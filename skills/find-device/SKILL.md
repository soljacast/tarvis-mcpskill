---
name: find-device
description: Find a Tarvis or Soljacast casting device on the local network and get the address to talk to it, including its https domain. Use when you do not know the device URL, when a saved address stops answering, or before setting up the Tarvis MCP connection. Triggers on "find my device", "what's the device address", "connect to the soljacast box", "the device URL stopped working", "set up tarvis".
allowed-tools: Bash
---

# Find the device

Devices publish themselves over mDNS. You do not need to know an IP.

## 1. Try the well-known name

```bash
curl -s --max-time 3 http://soljacast.local/api/agent/discover
```

A JSON reply means you found it. Skip to step 3.

## 2. Probe the numbered names

Several boxes on one network cannot all be `soljacast.local`. Each takes the
first free name at boot, so the second becomes `soljacast1`, the third
`soljacast2`, and so on up to `soljacast19`.

```bash
for n in "" 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do
  r=$(curl -s --max-time 2 "http://soljacast$n.local/api/agent/discover") || continue
  [ -n "$r" ] && echo "soljacast$n.local: $r"
done
```

Windows PowerShell:

```powershell
foreach ($n in @('') + 1..19) {
  try { $r = Invoke-RestMethod -Uri "http://soljacast$n.local/api/agent/discover" -TimeoutSec 2 }
  catch { continue }
  "soljacast$n.local -> $($r.preferred)"
}
```

Probe names rather than browsing for services. `.local` resolution is built
into macOS, Linux and Windows 10+, so plain HTTP requests work everywhere;
`dns-sd` and `avahi-browse` are not present on every machine.

If more than one answers, there is more than one device — show the user the
hostnames and what each reports in `device.hostname`, and let them pick.

Nothing found means you are on a different network from the device, or mDNS is
blocked (common on guest and corporate WiFi). Ask the user for the device's IP
or https address instead of retrying.

## 3. Use the address it gives you

`/api/agent/discover` needs no token and returns every way to reach the box,
best first:

```json
{
  "device":    { "hostname": "soljacast-<serial>" },
  "addresses": [
    { "url": "https://<name>.example.net",    "kind": "lan",       "tls": true  },
    { "url": "https://<name>.ts.example.net", "kind": "tailscale", "tls": true  },
    { "url": "http://soljacast.local",        "kind": "mdns",      "tls": false },
    { "url": "http://192.0.2.10",             "kind": "direct",    "tls": false }
  ],
  "preferred": "https://<name>.example.net",
  "mcp_url":   "https://<name>.example.net/api/agent/v1/mcp"
}
```

**Try each address in turn and keep the first that answers.** The Tailscale name
resolves only for callers on the tailnet and the LAN name only on the same
network, so which one works depends on where you are. An entry marked
`tls: true` has its certificate on the device, so the handshake will succeed.

Prefer an https address. Browsers expose the clipboard and camera only in a
secure context, so pages the user has to open — the approval page especially —
misbehave over plain http.

The mDNS name keeps working after a device is given an https domain; the two
are independent. Use mDNS to find the box, then its own answer to decide how to
talk to it.
