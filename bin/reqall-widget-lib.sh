# Shared by the reqall-widget-* scripts: credential lookup and one MCP tool
# call. Sourced, never run on its own.
#
# Credentials, in order of precedence:
#   REQALL_WIDGET_API_KEY   the widget's own apiKey setting
#   REQALL_API_KEY          the environment of omarchy-shell
#   ~/.config/reqall/env    the file the Reqall Claude plugin sources
#   ~/.config/reqall/config.json   api_key or access_token stored by `reqall login`
#
# After sourcing: $key (may be empty), $url, $source_name, $has_cli, and the
# functions mcp, mcp_error, and require_tools.

CONFIG_DIR="${REQALL_CONFIG_DIR:-$HOME/.config/reqall}"
DEFAULT_URL="https://www.reqall.net"

url="${REQALL_WIDGET_URL:-}"
key="${REQALL_WIDGET_API_KEY:-}"
source_name=""

unquote() {
  local v="$1"
  v="${v#\"}"; v="${v%\"}"
  v="${v#\'}"; v="${v%\'}"
  printf '%s' "$v"
}

# The env file is a list of `export NAME=value` lines. Parse it rather than
# sourcing it: the shell process should never execute text from a config file.
file_key=""
file_url=""
if [[ -r "$CONFIG_DIR/env" ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line#export }"
    case $line in
      REQALL_API_KEY=*) file_key=$(unquote "${line#REQALL_API_KEY=}") ;;
      REQALL_API_URL=*) file_url=$(unquote "${line#REQALL_API_URL=}") ;;
      REQALL_URL=*) file_url=$(unquote "${line#REQALL_URL=}") ;;
    esac
  done < "$CONFIG_DIR/env"
fi

if [[ -n $key ]]; then
  source_name="setting"
elif [[ -n ${REQALL_API_KEY:-} ]]; then
  key="$REQALL_API_KEY"; source_name="environment"
elif [[ -n $file_key ]]; then
  key="$file_key"; source_name="env-file"
elif [[ -r "$CONFIG_DIR/config.json" ]] && command -v jq >/dev/null; then
  key=$(jq -r '.api_key // .access_token // empty' "$CONFIG_DIR/config.json" 2>/dev/null)
  [[ -n $key ]] && source_name="cli-login"
fi

[[ -n $url ]] || url="${REQALL_API_URL:-${REQALL_URL:-$file_url}}"
[[ -n $url ]] || url="$DEFAULT_URL"
url="${url%/}"

has_cli=false
command -v reqall >/dev/null 2>&1 && has_cli=true

# require_tools: prints the first missing tool and returns 1.
require_tools() {
  local tool
  for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || { printf '%s' "$tool"; return 1; }
  done
}

# mcp <tool> <arguments-json>  -> prints structuredContent JSON, or returns:
#   2 on transport/server failure, 3 on 401, 4 on 403.
# mcp runs inside command substitutions, so the failure message travels through
# a temp file rather than a variable; read it back with mcp_error.
err_file=$(mktemp)
trap 'rm -f "$err_file"' EXIT
set_error() { printf '%s' "$1" > "$err_file"; }
mcp_error() { cat "$err_file"; }
mcp() {
  local body out code payload
  body=$(jq -nc --arg n "$1" --argjson a "$2" \
    '{jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: $n, arguments: $a}}')
  out=$(curl -sS --max-time 15 -w $'\n%{http_code}' -X POST "$url/mcp" \
    -H "Authorization: Bearer $key" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d "$body" 2>/dev/null) || { set_error "Could not reach $url"; return 2; }
  code="${out##*$'\n'}"
  payload="${out%$'\n'*}"
  case $code in
    200) ;;
    401) set_error "$(jq -r '.message // "Unauthorized"' <<<"$payload" 2>/dev/null)"; return 3 ;;
    403) set_error "$(jq -r '.message // "Forbidden"' <<<"$payload" 2>/dev/null)"; return 4 ;;
    *) set_error "Server returned HTTP $code"; return 2 ;;
  esac
  # The endpoint answers as a server-sent event stream or as plain JSON.
  if [[ $payload == event:* || $payload == data:* ]]; then
    payload=$(sed -n 's/^data: //p' <<<"$payload" | head -n 1)
  fi
  local sc
  sc=$(jq -c '.result.structuredContent // empty' <<<"$payload" 2>/dev/null)
  if [[ -z $sc ]]; then
    set_error "$(jq -r '.error.message // .result.content[0].text // "Unexpected response"' <<<"$payload" 2>/dev/null)"
    return 2
  fi
  printf '%s' "$sc"
}

# auth_for_status <mcp-return-code>  -> the widget's auth word for a failure.
auth_for_status() {
  case $1 in
    3) printf 'invalid' ;;
    4) printf 'paused' ;;
    *) printf 'error' ;;
  esac
}

# The projects remembered into from the panel, most recent first, one per line.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/reqall-widget"
USED_FILE="$STATE_DIR/used-projects"
