---
name: find-device
description: Find a Tarvis or Soljacast casting device on the local network and get the address to talk to it, including its https domain. Use when you do not know the device URL, when a saved address stops answering, or before setting up the Tarvis MCP connection. Triggers on "find my device", "what's the device address", "connect to the soljacast box", "the device URL stopped working", "set up tarvis".
allowed-tools: Bash
---

# Find the device

Devices publish themselves over mDNS. You do not need to know an IP.

## 1. Try the well-known names

```bash
curl -s --max-time 3 http://tarvis.local/api/agent/discover
curl -s --max-time 3 http://soljacast.local/api/agent/discover
```

A JSON reply means you found it. Skip to step 3.

Boxes on the Personal plan answer to **both** names; older and Lite boxes answer
only to `soljacast.local`. Try `tarvis.local` first — it is the name on the
device — but never conclude there is no device until both have been tried.

## 2. Probe the numbered names

Several boxes on one network cannot share a name. Each takes the first free one
at boot, so the second becomes `tarvis1`, the third `tarvis2`, up to 19, and the
same for `soljacast`.

```bash
for n in "" 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do
  for base in tarvis soljacast; do
    r=$(curl -s --max-time 2 "http://$base$n.local/api/agent/discover") || continue
    [ -n "$r" ] && echo "$base$n.local: $r"
  done
done
```

Windows PowerShell:

```powershell
foreach ($n in @('') + 1..19) {
  foreach ($base in 'tarvis', 'soljacast') {
    try { $r = Invoke-RestMethod -Uri "http://$base$n.local/api/agent/discover" -TimeoutSec 2 }
    catch { continue }
    "$base$n.local -> $($r.preferred)"
  }
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

Everything the box hosts follows the same pair: apps and coding sessions
report `url` (`https://<app>.<name>.example.net`, LAN) and `tailscale_url`
(`https://<app>.<name>.ts.example.net`) — same rule as the device addresses
above, so pick by where the caller is.
