---
name: tarvis-vm
description: Run a coding agent inside a sandboxed micro-VM on a Tarvis device — clone a repo, start Claude Code or another agent on the box, read its output, and send it input. Use when the user wants work running on the device itself rather than on their laptop. Triggers on "start a coding agent on the box", "run this in a VM on the device", "spin up a sandbox and clone X", "what is the agent on the device doing", "reply to the agent session". Only available when the token was approved with VM access.
---

# Sandboxed coding agents on the device

The device can run coding agents inside [Gondolin](https://github.com/earendil-works/gondolin)
micro-VMs, multiplexed by herdr. These tools appear only when the token was
approved with **Allow VMs & coding agents** and the device has both binaries
installed. If `coding_*` tools are missing, say so — don't try to work around it.

**Agents always run inside the VM, never on the device host.** That is the whole
security model. Nothing here gives you a shell on the box.

## The tools

- `coding_agent_configure` — register an agent once: its run command, its
  install command, and the credential env vars it needs. Stored 0600 on the
  device. Do this before the first `start` for a given agent. Optional fields:
  `headless` (a non-interactive command template for scheduled tasks, with
  `{prompt}` replaced per run) and `resume` (a flag appended on wake so the
  agent restores its conversation — `--continue` for Claude Code).
- `coding_agent_start` — create a workspace, clone a repo, and launch the agent.
- `coding_sessions` — list sessions, including saved ones that survived a
  device restart.
- `coding_agent_read` — read a session's recent output.
- `coding_agent_send` — type into a session (answering a prompt, giving an instruction).
- `coding_agent_wait` — block until a session settles or a timeout expires.
- `coding_agent_sleep` / `coding_agent_wake` — park a session's VM to free RAM
  and bring it back later.

## Starting a session

Give it a `name` (the workspace key), the configured `agent`, and optionally a
`repo` and `branch`.

**The repo must be an `https://` URL.** The VM's network allows HTTP and TLS but
not general egress, so `git@github.com:...` will not connect. Rewrite SSH remotes
to https before passing them.

Each session name maps to a persistent workspace at
`~/.soljacast/gondolin/workspaces/<name>`, mounted at `/workspace` inside the VM.
Logins and installed tools survive a restart of the same name — reuse the name
to resume, pick a new one for isolated work.

## Showing a dev server on a screen

Pass `expose_port` to `coding_agent_start` with the guest port the app will
listen on (e.g. 3010 for `next dev -p 3010`). The reply includes a device LAN
preview URL; once the agent has the server running, cast that URL with the
**cast-to-screen** skill and the live app is on the TV. The preview URL stays
stable across sleep/wake, so the loop is: talk to the session from your
laptop, the app hot-reloads on the screen. The dev server must bind 0.0.0.0
inside the VM, not 127.0.0.1.

## An isolated browser for the agent

Pass `browser: true` (or `"obscura"`) to give the session its own in-VM
browser: Obscura, a lightweight CDP-compatible engine that persists in the
workspace. The agent connects Playwright over CDP to it and verifies its own
dev server — click flows, DOM assertions, screenshots — without touching any
browser outside the sandbox. Pass `"chromium"` when pixel-accurate rendering
matters; it is much heavier and reinstalls on each wake. Each session's
browser is fully isolated: cookies and logins never leak between sessions or
to the device.

## Private repos

The VM has no credentials. Don't put tokens in the start call — start the
session without `repo`, then have the agent run `gh auth login` inside: the
device-code prompt comes back through `read`, the user approves it in their
own browser, and the agent clones after. The login persists in the workspace.

## Sessions belong to the device

Disconnect whenever you like: the session keeps running on the box, and any
later paired agent finds it by name in `coding_sessions` and reattaches with
`read`/`send`. This is how a heavy Claude Code session runs on the device
instead of a struggling laptop.

Idle sessions sleep automatically after ~30 minutes of unchanged output
(`sleep_after_min` on start overrides; `-1` never). A sleeping session costs no
RAM; `coding_agent_wake` — or simply `coding_agent_send` — relaunches it in the
same workspace with the agent's `resume` flag, restoring the conversation.
Pass `persistent: true` on start to have the device relaunch the session after
a reboot; otherwise it is listed as `interrupted` until something wakes it.

## Reading and replying

Output is a terminal screen, not a stream: `coding_agent_read` returns what's
currently visible, capped at a few thousand bytes. Poll it, or use
`coding_agent_wait`, which reports `working` while the screen keeps changing and
returns once it has been still for a few seconds.

"Settled" means either finished *or* waiting for input. Read the output to tell
which, then `coding_agent_send` if it's a prompt. Interactive logins work this
way too — the agent's device-code prompt comes back through `read`, and you send
the answer through `send`.

## Pacing

VM startup is slow, especially on a cold image. Give `coding_agent_start` room
before the first read, and prefer `coding_agent_wait` over a tight read loop.

If everything is unusably slow, the device is likely running QEMU without KVM.
Mention it — that's a device setup problem, not something to retry through.

## Showing the work

The VM's desktop is not castable through these tools. To put progress on a
screen, cast something the agent produces — a URL it serves, a file it writes —
with the **cast-to-screen** skill.
