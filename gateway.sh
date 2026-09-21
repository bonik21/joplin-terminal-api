#!/bin/sh

LOCK_FILE="/tmp/joplin-sync.lock"
SETTINGS_FILE="/root/.config/joplin/settings.json"

run_sync() {
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    return 2
  fi

  if command -v joplin >/dev/null 2>&1; then
    if joplin sync; then
      return 0
    else
      return 1
    fi
  else
    return 0
  fi
}

# Allow entrypoint.sh to invoke sync directly via CLI
if [ "$1" = "--sync" ]; then
  run_sync
  exit $?
fi

# Read HTTP Request Line
read -r request_line || exit 0
request_line=$(echo "$request_line" | tr -d '\r')
[ -z "$request_line" ] && exit 0

method=$(echo "$request_line" | cut -d' ' -f1)
uri=$(echo "$request_line" | cut -d' ' -f2)

auth_token=""
content_length=0
content_type=""
headers_file=$(mktemp)

while IFS= read -r header_line; do
  header_line=$(echo "$header_line" | tr -d '\r')
  [ -z "$header_line" ] && break

  header_name=$(echo "$header_line" | cut -d: -f1)
  header_val=$(echo "$header_line" | cut -d: -f2- | sed -e 's/^[[:space:]]*//')
  lower_name=$(echo "$header_name" | tr '[:upper:]' '[:lower:]')

  case "$lower_name" in
    authorization)
      case "$header_val" in
        Bearer\ *|bearer\ *)
          auth_token="${header_val#* }"
          ;;
      esac
      ;;
    content-length)
      content_length="$header_val"
      ;;
    content-type)
      content_type="$header_val"
      ;;
    host|connection)
      # Skip headers managed by gateway / curl
      ;;
    *)
      # Preserve other headers
      echo "-H \"$header_name: $header_val\"" >> "$headers_file"
      ;;
  esac
done

# Consume body if present
body_file=""
if [ -n "$content_length" ] && [ "$content_length" -gt 0 ] 2>/dev/null; then
  body_file=$(mktemp)
  head -c "$content_length" > "$body_file"
fi

cleanup() {
  rm -f "$headers_file"
  if [ -n "$body_file" ]; then
    rm -f "$body_file"
  fi
}
trap cleanup EXIT INT TERM

path="${uri%%\?*}"

# Read expected Joplin API token from settings
expected_token=""
if [ -f "$SETTINGS_FILE" ]; then
  expected_token=$(jq -r '."api.token" // empty' "$SETTINGS_FILE" 2>/dev/null || true)
fi

# Route 1: /sync
if [ "$path" = "/sync" ]; then
  if [ "$method" != "POST" ]; then
    printf "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nMethod Not Allowed\r\n"
    exit 0
  fi

  if [ -z "$auth_token" ] || { [ -n "$expected_token" ] && [ "$auth_token" != "$expected_token" ]; }; then
    printf "HTTP/1.1 401 Unauthorized\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nUnauthorized\r\n"
    exit 0
  fi

  sync_res=0
  run_sync || sync_res=$?

  if [ $sync_res -eq 0 ]; then
    printf "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nSync completed\r\n"
  elif [ $sync_res -eq 2 ]; then
    printf "HTTP/1.1 409 Conflict\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nSync already running\r\n"
  else
    printf "HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nSync failed\r\n"
  fi
  exit 0
fi

# Route 2: /ping (Health check: public endpoint, no token required)
if [ "$path" = "/ping" ]; then
  forward_uri="$uri"
  if [ -n "$auth_token" ]; then
    case "$uri" in
      *\?*) forward_uri="${uri}&token=${auth_token}" ;;
      *) forward_uri="${uri}?token=${auth_token}" ;;
    esac
  fi

  if ! curl -s -i --http1.0 "http://127.0.0.1:41184${forward_uri}"; then
    printf "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nBad Gateway\r\n"
  fi
  exit 0
fi

# Route 3: Other Joplin Data API endpoints
if [ -z "$auth_token" ]; then
  printf "HTTP/1.1 401 Unauthorized\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nUnauthorized\r\n"
  exit 0
fi

# Convert Bearer token to ?token= query param
case "$uri" in
  *\?*) forward_uri="${uri}&token=${auth_token}" ;;
  *) forward_uri="${uri}?token=${auth_token}" ;;
esac

curl_cmd="curl -s -i --http1.0 -X \"$method\""

if [ -n "$body_file" ] && [ -s "$body_file" ]; then
  curl_cmd="$curl_cmd --data-binary @\"$body_file\""
fi

if [ -n "$content_type" ]; then
  curl_cmd="$curl_cmd -H \"Content-Type: $content_type\""
fi

while IFS= read -r h; do
  [ -n "$h" ] && curl_cmd="$curl_cmd $h"
done < "$headers_file"

curl_cmd="$curl_cmd \"http://127.0.0.1:41184${forward_uri}\""

if ! eval "$curl_cmd"; then
  printf "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nBad Gateway\r\n"
fi
exit 0
