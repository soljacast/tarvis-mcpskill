# Tarvis MCP

Connect an MCP-speaking agent to a private Tarvis cloud workspace. The MCP
server runs in the workspace; the client reaches it through Tailscale and uses
a browser-approved bearer token.

## Recommended setup for any agent

Give the agent this instruction:

```text
Set up Tarvis from https://tarvis.io/SKILL.md
```

The standalone skill is the source of truth for pairing and does not require a
plugin or a preinstalled Tarvis tool. It guides the user through the complete
flow:

1. Ask for the base workspace URL, such as `https://war.tarvis.site`.
2. Derive `https://war.ts.tarvis.site`.
3. Enable VPN in workspace settings, accept the Tailscale invitation, and
   connect Tailscale on the MCP client computer.
4. Require the private `/health` endpoint to answer.
5. Request pairing through the `.ts` origin.
6. Open or display the generated private approval URL.
7. Exchange the browser code, write the MCP configuration, and verify
   `tools/list`.

Use the ordinary `*.tarvis.site` URL only to derive the private address. Health,
discovery, browser login and approval, and MCP requests all use the private
`*.ts.tarvis.site` origin.

## Terminal installer

After VPN and Tailscale are ready:

```bash
curl -fsSL https://tarvis.io/install.sh -o /tmp/tarvis-install.sh
bash /tmp/tarvis-install.sh --workspace https://war.tarvis.site
```

The installer derives the `.ts` origin, checks health, opens the approval page,
asks for the displayed code, and configures supported clients. For an
agent-driven two-phase run, add `--json`, then use the returned retry command
with `--id` and `--code`.

Target one client with `--client claude-code`, `--client claude-desktop`,
`--client cursor`, or `--client codex`.

## Claude Code plugin

```text
/plugin marketplace add tarvis-io/tarvis-mcpskill
/plugin install tarvis@tarvis-mcpskill
```

Then ask Claude Code to connect to the Tarvis workspace. Installing the plugin
adds guidance; it does not create the MCP connection by itself.

## Manual MCP configuration

Discovery returns the exact `mcp_url`. It normally has this form:

```text
https://war.ts.tarvis.site/api/agent/v1/mcp
```

Use the token returned by the code exchange as:

```text
Authorization: Bearer <token>
```

For a client with native remote HTTP MCP support:

```json
{
  "mcpServers": {
    "tarvis": {
      "type": "http",
      "url": "https://war.ts.tarvis.site/api/agent/v1/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

For stdio-only clients, bridge with `mcp-remote`:

```json
{
  "mcpServers": {
    "tarvis": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "https://war.ts.tarvis.site/api/agent/v1/mcp",
        "--header",
        "Authorization:${AUTH_HEADER}"
      ],
      "env": { "AUTH_HEADER": "Bearer <token>" }
    }
  }
}
```

Restart the client completely after changing its MCP configuration.

## Skills and further guidance

Skills are guidance, not a runtime dependency. A paired client can use every
tool advertised by `tools/list` even when it cannot install this plugin.

| Skill | Purpose |
|---|---|
| `connect-device` | Tailscale-backed workspace pairing and MCP configuration |
| `find-device` | Derive and diagnose the private workspace origin |
| `personal-cloud` | Apps, scheduled tasks, secrets, notifications, and chats |
| `tarvis-vm` | Workspace VMs and coding sessions |
| `cast-to-screen` | Casting when the connected Tarvis workspace advertises display tools |
| `drive-web-page` | Driving a page when the workspace advertises page-control tools |

Agents without plugin support can fetch a relevant skill directly from:

```text
https://raw.githubusercontent.com/tarvis-io/tarvis-mcpskill/master/skills/<skill-name>/SKILL.md
```

The complete collection is at
`https://github.com/tarvis-io/tarvis-mcpskill/tree/master/skills`.

## Hosted web connectors

Hosted web connectors cannot reach the Tarvis workspace tailnet. The `.ts`
endpoint is for a local MCP client whose computer joined the Tarvis workspace
VPN.

## Development

Each skill carries evaluation fixtures under its `evals/` directory. Validate
changed skills before release and keep `hosted/SKILL.md` synchronized with the
copy published at `https://tarvis.io/SKILL.md`.

## Safety

Pairing is approved in the user's browser. Login credentials stay in the
browser. Never request them in chat, never print the bearer token, and do not
claim setup succeeded until `tools/list` returns tools.
