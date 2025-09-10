#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"

"$SCRIPT_DIR/teardown.sh"

cf create-org cfday
cf create-space -o cfday cfday
cf target -o cfday

cf create-service-broker cp-broker test password http://crossplane-service-broker.crossplane-service-broker.svc.cluster.local

pushd "$ROOT_DIR/pgweb"
{
  make build
  cf push -f ./manifest.yaml
}
popd

pushd "$ROOT_DIR/cloud-storage-file-browser"
{
  ./prepare-for-push.sh
  cf push -f ./manifest.yaml
}
popd
