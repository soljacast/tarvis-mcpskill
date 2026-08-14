#!/usr/bin/env python3
"""Integration evals for the Tarvis device MCP surface.

Runs deterministic tool-level scenarios against a paired device and asserts
outcomes, so skill logic regressions surface without an LLM in the loop.

Auth: TARVIS_MCP_URL + TARVIS_MCP_TOKEN env vars, or the claude-code config
written by the pairing script (first project with a tarvis server).

Safe by default: no screen changes, no app installs; everything created is
named eval-* and removed afterwards. --with-screen adds cast checks (restores
nothing casted before, so only use on a test device). --with-vm adds a real
VM session round-trip (slow on first image download).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request

RESULTS: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    RESULTS.append((name, ok, detail))
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail and not ok else ""))


def find_server() -> tuple[str, str]:
    url, token = os.getenv("TARVIS_MCP_URL"), os.getenv("TARVIS_MCP_TOKEN")
    if url and token:
        return url, token
    cfg = os.path.expanduser("~/.claude.json")
    data = json.load(open(cfg))
    for proj in data.get("projects", {}).values():
        srv = proj.get("mcpServers", {}).get("tarvis")
        if srv and srv.get("url"):
            auth = srv.get("headers", {}).get("Authorization", "")
            return srv["url"], auth.removeprefix("Bearer ").strip()
    sys.exit("no tarvis MCP server configured; set TARVIS_MCP_URL and TARVIS_MCP_TOKEN")


class Client:
    def __init__(self, url: str, token: str):
        self.url, self.token = url, token

    def rpc(self, method: str, params: dict | None = None):
        body = {"jsonrpc": "2.0", "id": 1, "method": method}
        if params is not None:
            body["params"] = params
        req = urllib.request.Request(self.url, data=json.dumps(body).encode(), method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("Accept", "application/json, text/event-stream")
        req.add_header("Authorization", "Bearer " + self.token)
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read().decode()
        for line in raw.splitlines():
            if line.startswith("data: "):
                raw = line[6:]
                break
        return json.loads(raw)

    def call(self, tool: str, args: dict | None = None) -> tuple[str, bool]:
        res = self.rpc("tools/call", {"name": tool, "arguments": args or {}})
        result = res.get("result", {})
        text = "".join(c.get("text", "") for c in result.get("content", []))
        return text, bool(result.get("isError"))

    def tools(self) -> set[str]:
        res = self.rpc("tools/list", {})
        return {t["name"] for t in res.get("result", {}).get("tools", [])}


def eval_surface(c: Client) -> dict:
    tools = c.tools()
    core = {"device_status", "cast_content", "cast_stop", "screen_screenshot", "page_snapshot"}
    check("core tools present", core <= tools, str(core - tools))
    features = {
        "vm": "coding_agent_start" in tools,
        "apps": "app_install" in tools,
        "tasks": "task_create" in tools,
        "secrets": "secret_set" in tools,
    }
    text, err = c.call("device_status")
    status = json.loads(text) if not err else {}
    check("device_status answers", not err and "screens" in status)
    if features["vm"]:
        check("inventory advertised", "token" in status)
    return features


def eval_secrets(c: Client) -> None:
    name = "EVAL_PROBE_SECRET"
    text, err = c.call("secret_set", {"name": name, "value": "eval-value"})
    check("secret_set", not err, text)
    text, err = c.call("secret_list")
    check("secret_list names only", not err and name in text and "eval-value" not in text, text[:120])
    text, err = c.call("secret_set", {"name": "bad name!", "value": "x"})
    check("secret_set rejects bad name", err or "error" in text.lower(), text[:120])
    text, err = c.call("secret_delete", {"name": name})
    check("secret_delete", not err, text)
    text, _ = c.call("secret_list")
    check("secret gone", name not in text, text[:120])


def eval_tasks(c: Client) -> None:
    for label, args in {
        "bad task name": {"name": "Bad Name", "prompt": "x", "agent": "nope"},
        "unknown agent": {"name": "eval-task", "prompt": "x", "agent": "no-such-agent"},
        "interval too small": {"name": "eval-task", "prompt": "x", "agent": "no-such-agent",
                               "schedule": "interval", "interval_minutes": 1},
        "bad daily time": {"name": "eval-task", "prompt": "x", "agent": "no-such-agent",
                           "schedule": "daily", "daily_at": "25:99"},
    }.items():
        text, err = c.call("task_create", args)
        check(f"task_create rejects {label}", err or "error" in text.lower(), text[:120])
    text, err = c.call("task_list")
    check("task_list answers", not err, text[:120])


def eval_apps(c: Client) -> None:
    text, err = c.call("app_catalog")
    check("app_catalog lists slugs", not err and "uptime-kuma" in text, text[:120])
    bad = "services:\n  app:\n    image: x\n    privileged: true\n"
    text, err = c.call("app_install", {"name": "eval-bad", "compose": bad})
    check("sanitizer rejects privileged", err and "privileged" in text, text[:160])
    escape = "services:\n  app:\n    image: x\n    volumes: ['/etc:/host']\n"
    text, err = c.call("app_install", {"name": "eval-bad", "compose": escape})
    check("sanitizer rejects host bind", err and "relative" in text, text[:160])
    text, err = c.call("app_list")
    check("app_list answers", not err, text[:120])


def eval_vm(c: Client) -> None:
    name = "eval-vm"
    text, err = c.call("coding_agent_start",
                       {"command": "sh", "name": name, "expose_port": 3010})
    ok = not err and "preview at http://" in text
    check("session start with expose_port", ok, text[:200])
    if not ok:
        return
    deadline = time.time() + 240
    settled = ""
    while time.time() < deadline:
        settled, _ = c.call("coding_agent_read", {"target": name, "lines": 10})
        if "/workspace" in settled:
            break
        time.sleep(10)
    check("VM shell reachable", "/workspace" in settled, settled[-160:])
    text, err = c.call("coding_agent_sleep", {"name": name})
    check("session sleeps", not err and "sleeping" in text, text[:120])
    text, err = c.call("coding_agent_wake", {"name": name})
    check("session wakes with same preview", not err and "http://" in text, text[:160])
    c.call("coding_agent_sleep", {"name": name})
    text, err = c.call("coding_workspace_remove", {"name": name})
    check("workspace cleanup", not err and "Deleted" in text, text[:120])


def eval_screen(c: Client) -> None:
    text, err = c.call("cast_content",
                       {"screen": 1, "content_type": "text", "title": "Eval probe",
                        "content": "device evals ran"})
    check("cast text", not err, text[:120])
    text, err = c.call("cast_status")
    check("cast_status reflects cast", not err and "Eval probe" in text, text[:160])
    text, err = c.call("cast_stop", {"screen": 1})
    check("cast_stop", not err, text[:120])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--with-screen", action="store_true")
    ap.add_argument("--with-vm", action="store_true")
    opts = ap.parse_args()

    url, token = find_server()
    print(f"target: {url}\n")
    c = Client(url, token)
    features = eval_surface(c)
    if features["secrets"]:
        eval_secrets(c)
    if features["tasks"]:
        eval_tasks(c)
    if features["apps"]:
        eval_apps(c)
    if opts.with_vm and features["vm"]:
        eval_vm(c)
    if opts.with_screen:
        eval_screen(c)

    failed = [r for r in RESULTS if not r[1]]
    print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
