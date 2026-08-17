---
name: tarvis-vm
description: Run a coding agent inside a sandboxed micro-VM on a Tarvis device — clone a repo, start Claude Code or another agent on the box, read its output, and send it input. Use when the user wants work running on the device itself rather than on their laptop. Triggers on "start a coding agent on the box", "run this in a VM on the device", "spin up a sandbox and clone X", "what is the agent on the device doing", "reply to the agent session". Only available when the token was approved with VM access.
---

# Sandboxed coding agents on the device

The device runs coding agents inside microVMs — podman with the `krun`
(libkrun) runtime, one VM per session, each with its own guest kernel. These
tools appear only when the token was approved with **Allow VMs & coding
agents** and the runtime is installed. If `coding_*` tools are missing, say so
— don't try to work around it.

**Agents always run inside the VM, never on the device host.** That is the whole
security model. Nothing here gives you a shell on the box.

A session costs roughly 350 MB of device RAM while running and nothing while
asleep, so several can coexist on an 8 GB box.

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
- `coding_agent_wait` — block until a session settles. Pass `status: "idle"`
  (older device builds require it); `"working"` instead returns as soon as
  output starts.
- `coding_agent_sleep` / `coding_agent_wake` — park a session's VM to free RAM
  and bring it back later.
- `coding_workspace_remove` — delete a session's workspace for good.

`read`, `send` and `wait` name the session `target`; `sleep`, `wake`,
`save_login` and `workspace_remove` call it `name`. Recent devices accept
either, older ones don't, so use the one the tool asks for.

## Starting a session

Give it a `name` (the workspace key), the configured `agent`, and optionally a
`repo` and `branch`. Expect roughly 35 seconds from call to a live prompt —
plus a few minutes the very first time on a device, which pulls the ~165 MB
runtime image.

**The repo must be an `https://` URL.** The VM's network allows HTTP and TLS but
not general egress, so `git@github.com:...` will not connect. Rewrite SSH remotes
to https before passing them.

Each session name maps to a persistent workspace mounted at `/workspace` inside
the VM (the repo lands in `/workspace/repo`). Logins and installed tools survive
a restart of the same name — reuse the name to resume, pick a new one for
isolated work. `workspace` points a session at someone else's workspace, which
is how you log a scheduled task's agent in.

`memory_mb` and `cpus` size the VM (2 CPUs and ~3 GB by default); `ephemeral`
throws the workspace away when the session ends.

## Running one command instead of an agent

`command` replaces the agent with a command line. Write anything with `;`,
`&&` or a pipe as `sh -c 'foo; bar'` — recent devices run `command` as a shell
line, older ones as argv, and the explicit shell is right on both.

**A command that exits ends the session, and its output goes with it.** To see
a result, end the command with something that stays up (`sh`), or send it into
a session that is already alive with `coding_agent_send`.

## Showing a dev server on a screen

Pass `expose_port` to `coding_agent_start` with the guest port the app will
listen on (e.g. 3010 for `next dev -p 3010`). The reply includes a preview URL
— the session's own https name under the device's domain, plus a
`tailscale_url` when the device is on a tailnet (same LAN-vs-elsewhere rule as
every device address). Once the agent has the server running, cast that URL
with the **cast-to-screen** skill and the live app is on the TV. Only a session
whose name is a plain lowercase label (letters, digits, hyphens) gets an https
name; other names fall back to `http://<ip>:<port>`. The preview URL stays
stable across sleep/wake, so the loop is: talk to the session from your
laptop, the app hot-reloads on the screen. The dev server must bind 0.0.0.0
inside the VM, not 127.0.0.1.

## An isolated browser for the agent

Pass `browser: true` to give the session its own in-VM browser: Obscura, a
lightweight CDP-compatible engine that installs into `/workspace/.tools/bin`
and persists there. The agent starts it and connects Playwright over CDP to
verify its own dev server — click flows, DOM assertions, screenshots — without
touching any browser outside the sandbox. `"chromium"` selects full Chromium
instead when pixel-accurate rendering matters — heavier, and it reinstalls on
each wake. Each session's browser is fully isolated:
cookies and logins never leak between sessions or to the device.

## One login per device

Agent logins live in the session workspace, so the same session never asks
twice. To make every future session start signed in: configure the agent with
`login_paths` (for Claude Code: `.claude/.credentials.json` and
`.claude.json`), have the user log in once in any session, then call
`coding_agent_save_login` with that session's name. The files land on the
encrypted data volume and seed each new workspace. A revoked or expired login
is fixed the same way: log in once, save again.

## Private repos and git hosts

Connect the device once and every VM gets working git:

- GitHub: `github_connect` returns a code and URL — relay both, the user
  approves in their browser, poll `git_status` until connected.
- Any other host (GitLab, Bitbucket, Gitea, self-hosted): the user adds a
  personal access token in the device admin panel. Never ask for a token in
  chat.

Inside each VM, `~/.config/tarvis/git-hosts.json` lists the connected hosts;
the matching CLI (gh, glab, tea) is installed and token env vars are set, so
pick the provider's own commands for PRs or merge requests. Private repos
then clone straight from the `repo` argument of `coding_agent_start`.

## Sessions belong to the device

Disconnect whenever you like: the session keeps running on the box, and any
later paired agent finds it by name in `coding_sessions` and reattaches with
`read`/`send`. This is how a heavy Claude Code session runs on the device
instead of a struggling laptop.

Idle sessions sleep automatically after ~30 minutes of unchanged output
(`sleep_after_min` on start overrides; `-1` never). A sleeping session costs no
RAM; `coding_agent_wake` — or simply `coding_agent_send` — relaunches it in the
same workspace with the agent's `resume` flag, restoring the conversation.
Sleeping takes about ten seconds and waking about twenty. Pass
`persistent: true` on start to have the device relaunch the session after a
reboot; otherwise it is listed as `interrupted` until something wakes it.

## Reading and replying

Output is a terminal screen, not a stream: `coding_agent_read` returns what is
currently visible, so anything that scrolled past is gone. Ask for output that
fits, or have the agent write long results to a file in `/workspace`. Poll it,
or use `coding_agent_wait` with `status: "idle"`, which returns once the screen
has been still for a few seconds.

"Settled" means either finished *or* waiting for input. Read the output to tell
which, then `coding_agent_send` if it's a prompt. Interactive logins work this
way too — the agent's device-code prompt comes back through `read`, and you send
the answer through `send`.

The screen is narrow by default and lines wrap mid-word. A person who wants a
real terminal — full width, keys, colour — opens the session's console in the
device admin panel, which attaches to the very same tmux screen you are reading;
anything they type shows up in your next `read`.

## Pacing

Give `coding_agent_start` room before the first read, and prefer
`coding_agent_wait` over a tight read loop.

If everything is unusably slow, the device is likely falling back to software
emulation because `/dev/kvm` is missing. Mention it — that's a device setup
problem, not something to retry through.

## Showing the work

The VM's desktop is not castable through these tools. To put progress on a
screen, cast something the agent produces — a URL it serves, a file it writes —
with the **cast-to-screen** skill.
