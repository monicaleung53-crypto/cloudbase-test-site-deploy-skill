#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-}"
ENV_ID="${ENV_ID:-}"
FUNCTION_NAME="${FUNCTION_NAME:-app}"
SERVICE_PATH="${SERVICE_PATH:-/app}"
SERVICE_URL="${SERVICE_URL:-}"
RUNTIME="${RUNTIME:-Nodejs18.15}"
NODE_CHECK_BIN="${NODE_CHECK_BIN:-/Applications/Codex.app/Contents/Resources/node}"
TOOLS_DIR="${TOOLS_DIR:-/tmp/cloudbase-test-site-tools}"
NODE_VERSION="${NODE_VERSION:-20.11.1}"

if [ -z "$PROJECT_DIR" ] || [ -z "$ENV_ID" ]; then
  echo "Required: PROJECT_DIR and ENV_ID"
  echo "Example:"
  echo "PROJECT_DIR=/path/to/project ENV_ID=env-id FUNCTION_NAME=app SERVICE_PATH=/app SERVICE_URL=https://example.app.tcloudbase.com/app $0"
  exit 2
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) NODE_PLATFORM="darwin-arm64" ;;
  x86_64) NODE_PLATFORM="darwin-x64" ;;
  *) echo "Unsupported macOS arch: $ARCH"; exit 2 ;;
esac

NODE_DIR="$TOOLS_DIR/node-v$NODE_VERSION-$NODE_PLATFORM"
TCB="$TOOLS_DIR/node_modules/.bin/tcb"

mkdir -p "$TOOLS_DIR"

if [ ! -x "$NODE_DIR/bin/npm" ]; then
  echo "Installing temporary Node.js toolchain..."
  curl -L --fail --retry 2 -o "$TOOLS_DIR/node.tgz" "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-$NODE_PLATFORM.tar.gz"
  tar -xzf "$TOOLS_DIR/node.tgz" -C "$TOOLS_DIR"
fi

if [ ! -x "$TCB" ]; then
  echo "Installing CloudBase CLI..."
  (cd "$TOOLS_DIR" && "$NODE_DIR/bin/npm" install @cloudbase/cli@3.5.0)
fi

echo "Checking project syntax..."
if [ -f "$PROJECT_DIR/index.js" ]; then
  "$NODE_CHECK_BIN" --check "$PROJECT_DIR/index.js"
fi
if [ -f "$PROJECT_DIR/app.js" ]; then
  "$NODE_CHECK_BIN" --check "$PROJECT_DIR/app.js"
fi

echo "Checking CloudBase login..."
if ! "$TCB" env:list >/tmp/cloudbase-test-env-list.log 2>&1; then
  echo "CloudBase CLI is not logged in. Run this, authorize in the browser, then rerun:"
  echo "$TCB login"
  exit 2
fi

echo "Deploying function $FUNCTION_NAME to $ENV_ID..."
printf '\n' | "$TCB" fn deploy "$FUNCTION_NAME" \
  --force \
  --dir "$PROJECT_DIR" \
  --runtime "$RUNTIME" \
  -e "$ENV_ID" \
  --json

echo "Ensuring HTTP access service $SERVICE_PATH exists..."
if ! "$TCB" service list -e "$ENV_ID" --json | grep -q "\"path\": \"$SERVICE_PATH\""; then
  CREATE_OUTPUT="$(printf 'Y\n' | "$TCB" service create -e "$ENV_ID" -p "$SERVICE_PATH" -f "$FUNCTION_NAME" --json)"
  echo "$CREATE_OUTPUT"
  if [ -z "$SERVICE_URL" ]; then
    SERVICE_URL="$(printf '%s' "$CREATE_OUTPUT" | sed -n 's/.*"url": *"\([^"]*\)".*/\1/p' | tail -1)"
  fi
fi

if [ -z "$SERVICE_URL" ]; then
  echo "Deployment finished. Set SERVICE_URL to run public verification."
  exit 0
fi

echo "Verifying $SERVICE_URL..."
curl -fsSI --max-time 25 "$SERVICE_URL" >/dev/null

if [ -f "$PROJECT_DIR/styles.css" ]; then
  curl -fsSI --max-time 25 "$SERVICE_URL/styles.css" >/dev/null
fi
if [ -f "$PROJECT_DIR/app.js" ]; then
  curl -fsSI --max-time 25 "$SERVICE_URL/app.js" >/dev/null
fi

SECRET_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 25 "$SERVICE_URL/.env")"
if [ "$SECRET_STATUS" != "404" ] && [ "$SECRET_STATUS" != "403" ]; then
  echo "Secret guard failed: $SERVICE_URL/.env returned $SECRET_STATUS"
  exit 3
fi

echo "Done: $SERVICE_URL"
