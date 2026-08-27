---
name: personal-cloud
description: Use a Tarvis device as the user's personal cloud — install and run self-hosted apps (Uptime Kuma, Vaultwarden, any Coolify template or docker-compose), schedule recurring agent tasks that watch things and cast results to the screen, and store secrets that apps, tasks and coding sessions pick up as env vars. Triggers on "run X on my box", "self-host X", "install X on the device", "watch this site and show changes on the TV", "morning summary on the screen", "schedule a task on the device". Only available when the token was approved with VM access.
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
  relay those to the user immediately, they are shown once. **The URL works
  before the app does**: install returns as soon as the containers are up,
  while the app itself may still be migrating a database. Poll the URL until
  it answers 200 before you cast it to a screen or hand it over.
- `app_list` / `app_start` / `app_stop` / `app_restart` / `app_logs` / `app_remove`.
- `app_compose_get` reads back the compose the device is actually running, and
  `app_update` replaces it. That pair is how you fix a broken app: read what is
  there, correct it, update. Ports and generated passwords survive an update,
  so the app keeps its URL and credentials.

Writing compose yourself: images only (no `build:`), no privileged containers,
no host paths — bind mounts must be relative (they land in the app's own data
dir), named volumes are fine. Published ports are reallocated by the device;
the install result tells you where the app actually listens. `app_remove`
keeps data unless `purge: true` — confirm purge with the user first. It does
drop the app's image, since nothing else would ever reclaim it; reinstalling
pulls again.

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
- `task_list` inventories them; `task_delete` removes a task, its run history
  and its workspace, including anything it remembered or logged into.

Each run is a fresh sandbox VM, so a trivial prompt is done in seconds and
nothing leaks between runs except the workspace.

### A watcher must report only what changed

Tasks have durable memory on the device. Never invent a state file: a prompt
that writes its own JSON somewhere is the reason a watcher emails the same
listings every run.

`task_memory_new {items}` is the one call a watcher needs. Pass every item you
found as an object of id to a value that marks a change (a price, a timestamp,
a hash). It returns `new` (ids never reported) and `changed` (id to its previous
value) and remembers them in the same step, so a crash cannot double-report and
a run cannot forget to save. Report only the ids it hands back, and stay silent
when it returns nothing. Give each item an id that is stable between runs — a
listing or reference number, not a full URL, which can gain tracking parameters
and make an old item look new.

`task_memory_get` / `task_memory_set` keep arbitrary JSON between runs (a
threshold, a cursor, the last summary).

### Design the output once

A task that shows or emails anything keeps its presentation as files in its own
workspace, which persists between runs: `/workspace/templates/cast.html` and
`/workspace/templates/email.html`. The prompt tells the run to read them and to
design and write one only when it is missing — never paste markup into a task
prompt, or the model re-sends the whole page every run and the design drifts.
Keep one marker (`<!--ROWS-->`) and substitute the rows into it.

A cast template must fit one screen with no scrolling, because it is a TV that
nobody can scroll: `html,body{height:100%;margin:0;overflow:hidden}`, sizes in
`vh`/`vw` with `clamp()`, and a hard cap on rows with a "+N more" line. The
email has no such limit.

### Clear the screen after a while

Pass `expires_in_minutes` on every cast a task makes, about twice the interval
between runs. The screen stays current while the task keeps running and returns
to the splash on its own once it stops, instead of showing prices from hours
ago. A cast with a lifetime is not restored after a restart, which is what you
want for anything time sensitive.

## Telling the user something happened

`notify_channels` lists the channels the owner configured (email, ntfy,
pushover, telegram, ...); `notify_send` delivers to one with a title, a body and
an `html` flag for rich mail. A task like "email me X daily" is a scheduled task
whose prompt ends in `notify_send`.

Call `notify_send` without a channel: the device routes it to the task's own
channel when one is pinned, and to the owner's default otherwise. A task run
cannot read environment variables, so never look for one. The device drops
identical repeats and caps how many go out per hour, so a chatty task is
suppressed anyway. If no channel exists, tell the user to add one under Alerts
in the admin panel rather than inventing a delivery method.

## Logged-in sites without handing over credentials

Task workspaces persist between runs (`/workspace/.home`). To watch something
behind a login: start an interactive coding session in the task's workspace
(`coding_agent_start` with `workspace` set to the task's workspace name), have
the agent open the site and let the user complete the login through
`read`/`send`, then end the session. Scheduled runs in that workspace stay
logged in. The device never stores the account password.

## Secrets

`secret_set` stores a value encrypted on the device and says where it is
injected as an env var: `domain` is `app`, `task` or `session`, and `target`
names one of them. **Omit `target` and it reaches every one in that domain,
including ones created later** — so a key for a single app needs its name, or
every container on the box can read it.

When it takes effect differs by domain, and the reply tells you:

- **task** — the next run has it. Nothing to restart.
- **app** — the device rewrites that app's env and restarts it, then reports
  which apps it restarted.
- **session** — a session reads its environment only when it launches, so it
  needs a relaunch: `coding_agent_sleep` then `coding_agent_wake`. Waking a
  session that is still running only reattaches, so the sleep is what makes the
  new value arrive. The workspace and the agent's conversation survive.

A task may still name secrets in `task_create`'s `secrets` list; that and the
domain compose, so an older task keeps working.

Values are write-only — `secret_list` returns each name with where it applies,
nothing returns a value, and `secret_delete` removes one.

## The user's view

The device's admin panel shows everything these tools set up, with stop/pause
controls. Don't treat the box as yours alone: name apps and tasks so the user
recognizes them there.
