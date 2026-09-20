#!/bin/sh

echo "=================================================="
echo " Starting Joplin Terminal REST API Gateway"
echo "=================================================="

echo "[init] Clearing residual temporary files..."
rm -rf /tmp/* 2>&1

current=""
if [ -f "/app/joplin/lib/node_modules/joplin/package.json" ]; then
  current=$(jq -r '.version // empty' /app/joplin/lib/node_modules/joplin/package.json 2>/dev/null)
fi

if [ -z "$current" ]; then
  current=$(joplin version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
fi

current=${current:-$JOPLIN_VERSION}

echo "[info] Installed Joplin Terminal App version: v${current:-unknown}"
echo "[info] Checking for latest release from npm registry..."

latest=$(curl -s --max-time 5 https://registry.npmjs.org/joplin/latest | jq -r '.version // empty' 2>/dev/null)

if [ -n "$latest" ] && [ -n "$current" ]; then
  if [ "$current" != "$latest" ]; then
    echo "--------------------------------------------------"
    echo " [NOTICE] A new Joplin version (v$latest) is available!"
    echo " Current running version: v$current"
    echo ""
    echo " To upgrade:"
    echo "   1. Update 'JOPLIN_VERSION=$latest' in your .env file"
    echo "   2. Rebuild the container: docker compose up -d --build"
    echo "--------------------------------------------------"
  else
    echo "[info] Joplin Terminal App is currently up to date (v$current)."
  fi
fi

SETTINGS_FILE="/root/.config/joplin/settings.json"
mkdir -p /root/.config/joplin

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "{}" > "$SETTINGS_FILE"
fi

echo "[config] Applying environment variables to settings.json..."

ENV_JSON="{}"
for var in $(env | grep '^JOPLIN_' | grep -v '^JOPLIN_VERSION='); do
  env_name="${var%%=*}"
  val="${var#*=}"

  key=$(echo "$env_name" | sed 's/^JOPLIN_//' | tr '_' '.')

  if [ -n "$val" ]; then
    ENV_JSON=$(echo "$ENV_JSON" | jq --arg k "$key" --arg v "$val" \
      '. + {($k): (if ($v == "true") then true elif ($v == "false") then false elif ($v | test("^[0-9]+$")) then ($v | tonumber) else $v end)}')
  fi
done

UPDATED_SETTINGS=$(jq --argjson env "$ENV_JSON" '. * $env' "$SETTINGS_FILE")
echo "$UPDATED_SETTINGS" > "$SETTINGS_FILE"
echo "[config] Settings updated successfully."

echo "[service] Launching Joplin Web Clipper server..."
joplin server start &

sleep 5

echo "[network] Starting socat port proxy (0.0.0.0:41185 -> 127.0.0.1:41184)..."
socat TCP-LISTEN:41185,fork,reuseaddr TCP:127.0.0.1:41184 &

while true; do
  total_items=$(joplin status 2>/dev/null \
    | grep -E ':[[:space:]]*[0-9]+/[0-9]+' \
    | tail -n 1 \
    | sed -E 's/.*:[[:space:]]*[0-9]+\/([0-9]+).*/\1/')

  if [ -z "$total_items" ] || [ "$total_items" -eq 0 ] 2>/dev/null; then
    echo "[sync] Local database is empty. Synchronization paused until initialized."
  else
    echo "[sync] Starting remote synchronization (Item count: $total_items)..."
    joplin sync
  fi

  sync_interval=600

  if [ -f "/root/.config/joplin/settings.json" ]; then
    extracted_interval=$(jq -r '."sync.interval" // empty' /root/.config/joplin/settings.json 2>/dev/null)
    [ -n "$extracted_interval" ] && sync_interval=$extracted_interval
  fi

  if [ "$sync_interval" -lt 300 ] 2>/dev/null; then
    sync_interval=300
  fi

  sleep $sync_interval
done

wait
