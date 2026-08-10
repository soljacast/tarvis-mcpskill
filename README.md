# Tarvis MCP

Drive a Tarvis device from any MCP-speaking agent: cast to its screens, read and
control the web pages it shows, and run sandboxed coding agents on the box.

The device runs the MCP server itself, so there is nothing to install and no
background process on your machine. This repo is the Claude Code plugin: the
connection config plus skills that teach an agent how to use the tools well.

## Install

Pick your client. All of them talk to the same MCP server on the device; only
Claude Code gets the skills, which teach an agent *how* to use the tools well.

### Claude Code

```
/plugin marketplace add soljacast/tarvis-mcpskill
/plugin install tarvis@tarvis-mcpskill
```

Two commands because the first registers the repo as a marketplace and the
second installs the plugin from it. You'll be asked for two things:

- **Device URL** — use the device's https name if it has one (see below);
  `http://soljacast.local` works too.
- **Access token** — get one by opening `<device>/admin?mcp_login` in a browser,
  signing in as admin, and approving the connection. The device shows a code;
  paste it back where the terminal asks, and it becomes your token.

The token is stored in your OS keychain, never in a settings file. Revoke it any
time from **Manage → Settings → System → Connected agents** on the device.

### Claude Desktop, Cursor, Zed, Cline

These take an MCP config file rather than a plugin. If the client supports a
remote HTTP server directly:

```json
{
  "mcpServers": {
    "tarvis": {
      "type": "http",
      "url": "http://soljacast.local/api/agent/v1/mcp",
      "headers": { "Authorization": "Bearer sca_YOUR_TOKEN" }
    }
  }
}
```

If it only supports stdio (Claude Desktop's `claude_desktop_config.json` does),
bridge it with `mcp-remote`:

```json
{
  "mcpServers": {
    "tarvis": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote",
        "http://soljacast.local/api/agent/v1/mcp",
        "--header", "Authorization:${AUTH_HEADER}"
      ],
      "env": { "AUTH_HEADER": "Bearer sca_YOUR_TOKEN" }
    }
  }
}
```

The token goes in `env`, not inline in `args`, so it stays out of process
listings. Restart the client after editing the config.

Get the token the same way as above: open `<device>/admin?mcp_login` in a
browser, approve, and exchange the code. You get the tools but not the skills.

### Codex CLI

Codex reads `~/.codex/config.toml`:

```toml
[mcp_servers.tarvis]
command = "npx"
args = [
  "-y", "mcp-remote",
  "http://soljacast.local/api/agent/v1/mcp",
  "--header", "Authorization: Bearer sca_YOUR_TOKEN",
]
```

### ChatGPT — not supported

Custom MCP connectors live behind **Settings → Apps → Advanced → Developer
mode** (Plus/Pro/Business/Enterprise/Edu, web-first). Two things rule this
device out, and neither is a config problem:

- Auth is **OAuth or none**. A static `Authorization: Bearer` header is not an
  option, and that is how device tokens work.
- The server must be a **public HTTPS endpoint**. OpenAI's servers cannot reach
  a device on your network. Their Secure MCP Tunnel exists for this case.

So a Tarvis device only becomes reachable from ChatGPT if it is published on a
public HTTPS address *and* fronted by something that speaks OAuth.

### Anything else that speaks MCP

The endpoint is plain Streamable HTTP MCP:

```
POST <device>/api/agent/v1/mcp
Authorization: Bearer sca_YOUR_TOKEN
```

`GET <device>/api/agent/discover` needs no token and returns every address the
device answers on, plus `mcp_url`.

### What will not work

**Cloud-hosted clients** — ChatGPT, claude.ai web connectors — connect from the
vendor's servers, not your machine, so they cannot reach a device on your LAN at
all. No configuration changes that. The device must be published on a public
HTTPS address first, which is what its `.solja.one` name is for.

## Finding the right address

You do not need to know an IP. Devices publish themselves over mDNS:

```bash
curl http://soljacast.local/api/agent/discover
```

Several boxes on one network cannot share a name, so each takes the first free
one at boot — `soljacast`, then `soljacast1`, up to `soljacast19`. Probe the
numbered names if the first does not answer. `.local` resolution is built into
macOS, Linux and Windows 10+, so plain HTTP requests work everywhere.

The reply lists every address best-first (LAN https, Tailscale https, mDNS,
raw IP) plus a `preferred` and a ready-made `mcp_url`. Try each in turn and
keep the first that answers: the Tailscale name resolves only on the tailnet,
the LAN name only on the same network. The `find-device` skill does all of
this for you.

Use an https address when one works. Over plain HTTP the browser withholds the
clipboard, so the approval page's **Copy code** button does nothing.

## Portable skills

The tools are just the MCP server — see [Install](#install) for per-client
config. The **skills** are separate, and follow the open
[Agent Skills](https://agentskills.io) format, so they port too; each client
installs them its own way. Copy a `skills/<name>/` directory into your client's
skills location, or package one for upload:

```bash
package_skill.py skills/find-device ./dist    # -> find-device.skill
```

Without the skills you still get every tool; you lose the workflow knowledge
that tells an agent which one to reach for and when to hand back to a human.

## What's in here

| Skill | Covers |
|---|---|
| `cast-to-screen` | Showing web pages, video, decks, images, text and audio on a screen; controlling what's showing |
| `drive-web-page` | Reading a casted page's accessibility tree and clicking, typing and navigating in it |
| `tarvis-vm` | Sandboxed Gondolin VMs and herdr coding-agent sessions (needs VM access on the token) |
| `find-device` | Locating a device on the network over mDNS and picking the right address |

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
