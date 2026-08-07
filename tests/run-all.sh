#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash -n scripts/bash/check-gate.sh
bash -n install.sh
bash -n tests/run-tests.sh
bash -n tests/test-installer.sh
shellcheck scripts/bash/check-gate.sh install.sh tests/run-tests.sh tests/test-installer.sh
bash tests/run-tests.sh
bash tests/test-installer.sh
