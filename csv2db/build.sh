#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

pushd $SCRIPT_DIR
{
  pack build --builder=gcr.io/buildpacks/builder korifi/csv2db:$(uuidgen)
}
popd
