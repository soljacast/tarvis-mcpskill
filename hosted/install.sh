#!/usr/bin/env bash
# Tarvis cloud workspace setup. Two phases so an agent can drive it without a TTY.
#
#   install.sh --workspace <url>                         -> request pairing
#   install.sh --workspace <url> --id <id> --code <code> -> configure and verify
#
# Every run prints one JSON object: {phase, status, ...}. status is one of
# ok | approval_pending | error.
set -uo pipefail

WORKSPACE=""; REQ_ID=""; CODE=""; CLIENT=""; JSON_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="${2%/}"; shift 2 ;;
    --id)     REQ_ID="$2"; shift 2 ;;
    --code)   CODE="$2"; shift 2 ;;
    --client) CLIENT="$2"; shift 2 ;;
    --json)   JSON_ONLY=1; shift ;;
    *) shift ;;
  esac
done

PY=$(command -v python3 || command -v python || true)
emit() { # emit <json-body>
  printf '%s\n' "$1"
  [ "${2:-0}" = "1" ] && exit 1
  exit 0
}
fail() { emit "{\"phase\":\"$1\",\"status\":\"error\",\"error\":\"$2\",\"hint\":\"$3\"}" 1; }

[ -z "$PY" ] && fail "preflight" "python3 not found" "Install python3, then re-run."
command -v curl >/dev/null || fail "preflight" "curl not found" "Install curl, then re-run."

jget() { "$PY" -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1],""))' "$1" 2>/dev/null; }
jstr() { "$PY" -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

# ---------------------------------------------------------- private workspace
normalize_workspace() {
  "$PY" -c 'import sys
from urllib.parse import urlsplit
raw=sys.argv[1].strip()
if "://" not in raw:
    raw="https://"+raw
u=urlsplit(raw)
host=(u.hostname or "").lower()
if host.endswith(".ts.tarvis.site"):
    private=host
elif host.endswith(".tarvis.site"):
    label=host[:-len(".tarvis.site")]
    if not label or "." in label:
        raise SystemExit(2)
    private=label+".ts.tarvis.site"
else:
    raise SystemExit(2)
print("https://"+private)' "$1"
}

reorigin() {
  "$PY" -c 'import sys
from urllib.parse import urlsplit,urlunsplit
raw,base=sys.argv[1],urlsplit(sys.argv[2])
if not raw:
    print("")
else:
    u=urlsplit(raw)
    print(urlunsplit((base.scheme,base.netloc,u.path,u.query,u.fragment)))' "$1" "$2"
}

[ -z "$WORKSPACE" ] && fail "preflight" "workspace URL required" \
  "Enable VPN in Tarvis workspace settings, accept the Tailscale invitation, connect Tailscale, then re-run with --workspace https://name.tarvis.site"
WORKSPACE=$(normalize_workspace "$WORKSPACE") || fail "preflight" "invalid workspace URL" \
  "Pass the base URL, for example https://name.tarvis.site"
curl -fsS --max-time 10 "$WORKSPACE/health" >/dev/null 2>&1 ||
  fail "health" "private workspace is not reachable" \
    "Confirm VPN is enabled, the Tailscale invitation is accepted, and Tailscale is connected on this computer."
INFO=$(curl -fsS --max-time 10 "$WORKSPACE/api/agent/discover" 2>/dev/null) ||
  fail "discover" "workspace discovery failed" "Check Tailscale and the private workspace health endpoint."
MCP_RAW=$(printf '%s' "$INFO" | jget mcp_url)
[ -n "$MCP_RAW" ] || MCP_RAW="$WORKSPACE/api/agent/v1/mcp"
MCP_URL=$(reorigin "$MCP_RAW" "$WORKSPACE")

# ---------------------------------------------------------------- phase 1
if [ -z "$CODE" ]; then
  REQ=$(curl -fsS --max-time 10 -X POST "$WORKSPACE/api/agent/auth/request" \
        -H "Content-Type: application/json" \
        -d "{\"client_name\":$(jstr "$(hostname -s 2>/dev/null || echo agent)")}" 2>/dev/null) \
    || fail "request" "pairing request failed" "Check the workspace is reachable at $WORKSPACE"
  RID=$(printf '%s' "$REQ" | jget request_id)
  URL=$(reorigin "$(printf '%s' "$REQ" | jget approve_url)" "$WORKSPACE")
  [ -z "$RID" ] && fail "request" "workspace returned no request id" "Update the Tarvis workspace."
  [ -z "$URL" ] && fail "request" "workspace returned no approval URL" "Update the Tarvis workspace."
  (command -v open >/dev/null && open "$URL" >/dev/null 2>&1) ||
    (command -v xdg-open >/dev/null && xdg-open "$URL" >/dev/null 2>&1) || true
  # A person at a terminal gets a prompt; an agent gets JSON and calls back.
  if [ -z "$JSON_ONLY" ] && [ -r /dev/tty ]; then
    printf '\n  Open this and approve, completing authorization in the browser:\n\n    %s\n\n' "$URL" > /dev/tty
    printf '  The authorization page shows a short code. Type it here.\n  Code: ' > /dev/tty
    read -r CODE < /dev/tty
    if [ -n "$CODE" ]; then REQ_ID="$RID"; else
      emit "{\"phase\":\"approval\",\"status\":\"error\",\"error\":\"no code entered\",\"hint\":\"Re-run to try again.\"}" 1
    fi
  else
  emit "{\"phase\":\"approval\",\"status\":\"approval_pending\",\"workspace\":$(jstr "$WORKSPACE"),\"request_id\":$(jstr "$RID"),\"approve_url\":$(jstr "$URL"),\"instructions\":\"Open approve_url in a browser, authorize access, then re-run with the code shown.\",\"retry\":{\"command\":$(jstr "$0 --workspace $WORKSPACE --id $RID --code <CODE>")}}"
  fi
fi

# ---------------------------------------------------------------- phase 2
[ -z "$REQ_ID" ] && fail "exchange" "--code given without --id" "Re-run phase 1 to get a request id."
TOKEN=$(curl -fsS --max-time 10 -X POST "$WORKSPACE/api/agent/auth/exchange" \
        -H "Content-Type: application/json" \
        -d "{\"request_id\":$(jstr "$REQ_ID"),\"code\":$(jstr "$CODE")}" 2>/dev/null |
        "$PY" -c 'import json,sys;d=json.load(sys.stdin);print(d.get("token") or d.get("access_token") or "")' 2>/dev/null)
[ -z "$TOKEN" ] && fail "exchange" "code rejected" \
  "Codes are single use and expire. Re-run phase 1 for a fresh request."

CONFIGURED=""; SKIPPED=""
note() { CONFIGURED="$CONFIGURED${CONFIGURED:+,}$(jstr "$1")"; }
skip() { SKIPPED="$SKIPPED${SKIPPED:+,}$(jstr "$1")"; }

write_json_cfg() { # <label> <path>
  local dir; dir=$(dirname "$2")
  [ -d "$dir" ] || return 1
  [ -f "$2" ] && cp "$2" "$2.bak-tarvis-$(date +%s)" 2>/dev/null
  MCP_URL="$MCP_URL" TOKEN="$TOKEN" "$PY" - "$2" <<'PY' || return 1
import json,os,sys
p=sys.argv[1]
try: cfg=json.load(open(p))
except Exception: cfg={}
cfg.setdefault("mcpServers",{})["tarvis"]={
 "command":"npx",
 "args":["-y","mcp-remote",os.environ["MCP_URL"],"--header","Authorization:${AUTH_HEADER}"],
 "env":{"AUTH_HEADER":"Bearer "+os.environ["TOKEN"]}}
os.makedirs(os.path.dirname(p),exist_ok=True)
json.dump(cfg,open(p,"w"),indent=2)
PY
  chmod 600 "$2" 2>/dev/null
  note "$1"
}

case "$(uname -s)" in
  Darwin) CD_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  *)      CD_CFG="$HOME/.config/Claude/claude_desktop_config.json" ;;
esac

if [ -z "$CLIENT" ] || [ "$CLIENT" = "claude-code" ]; then
  if command -v claude >/dev/null 2>&1; then
    claude mcp remove -s user tarvis >/dev/null 2>&1 || true
    if claude mcp add -s user --transport http tarvis "$MCP_URL" \
         --header "Authorization: Bearer $TOKEN" >/dev/null 2>&1; then
      note "claude-code"
    else
      claude mcp list 2>/dev/null | grep -q tarvis && skip "claude-code"
    fi
  fi
fi
[ -z "$CLIENT" ] || [ "$CLIENT" = "claude-desktop" ] && write_json_cfg "claude-desktop" "$CD_CFG"
[ -z "$CLIENT" ] || [ "$CLIENT" = "cursor" ] && write_json_cfg "cursor" "$HOME/.cursor/mcp.json"

CODEX="$HOME/.codex/config.toml"
if { [ -z "$CLIENT" ] || [ "$CLIENT" = "codex" ]; } && [ -d "$(dirname "$CODEX")" ] &&
   ! grep -q '^\[mcp_servers.tarvis\]' "$CODEX" 2>/dev/null; then
  [ -f "$CODEX" ] && cp "$CODEX" "$CODEX.bak-tarvis-$(date +%s)"
  printf '\n[mcp_servers.tarvis]\ncommand = "npx"\nargs = ["-y", "mcp-remote", "%s", "--header", "Authorization: Bearer %s"]\n' \
    "$MCP_URL" "$TOKEN" >> "$CODEX"
  chmod 600 "$CODEX" 2>/dev/null; note "codex"
elif grep -q '^\[mcp_servers.tarvis\]' "$CODEX" 2>/dev/null; then
  skip "codex"
fi

VERIFY=$(curl -fsS --max-time 10 -X POST "$MCP_URL" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' 2>/dev/null)
TOOLS=$(printf '%s' "$VERIFY" | "$PY" -c 'import json,sys
try: print(len(json.load(sys.stdin).get("result",{}).get("tools",[])))
except Exception: print(0)' 2>/dev/null)
[ "${TOOLS:-0}" -eq 0 ] && fail "verify" "server returned no tools" \
  "Token may be wrong. Re-run phase 1 for a fresh request."

if [ -z "$JSON_ONLY" ] && [ -w /dev/tty ]; then
  printf '\n  Connected to %s\n  %s tools available, configured: %s\n  Fully quit and reopen your client (a reload is not enough).\n\n' \
    "$WORKSPACE" "$TOOLS" "$(printf '%s' "$CONFIGURED" | tr -d '\"')" > /dev/tty 2>/dev/null || true
fi
if [ -z "$CONFIGURED" ] && [ -z "$SKIPPED" ]; then
  emit "{\"phase\":\"configure\",\"status\":\"error\",\"error\":\"no supported client found\",\"hint\":\"Add it by hand: url $MCP_URL with header 'Authorization: Bearer <token>'. The token was not printed; re-run to mint a new one.\",\"mcp_url\":$(jstr "$MCP_URL")}" 1
fi
emit "{\"phase\":\"done\",\"status\":\"ok\",\"workspace\":$(jstr "$WORKSPACE"),\"mcp_url\":$(jstr "$MCP_URL"),\"tools\":$TOOLS,\"configured\":[$CONFIGURED],\"already_configured\":[$SKIPPED],\"next\":\"Fully quit and reopen the client; a reload does not pick up new MCP servers.\"}"
