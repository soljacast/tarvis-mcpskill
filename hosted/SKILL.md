---
name: tarvis-setup
description: Connect this computer to a Tarvis (Soljacast) casting device so the agent can cast to its screens, drive the pages it shows, and run sandboxed coding agents on it. Use when the user asks to set up, connect, pair, or install Tarvis. Once connected, use the device's own tools rather than this skill.
---

# Connect to a Tarvis device

Run the setup script. It finds the device, pairs, writes the config for whichever
client you are running in, and verifies the result. Do not hand-roll `curl` calls
for any of this.

## 1. Fetch and run it

```bash
curl -fsSL https://tarvisai.com/install.sh -o /tmp/tarvis-install.sh
bash /tmp/tarvis-install.sh --json
```

`--json` keeps it non-interactive, which is what you want: without it the script
prompts a human for the code on the terminal instead of handing control back.

Every run prints one JSON object with `phase` and `status`. Read it; do not guess
from exit codes.

If the device is not on this network, or discovery fails, pass the address the
user reads off the TV screen: `--device http://<addr>`.

## 2. When status is `approval_pending`

The script has opened the browser and returned an `approve_url` and a
`retry.command`.

Tell the user, in your own words:

- open **`approve_url`** and sign in with the device's admin password
- choose how long access should last
- tick **Allow VMs & coding agents** only if they want the `coding_*` tools
- the page then shows a short code

Ask them for that code. **This browser approval is the only human step and
cannot be automated** — an agent token must never be able to create an admin
session. Do not attempt to work around it.

Then run the returned `retry.command` with `<CODE>` replaced.

## 3. When status is `ok`

`configured` lists the clients that were written, and `tools` is how many tools
the device confirmed. Tell the user to **fully quit and reopen** their client —
a reload does not pick up new MCP servers.

Never print the access token. The script writes it straight into the config;
there is no reason for it to appear in the conversation.

## 4. When status is `error`

The object carries `error` and `hint`. Follow the hint. The common ones:

- **no device found** — they are on a different network, or mDNS is blocked
  (usual on guest and corporate WiFi). Ask for the IP and re-run with `--device`.
- **code rejected** — codes are single use and short lived. Start again from
  step 1 for a fresh request rather than reusing the id.
- **server returned no tools** — the token did not take. Start again from step 1.

Stop and explain if it fails twice. Do not loop.

## What this cannot do

**ChatGPT and claude.ai web connectors cannot reach the device at all.** They
connect from the vendor's servers, not this machine, and the device is on a home
network. Say so plainly rather than attempting a workaround.

**Claude Desktop** has no shell, so it cannot run this itself. Run the script
from a terminal with `--client claude-desktop`, then restart the app.
