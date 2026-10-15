#!/usr/bin/env bash
# The connectors form of scripts/dev/use-local-library.sh: use-local-connectors.sh <checkout> | --restore [--force]
set -euo pipefail
exec "$(dirname "$0")/use-local-library.sh" calendar-connectors "$@"
