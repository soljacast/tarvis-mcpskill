# Tarvis MCP

Drive a Tarvis device from any MCP-speaking agent: cast to its screens, read and
control the web pages it shows, and run sandboxed coding agents on the box.

The device runs the MCP server itself, so there is nothing to install and no
background process on your machine. This repo is the Claude Code plugin: the
connection config plus skills that teach an agent how to use the tools well.

## Install

```
/plugin marketplace add soljahub/tarvis-mcpskill
/plugin install tarvis@tarvis-mcpskill
```

You'll be asked for two things:

- **Device URL** — `http://soljacast.local`, or the device's IP or private
  https address.
- **Access token** — get one by opening `<device>/admin?mcp_login` in a browser,
  signing in as admin, and approving the connection. The device shows a code;
  paste it back where the terminal asks, and it becomes your token.

The token is stored in your OS keychain, never in a settings file. Revoke it any
time from **Manage → Settings → System → Connected agents** on the device.

## Without the plugin

Any MCP client can connect directly:

```bash
claude mcp add --transport http tarvis \
  http://soljacast.local/api/agent/v1/mcp \
  --header "Authorization: Bearer sca_..."
```

You get the tools but not the skills.

## What's in here

| Skill | Covers |
|---|---|
| `cast-to-screen` | Showing web pages, video, decks, images, text and audio on a screen; controlling what's showing |
| `drive-web-page` | Reading a casted page's accessibility tree and clicking, typing and navigating in it |
| `tarvis-vm` | Sandboxed Gondolin VMs and herdr coding-agent sessions (needs VM access on the token) |

## Development

Symlink this repo into your skills directory and it loads with no install step:

```bash
ln -s "$PWD" ~/.claude/skills/tarvis
```

It appears as `tarvis@skills-dir`. `SKILL.md` edits apply immediately;
`.mcp.json` changes need `/reload-plugins`.

Each skill carries `evals/evals.json` with test cases and a trigger set. Run
them with the official tooling:

```
/plugin marketplace add anthropics/claude-plugins-official
/plugin install skill-creator@claude-plugins-official
> evaluate my drive-web-page skill with skill-creator
```

## Safety

The token grants casting, page control, and — only if explicitly approved — VM
sessions. It cannot update or reboot the device, change its network, read
credentials, or reset it. Coding agents run inside micro-VMs, never on the host.

The skills also refuse to type passwords, card numbers, 2FA codes, or solve
captchas. When a page needs one, they hand off to `<device>/admin`, where a live
interactive preview lets you finish the step yourself and the agent resumes.
