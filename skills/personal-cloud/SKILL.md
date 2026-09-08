---
name: personal-cloud
description: Manage self-hosted apps, scheduled agent tasks, secrets and vars, and device assistant chats on a Tarvis device or cloud workspace. Use for installing or repairing an app, changing a task schedule, inspecting runs and workspace files, managing injected configuration, or continuing a device chat. Requires a paired token with VM access.
---

# The device as a personal cloud

A paired Tarvis device or cloud workspace can host apps, run scheduled agent tasks,
and maintain assistant chats for the user.
Everything survives reboots. These tools appear only when the token was
approved with **Allow VMs & coding agents** and the device has the runtimes
installed; if a tool is missing, inspect the advertised catalog before using it.
Chat management requires an external device token with VM access; internal
chat/task tokens and domain-scoped tokens do not expose `chat_*`.

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
  relay those to the user immediately, they are shown once. **The URL works
  before the app does**: install returns as soon as the containers are up,
  while the app itself may still be migrating a database. Poll the URL until
  it answers 200 before you cast it to a screen or hand it over.
- `app_list` / `app_start` / `app_stop` / `app_logs` / `app_remove`.
- `app_compose_get` reads the current compose and env; `app_update` changes
  compose while retaining data; `app_restart` restarts without reinstalling.
- `app_source_fetch` clones an HTTPS repo (optional `branch`) or snapshots a
  coding `workspace`. Re-fetching replaces prior source. `app_source_read`
  and `app_source_write` inspect and edit source files, including a Dockerfile.
  Builds run in the background: check `app_list` phase and `last_error`.
  `app_autoupdate` enables or disables deploy-on-push for repo-sourced apps;
  enable it when requested.
- `app_storage` reports disk usage; `app_backups` lists configured backup jobs;
  `app_backup_run` starts one by name. Backups can stop covered apps temporarily.
  Destination changes and restores use the admin Backups dialog.

Writing compose yourself: images or `build: {context: ./src}` using source
fetched with `app_source_fetch`; no privileged containers,
no host paths — bind mounts must be relative (they land in the app's own data
dir), named volumes are fine. Published ports are reallocated by the device;
the install result tells you where the app actually listens. `app_remove`
keeps data unless `purge: true` — confirm purge with the user first.

Install is as fast as the image pull: a small image is live on its https name
in under ten seconds, a large multi-service one takes minutes and can return
while layers are still coming down. Check `app_list` and read `app_logs`
before declaring failure; a retry of `app_start` resumes from cached layers.

**These devices are arm64, so pick images that are.** An x86-only image
installs cleanly, then dies the instant it execs — nothing retries it, and no
amount of restarting helps. Prefer a multi-arch image, and when a template
pins one that isn't (CyberChef's own `ghcr.io/gchq/cyberchef` is x86-only, for
instance), write the compose yourself against an image that publishes arm64 —
`mpepping/cyberchef` in that case. Docker Hub's tag list shows the
architectures.

`app_list` reports `last_error` for an app that is meant to be running and
isn't, and the app's own URL says the same thing rather than a bare port
error. Read it before guessing: it names the arm64 case outright.

### Monitor what you host — in the background, never by stalling

Do not sit in a foreground loop polling an app you just installed; keep
working and let something else watch it:

- **Bring-up:** run the wait in a background process on your side (a shell
  loop curling the app URL until 200, or your harness's background/monitor
  facility) and report to the user when it flips. Your main loop stays free.
- **Ongoing health:** when requested, make monitoring durable on the device itself, not in
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

Use `task_list` to inspect existing prompts, schedules, workspaces and the last
run before creating or changing a task. Runs execute in a sandbox and continue
in the background. A cloud workspace has no display; include casting only on
a device with a screen.

- `task_create`: `name`, `prompt`, optional `agent` and `workspace`;
  `schedule: interval` with `interval_minutes` (minimum 5), or `schedule: daily`
  with `daily_at` (`HH:MM`) and `timezone`. The default is hourly. Omit `agent`
  to use the built-in agent when available; other agents need a configured
  headless command via `coding_agent_configure`.
- Creation queues a first run automatically. Do not immediately call
  `task_run_now` as an extra setup step. `enabled: false` pauses scheduled
  runs; it is not a guarantee that creation performs no work.
- `task_update` changes supplied fields; `enabled: false` pauses the schedule.
  `catch_up_on_boot` controls catching up after downtime. `budget_minutes`
  is 1–30 (default 10); `self_heal` controls automatic repair after failures.
  `notify_channel` is a name from `notify_channels`, `none` for logs only,
  or `-` on update to restore the owner's default. `secrets` lists stored
  names exported into runs; an empty list clears the explicit selection.
- `task_run_now` starts an additional run and returns its run ID. Report it as
  started, then use `task_runs` to inspect progress when appropriate. Do not
  keep a foreground turn waiting or repeatedly poll for completion.
- `task_runs` lists statuses, attempts, result/needs and the latest log tail.
  `task_run_log` takes `name` and `run` (ID from `task_runs`) for the full log.
  Secret values are redacted. A closing `RESULT:` describes the outcome;
  `NEEDS:` asks the owner for input. Queued or running is not success.
- `task_stop` stops the active run or waiting retry, retaining the schedule.
  Use `task_update` as well if the user wants future runs paused.
  `task_delete` removes the task, history and workspace.
- `task_files`, `task_file_read` and `task_file_write` access the persistent
  task workspace by `name` and relative `path`. Writes also take `content`.
  A run sees files at `/workspace/<path>`; your local filesystem is separate.
- `task_memory_new` remembers observed items and returns new or changed ones.
  `task_memory_get` / `task_memory_set` retain arbitrary JSON across runs;
  inspect the tool schema for their fields.

Task workspaces retain `/workspace/.home` between runs. For a logged-in site,
an interactive coding session can share the task's workspace so the user can
complete login once and future runs retain it.

## Secrets and vars

`secret_set` stores `name`, `value`, and `domain` (`app`, `task`, or `session`).
`target` selects one named app/task/session; omit it for every resource in that
domain, including future ones. Set the narrow target the user intends.

`secret: true` is the default: encrypted at rest, write-only, and redacted in
run logs. Never echo the submitted value. `secret: false` stores a var whose
value is visible through `secret_list` and in logs. `secret_list` reports names,
domains, targets and secrecy flags; only vars return values. `secret_delete`
removes an entry by name. Setting or deleting app configuration reloads affected
apps automatically; tasks pick it up on their next run, sessions on restart.

## Notifications

`notify_channels` lists available delivery channels. `notify_send` sends a
notification using the tool's schema. Task runs can omit the channel to use
the task's configured channel or the owner's default. With no channel available,
report that delivery is unavailable. Add ongoing monitoring or notifications
when the user's request includes them.

## Device assistant chats

Use these when the user wants to manage or talk to an assistant conversation
on the device. Direct app/task/secret tools perform their respective operations
without needing a chat turn.

- `chat_list` returns conversation IDs, previews and working state. `apps` and
  `tasks` are the fixed assistants.
- `chat_create` opens a general conversation (optional `title` and `agent`).
  For an existing coding session, pass `kind: session` and its `session` name;
  create the coding session with the coding tools first if needed. Creation
  alone sends nothing.
- `chat_history` takes `id`, optional `limit` (1–200, default 60) and `before`
  (message ID). Messages are chronological; if `has_more`, use the oldest
  returned message's ID as `before` to read the preceding page. It also reports
  `thinking`, available `agents`, and `terminal_open`.
- `chat_send` takes `id` and `text`. It returns the accepted user message while
  the assistant works in the background; read `chat_history` for the reply.
  An open coding terminal prevents a session chat turn; the user must close it.
- `chat_upload` takes `id`, `filename`, and base64 `data` (up to 16 MiB decoded).
  Pass its returned `attachment` in `chat_send`'s `attachments` array for the
  same chat. Uploading a file does not send a message.
- `chat_rename` changes `title`. `chat_set_agent` selects an `agent` listed by
  history; an empty string restores automatic selection.
- `chat_cancel` stops the current turn and clears queued messages, retaining
  history. `chat_delete` removes history and a general chat's scratch workspace;
  a coding session's workspace stays. Fixed Apps and Tasks chats cannot be deleted.

## Clients without MCP tool access

The same token-scoped catalog is available over HTTP:
`GET /api/agent/v1/tools` and `POST /api/agent/v1/tools/call`, both with
`Authorization: Bearer <device-token>`. The call body is
`{"name":"task_list","arguments":{}}`; substitute a listed name and its schema's
arguments. Use these endpoints rather than admin-cookie routes. A missing tool
can mean an older device version, insufficient token scope, or an unavailable
service; do not assume the skill installs backend capabilities.

## The user's view

The device's admin panel shows everything these tools set up, with stop/pause
controls. Don't treat the box as yours alone: name apps and tasks so the user
recognizes them there.
