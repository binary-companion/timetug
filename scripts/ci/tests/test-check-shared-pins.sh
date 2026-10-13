#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 -m unittest scripts/ci/tests/test_check_shared_pins.py
python3 scripts/ci/check-shared-pins.py
