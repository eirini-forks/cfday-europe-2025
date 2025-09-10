#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"

cf delete-org cfday -f
"$SCRIPT_DIR/unregister-broker.sh"

kubectl delete -f "$ROOT_DIR/deploy/services/*"
