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
Device-owned internal services cannot be targeted with user app tools.
Chat management requires an external device token with VM access; internal
chat/task tokens and domain-scoped tokens do not expose `chat_*`.

**Start with `device_status`.** For VM-scoped tokens it inventories what the
box is already running — hosted apps with URLs, scheduled tasks with their
last outcome, coding sessions — so you have context before adding anything.
Before installing or starting an app, call `workspace_resources` and respect
its admission result. Unknown resource metrics are not spare capacity, and its
generic estimates do not replace an app's documented requirements.

## Two URLs per service

Every app and session comes with `url` (the LAN name — the service's label as a
subdomain of the device's own domain) and, when the owner enabled Tailscale for
the device, `tailscale_url` (the same label on the tailnet name). Both are real
https names covered by the device's own wildcard certificate; the device routes
them to the right port itself, so a new app is reachable over https the moment
it starts — no DNS or certificate step to run, and nothing to ask the user for.
For a local device, use `url` on its LAN and `tailscale_url` for remote access
when Tailscale is configured. Cloud deployments may expose a reachable public
`url`. Use the addresses returned by the device and the user's connectivity;
do not assume every deployment requires the same Wi-Fi.

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

- `app_catalog` — curated slugs installable offline. Use `query`, `offset` and
  `limit` for targeted or paged discovery, following `has_more`. Any other slug
  from Coolify's service directory (github.com/coollabsio/coolify,
  templates/compose) works too when the device has internet.
- `app_install` — `name` plus either `template` (a slug) or `compose` (YAML
  you write). Returns `url` / `tailscale_url` and any generated credentials —
  relay those to the user immediately, they are shown once. **The URL works
  before the app does**: install returns as soon as the containers are up,
  while the app itself may still be migrating a database. Poll the URL until
  it answers 200 before you cast it to a screen or hand it over.
- `app_list` / `app_start` / `app_stop` / `app_logs` / `app_remove`.
- `app_request` calls an installed app's HTTP API internally without going
  through browser SSO. The app's own authentication still applies. In task
  calls, headers can use `${ENV_NAME}` and JSON values can use
  `{"$secret":"ENV_NAME"}`. Prefer `save_response` for login/token responses
  so selected fields are encrypted as task secrets without entering messages
  or logs. Redirects are returned rather than followed and responses are capped.
- `app_compose_get` reads the current compose and `env_keys` (variable names
  only). It omits all `.env` values; preserve `${NAME}` references when editing.
  `app_update` changes
  compose while retaining data; `app_restart` restarts without reinstalling.
- `app_source_fetch` clones an HTTPS repo (optional `branch`) or snapshots a
  coding `workspace`. Re-fetching replaces prior source. `app_source_read`
  and `app_source_write` inspect and edit source files, including a Dockerfile.
  Builds run in the background: check `app_list` phase and `last_error`.
  `app_autoupdate` enables or disables deploy-on-push for repo-sourced apps;
  enable it when requested.
- `app_storage` reports disk usage; `app_backups` lists configured backup jobs;
  `app_backup_run` starts one by name. Backups can stop covered apps temporarily.
  See Backups below for configuration, schedules and restores.

Writing compose yourself: images or `build: {context: ./src}` using source
fetched with `app_source_fetch`; no privileged containers and no ordinary host
paths — bind mounts must be relative (they land in the app's own data dir), and
named volumes are fine. Supported workspaces recognize a CI runner's standard
container-engine declaration and provide an isolated, app-scoped capability.
If a runner needs that capability later without declaring it in Compose,
identify only the consumer service:

```yaml
x-tarvis:
  capabilities:
    container_engine:
      services: [runner]
```

The managed capability follows the app lifecycle. Do not add a nested daemon,
privileged mode, or host-engine access. If the workspace does not accept the
capability, report that limitation rather than weakening the Compose.
Published ports are reallocated by the device;
the install result tells you where the app actually listens. `app_remove`
keeps data unless `purge: true` — confirm purge with the user first.

Install is as fast as the image pull: a small image is live on its https name
in under ten seconds, a large multi-service one takes minutes and can return
while layers are still coming down. Check `app_list` and read `app_logs`
before declaring failure; a retry of `app_start` resumes from cached layers.

Use images matching the deployment architecture: physical devices commonly use
arm64, while cloud workspaces may use amd64. Prefer multi-architecture images;
do not assume an ARM-only image will run on a VPS (or the reverse).

`app_list` reports `last_error` for an app that is meant to be running and
isn't, and the app's own URL says the same thing rather than a bare port
error. Read it before guessing; image architecture mismatches need a compatible image.

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
run before creating or changing a task. It also returns explicit `secrets`
(names only) and `catch_up_on_boot`, so those settings can be inspected before
editing. Runs execute in a sandbox and continue
in the background. A cloud workspace has no display; include casting only on
a device with a screen.

- `task_create`: `name`, `prompt`, optional `agent` and `workspace`;
  `schedule: interval` with `interval_minutes` (minimum 5), or `schedule: daily`
  with `daily_at` (`HH:MM`) and `timezone`. The default is hourly. Omit `agent`
  to use the built-in agent when available; other agents need a configured
  headless command via `coding_agent_configure`. Put credential names the task
  will need in `required_secrets`; creation succeeds but execution waits while
  any are missing, and the task's Secrets UI attaches them when supplied.
- Creation queues a first run automatically once required credentials are
  available. Do not immediately call
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
- `task_memory_new` returns new, changed, and previously unacknowledged items.
  They stay pending across failures and retries. Call `task_memory_ack` with
  the same ID-to-value entries only after all required processing and delivery
  succeeds; never acknowledge merely because items were fetched. Use
  `task_memory_get` / `task_memory_set` for other persistent JSON.
- `task_secret_list` lists credential names assigned to the current task, never
  their values. `task_secret_set` stores a credential for that task only. For
  API login responses, prefer `app_request.save_response` so the credential is
  encrypted without appearing in a message or log.
- `task_instructions_correct` is available only inside a task run. Use it to
  replace one exact instruction passage after a successful operation proves
  the correction. Preserve the owner's goal, schedule, delivery and secret
  references; never persist a guess, temporary outage, or credential value.

Task workspaces retain `/workspace/.home` between runs. For a logged-in site,
an interactive coding session can share the task's workspace so the user can
complete login once and future runs retain it.

## Secrets and vars

`secret_set` stores `name`, `value`, and `domain` (`app`, `task`, or `session`).
`target` selects one named app/task/session; omit it for every resource in that
domain, including future ones. Set the narrow target the user intends.

`secret: true` is the default: encrypted at rest, with its value omitted from
`secret_list`, and redacted in run logs. This is not isolation from an agent authorized to
read app configuration or execute code in a runtime receiving that secret.
`app_compose_get` omits `.env` values and returns their names only. Compose YAML
is returned as written, so credentials manually embedded in YAML remain visible. Never echo the submitted value. `secret: false` stores a var whose
value is visible through `secret_list` and in logs. `secret_list` reports names,
domains, targets and secrecy flags; only vars return values. `secret_delete`
removes an entry by name. Setting or deleting app configuration reloads affected
apps automatically; tasks pick it up on their next run, sessions on restart.

A secret entered through a chat's Secrets UI belongs to that chat, is saved
before its first message, and is injected into its turns without exposing the
value in history. Inside the owning chat, `secret_assign` can copy it to one
named app, task, or coding session without reading the value. Reassign it after
rotation. Only the owning device chat can call `secret_assign`; external paired
clients cannot invoke it directly.

## Backups

`app_backups` returns job IDs, configuration with stored credentials redacted,
engine readiness, current activity and the last restore result.

- `app_backup_create` takes `name`, `apps` (names), `destination` and optional
  `schedule`. A schedule has `kind: off`, `daily` with `daily_at` and `timezone`,
  or `interval` with `interval_minutes` (minimum 15). Defaults: schedule off,
  `encrypt: true`, `stop_apps: true` for consistent data.
- `destination` contains `kind` and string-valued `fields`. Inspect the tool
  schema for required fields: local folder, S3, B2, WebDAV, SFTP and drive
  destinations are supported. A local folder is a plain name within managed
  backup storage, not an arbitrary host path. `app_backup_destination_test`
  verifies connectivity and may create the destination folder.
- Drive sign-in: `app_backup_oauth_start` takes `kind` googledrive, onedrive or
  dropbox. Give its login URL to the user. After approval,
  `app_backup_oauth_fetch` takes the returned token and reports pending or a
  one-time `authid`; put that in destination fields without echoing it.
- Encrypted creation returns the supplied or generated recovery passphrase.
  Preserve it securely for the user. Stored destination credentials and
  passphrases have no readback tool. Encryption/passphrase changes after the
  first backup require a new job.
- `app_backup_update` takes `id` and the fields to change. Omitted settings are
  retained; a supplied `schedule` replaces the schedule object. Omitting the
  destination or leaving its stored secret fields blank preserves credentials.
- `app_backup_prepare` prepares the engine in the background. `app_backup_run`
  starts an existing job by **name**; other management tools use its **id**.
  Read `app_backups` for progress and results.
- Restore: `app_backup_versions` takes `id`; `app_backup_version_apps` takes
  `id` and the exact returned `time`. `app_backup_restore` takes `id`, `time`
  and `apps: [{name, as_new?}]`. Omitting `as_new` overwrites existing app data;
  supplying it creates a new app with that name. Use the destination the user
  authorized. Restore starts in the background; check `app_backups` for its
  final result before reporting success.
- `app_backup_delete` removes the job by `id`, keeping destination files by
  default. Set `delete_remote: true` only when the user requested removal of
  the backup files too.

## Notifications

`notify_channels` lists channel names/types, the default, hourly limits and
recent delivery health; credentials are not returned. `notify_services`
discovers the engine's supported services and configuration fields.

- `notify_channel_add` takes `name` and an Apprise `url`, adding or replacing
  the channel. The first channel becomes default. Store credential-bearing
  URLs without echoing them.
- `notify_channel_default` chooses a default by `name`;
  `notify_channel_limit` sets `max_per_hour` (non-negative; zero restores the
  service default). `notify_channel_delete` removes the named channel.
- `notify_channel_test` sends a real test message, bypassing deduplication and
  hourly limits. Use it to verify a requested setup, not as a retry bypass.
- `notify_send` sends ordinary notifications using the tool's schema. Task
  runs can omit the channel to use the task's channel or the owner's default.
  If setup is needed and authorized, configure a channel; otherwise explain
  what is missing. Add ongoing monitoring when the user's request includes it.

## Choosing agents, models and repositories

`agent_list` shows configured agents, sign-in status, headless commands and
credential variable names, without credential values. `agent_models` lists
models for a configured `agent`; `agent_auth_status` checks its authentication.
For a new provider, use `provider_list` then `provider_models` with `provider_id`
or a compatible `base_url`/`npm` and optional `key`. Discovery stores nothing;
configure the chosen agent using `coding_agent_configure`.

`git_status` shows connected Git hosts. `git_repos` lists accessible
repositories, reporting partial host failures alongside successful results.
`git_branches` takes `host` and `repo` (owner/project). Use these to select a
real source branch before fetching app source or starting a coding session.
`git_disconnect` removes one connected host only when the user asks to revoke
that connection.

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
- A general chat uses `continue_in_code` when the user asks it to implement an
  application or feature, fix code, or load a repository. It creates a separate
  coding session with the same agent/model, securely copies chat-scoped secrets
  and recent attachments, queues a self-contained implementation brief, and
  switches the user to Code. The original chat remains a normal chat and is not
  duplicated in the Code list. Repeated handoff calls return the same destination.
  This is an internal tool of the owning chat; an external paired client sends
  the request with `chat_send` and observes the resulting handoff/history.

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
