---
name: personal-cloud
description: Use a Tarvis device as the user's personal cloud — install and run self-hosted apps (Uptime Kuma, Vaultwarden, any Coolify template or docker-compose), schedule recurring agent tasks that watch things and cast results to the screen, and store secrets for those tasks. Triggers on "run X on my box", "self-host X", "install X on the device", "watch this site and show changes on the TV", "morning summary on the screen", "schedule a task on the device". Only available when the token was approved with VM access.
---

# The device as a personal cloud

A paired Tarvis box can host apps and run scheduled agent tasks for the user.
Everything survives reboots. These tools appear only when the token was
approved with **Allow VMs & coding agents** and the device has the runtimes
installed; if `app_*`/`task_*` tools are missing, say so.

**Start with `device_status`.** For VM-scoped tokens it inventories what the
box is already running — hosted apps with URLs, scheduled tasks with their
last outcome, coding sessions — so you have context before adding anything.

## Two URLs per service

Every app and session comes with `url` (the LAN name — the service's label as a
subdomain of the device's own domain) and, when the owner enabled Tailscale for
the device, `tailscale_url` (the same label on the tailnet name). Both are real
https names covered by the device's own wildcard certificate; the device routes
them to the right port itself, so a new app is reachable over https the moment
it starts — no DNS or certificate step to run, and nothing to ask the user for.
The rule never changes: **on the same Wi-Fi as the box use `url`; anywhere else
use `tailscale_url`.** Hand the user whichever matches where they are, or both.

Never assemble these names yourself — read them from the tool's reply or
`device_status`. Until the device's domain is active (fresh pairing, no cert
yet) the same fields carry plain `http://<ip>:<port>` links instead — still
correct, just not https.

## Hosted apps

Apps are docker-compose projects run by the device (podman underneath). You
never touch the container engine: you hand over a template or compose, the
device sanitizes it, allocates ports, generates passwords, and runs it
with restart-on-boot persistence. The app's `name` becomes its subdomain, so
keep it a short lowercase label. Data lives on the encrypted data partition.

- `app_catalog` — curated slugs installable offline. Any other slug from
  Coolify's service directory (github.com/coollabsio/coolify,
  templates/compose) works too when the device has internet.
- `app_install` — `name` plus either `template` (a slug) or `compose` (YAML
  you write). Returns `url` / `tailscale_url` and any generated credentials —
  relay those to the user immediately, they are shown once.
- `app_list` / `app_start` / `app_stop` / `app_logs` / `app_remove`.

Writing compose yourself: images only (no `build:`), no privileged containers,
no host paths — bind mounts must be relative (they land in the app's own data
dir), named volumes are fine. Published ports are reallocated by the device;
the install result tells you where the app actually listens. `app_remove`
keeps data unless `purge: true` — confirm purge with the user first.

Install is as fast as the image pull: a small image is live on its https name
in under ten seconds, a large one takes many minutes and can return with a
`start_error` while layers are still coming down. Check `app_list` and read
`app_logs` before declaring failure; a retry of `app_start` resumes from cached
layers.

### Monitor what you host — in the background, never by stalling

Do not sit in a foreground loop polling an app you just installed; keep
working and let something else watch it:

- **Bring-up:** run the wait in a background process on your side (a shell
  loop curling the app URL until 200, or your harness's background/monitor
  facility) and report to the user when it flips. Your main loop stays free.
- **Ongoing health:** make monitoring durable on the device itself, not in
  your session. Two device-native options:
  - If Uptime Kuma (or similar) is hosted on the box, add the new app's URL
    as a monitor there — the device then watches itself 24/7.
  - Otherwise `task_create` a scheduled check: a headless agent that curls
    the app URL and casts/alerts only on failure. Every X minutes, zero cost
    while healthy, survives reboots. On-device checks use `url` (the box is
    on its own LAN); anything watching from elsewhere needs `tailscale_url`.

Rule of thumb: your attention ends when the app is up; the device's attention
is what watches it stay up.

## Scheduled tasks

A task runs a headless coding agent inside a sandboxed VM on a schedule. The
run gets this device's own MCP tools (a scoped short-lived token is minted per
run), so the prompt can end with "cast a summary to screen 1" and the agent
does it. Typical uses: watch a listings page and show changes on the TV, or a
morning digest at 07:30.

- The task's `agent` must be registered via `coding_agent_configure` with a
  `headless` command template — for Claude Code:
  `claude -p {prompt} --mcp-config /workspace/.tarvis-mcp.json --dangerously-skip-permissions`
- `task_create` — name, prompt, agent, then `schedule: interval` with
  `interval_minutes` (min 5) or `schedule: daily` with `daily_at` and
  `timezone`. `screen` picks the display. Missed runs while powered off run
  once at boot unless `catch_up_on_boot: false`.
- `task_run_now` tests it immediately; `task_runs` shows outcomes and the
  latest log tail. `task_update` with `enabled: false` pauses. Create a new task
  with `enabled: false`, prove it with `task_run_now`, then enable it — a broken
  prompt otherwise fails quietly on a schedule nobody is watching.

Each run is a fresh sandbox VM, so a trivial prompt is done in seconds and
nothing leaks between runs except the workspace.

## Logged-in sites without handing over credentials

Task workspaces persist between runs (`/workspace/.home`). To watch something
behind a login: start an interactive coding session in the task's workspace
(`coding_agent_start` with `workspace` set to the task's workspace name), have
the agent open the site and let the user complete the login through
`read`/`send`, then end the session. Scheduled runs in that workspace stay
logged in. The device never stores the account password.

## Secrets

`secret_set` stores a value encrypted on the device; reference it by name in
`task_create`'s `secrets` and it is exported as an env var inside the run.
Values are write-only — `secret_list` returns names, nothing returns a value.

## The user's view

The device's admin panel shows everything these tools set up, with stop/pause
controls. Don't treat the box as yours alone: name apps and tasks so the user
recognizes them there.
