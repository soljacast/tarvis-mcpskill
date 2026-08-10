#!/usr/bin/env bash
# Tarvis setup. Two phases so an agent can drive it without a TTY.
#
#   install.sh                          -> phase 1: find device, request pairing
#   install.sh --id <id> --code <code>  -> phase 2: exchange, configure, verify
#
# Every run prints one JSON object: {phase, status, ...}. status is one of
# ok | approval_pending | error.
set -uo pipefail

DEVICE=""; REQ_ID=""; CODE=""; CLIENT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="${2%/}"; shift 2 ;;
    --id)     REQ_ID="$2"; shift 2 ;;
    --code)   CODE="$2"; shift 2 ;;
    --client) CLIENT="$2"; shift 2 ;;
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

# ---------------------------------------------------------------- discovery
discover() {
  if [ -n "$DEVICE" ]; then
    curl -fsS --max-time 4 "$DEVICE/api/agent/discover" 2>/dev/null && return 0
    return 1
  fi
  local n out
  for n in "" 1 2 3 4 5; do
    out=$(curl -fsS --max-time 3 "http://soljacast$n.local/api/agent/discover" 2>/dev/null) || continue
    printf '%s' "$out"; return 0
  done
  return 1
}

INFO=$(discover) || fail "discover" "no device found" \
  "Ask the user for the address on the TV screen, then re-run with --device http://<addr>"
PREFERRED=$(printf '%s' "$INFO" | jget preferred)
[ -n "$PREFERRED" ] && DEVICE="${PREFERRED%/}"
MCP_URL="$DEVICE/api/agent/v1/mcp"

# ---------------------------------------------------------------- phase 1
if [ -z "$CODE" ]; then
  REQ=$(curl -fsS --max-time 10 -X POST "$DEVICE/api/agent/auth/request" \
        -H "Content-Type: application/json" \
        -d "{\"name\":$(jstr "$(hostname -s 2>/dev/null || echo agent)")}" 2>/dev/null) \
    || fail "request" "pairing request failed" "Check the device is reachable at $DEVICE"
  RID=$(printf '%s' "$REQ" | jget request_id)
  URL=$(printf '%s' "$REQ" | jget approve_url)
  [ -z "$RID" ] && fail "request" "device returned no request id" "Update the device firmware."
  (command -v open >/dev/null && open "$URL" >/dev/null 2>&1) ||
    (command -v xdg-open >/dev/null && xdg-open "$URL" >/dev/null 2>&1) || true
  emit "{\"phase\":\"approval\",\"status\":\"approval_pending\",\"device\":$(jstr "$DEVICE"),\"request_id\":$(jstr "$RID"),\"approve_url\":$(jstr "$URL"),\"instructions\":\"Open approve_url, sign in as admin, approve, then re-run with --id and the code shown.\",\"retry\":{\"command\":$(jstr "$0 --device $DEVICE --id $RID --code <CODE>")}}"
fi

# ---------------------------------------------------------------- phase 2
[ -z "$REQ_ID" ] && fail "exchange" "--code given without --id" "Re-run phase 1 to get a request id."
TOKEN=$(curl -fsS --max-time 10 -X POST "$DEVICE/api/agent/auth/exchange" \
        -H "Content-Type: application/json" \
        -d "{\"id\":$(jstr "$REQ_ID"),\"code\":$(jstr "$CODE")}" 2>/dev/null |
        "$PY" -c 'import json,sys;d=json.load(sys.stdin);print(d.get("token") or d.get("access_token") or "")' 2>/dev/null)
[ -z "$TOKEN" ] && fail "exchange" "code rejected" \
  "Codes are single use and expire. Re-run phase 1 for a fresh request."

CONFIGURED=""
note() { CONFIGURED="$CONFIGURED${CONFIGURED:+,}$(jstr "$1")"; }

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
  command -v claude >/dev/null 2>&1 &&
    claude mcp add --transport http tarvis "$MCP_URL" \
      --header "Authorization: Bearer $TOKEN" >/dev/null 2>&1 && note "claude-code"
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
fi

VERIFY=$(curl -fsS --max-time 10 -X POST "$MCP_URL" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' 2>/dev/null)
TOOLS=$(printf '%s' "$VERIFY" | "$PY" -c 'import json,sys
try: print(len(json.load(sys.stdin).get("result",{}).get("tools",[])))
except Exception: print(0)' 2>/dev/null)
[ "${TOOLS:-0}" -eq 0 ] && fail "verify" "server returned no tools" \
  "Token may be wrong. Re-run phase 1 for a fresh request."

emit "{\"phase\":\"done\",\"status\":\"ok\",\"device\":$(jstr "$DEVICE"),\"mcp_url\":$(jstr "$MCP_URL"),\"tools\":$TOOLS,\"configured\":[$CONFIGURED],\"next\":\"Fully quit and reopen the client; a reload does not pick up new MCP servers.\"}"
