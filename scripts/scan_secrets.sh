#!/usr/bin/env bash
set -euo pipefail

PATTERN="${PATTERN:-'(password|secret|token|api_key)[[:space:]]*=[[:space:]]*["'\''][^"'\'' ]{8,}["'\'']'}"
IGNORE_FILE="${IGNORE_FILE:-.secret-scan-ignore}"

matches=$(grep -r -E "$PATTERN" \
  --include="*.sh" \
  --include="*.json" \
  --exclude-dir=".git" \
  . || true)

if [[ -f "$IGNORE_FILE" ]]; then
  matches=$(printf '%s\n' "$matches" | grep -v -f "$IGNORE_FILE" || true)
fi

if [[ -n "$matches" ]]; then
  echo "⚠ Potential secrets detected:"
  echo "$matches"
  exit 1
fi

echo "✓ No secrets detected"
