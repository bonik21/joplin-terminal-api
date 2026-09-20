#!/bin/sh

echo "---------------------------"
echo "Cleaning aborted temp lock files..."
rm -rf /tmp/* 2>&1

echo "Running Joplin version: $JOPLIN_VERSION"

if [ "$JOPLIN_VERSION" = "dynamic" ]; then
  echo "Checking for Joplin updates..."

  current=$(NPM_CONFIG_PREFIX=/app/joplin npm list -g joplin --depth=0 2>/dev/null \
    | grep -E 'joplin@[0-9.]*\s*$' \
    | tail -n 1 \
    | sed 's/^.*joplin@\([0-9.]*\).*$/\1/')

  latest=$(npm show joplin@latest version 2>/dev/null)

  echo "Current Joplin version: $current"
  echo "Latest Joplin version: $latest"

  if [ "$current" != "$latest" ]; then
    echo "Installing joplin@$latest..."
    NPM_CONFIG_PREFIX=/app/joplin npm install --omit=dev -g joplin@$latest
  else
    echo "Joplin is already up to date."
  fi

  ln -sf /app/joplin/bin/joplin /usr/bin/joplin
fi

SETTINGS_FILE="/root/.config/joplin/settings.json"
mkdir -p /root/.config/joplin

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "{}" > "$SETTINGS_FILE"
fi

echo "Updating Joplin settings from environment variables (Fast jq Batch Update)..."

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
echo "Joplin settings updated successfully."
echo "Starting Joplin server..."
joplin server start &

sleep 5

echo "Starting socat port forwarding (0.0.0.0:41185 -> 127.0.0.1:41184)..."
socat TCP-LISTEN:41185,fork,reuseaddr TCP:127.0.0.1:41184 &

while true; do
  total_items=$(joplin status 2>/dev/null \
    | grep -E ':[[:space:]]*[0-9]+/[0-9]+' \
    | tail -n 1 \
    | sed -E 's/.*:[[:space:]]*[0-9]+\/([0-9]+).*/\1/')

  if [ -z "$total_items" ] || [ "$total_items" -eq 0 ] 2>/dev/null; then
    echo "Joplin is in a blank state, synchronization is paused"
  else
    echo "Starting Joplin sync (Total items: $total_items)..."
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
