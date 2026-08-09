---
name: tarvis-vm
description: Run a coding agent inside a sandboxed micro-VM on a Tarvis device — clone a repo, start Claude Code or another agent on the box, read its output, and send it input. Use when the user wants work running on the device itself rather than on their laptop.
when_to_use: Triggers on "start a coding agent on the box", "run this in a VM on the device", "spin up a sandbox and clone X", "what is the agent on the device doing", "reply to the agent session". Only available when the token was approved with VM access.
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
  device. Do this before the first `start` for a given agent.
- `coding_agent_start` — create a workspace, clone a repo, and launch the agent.
- `coding_sessions` — list the sessions this pack created.
- `coding_agent_read` — read a session's recent output.
- `coding_agent_send` — type into a session (answering a prompt, giving an instruction).
- `coding_agent_wait` — block until a session settles or a timeout expires.

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
