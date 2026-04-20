#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
fi

if [ $# -lt 1 ]; then
  echo "Usage: $0 <workflow-file>" >&2
  exit 1
fi
cd "$SCRIPT_DIR/elixir"
mise exec -- ./bin/symphony --i-understand-that-this-will-be-running-without-the-usual-guardrails "$1"
