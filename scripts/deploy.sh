#!/bin/bash

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"

retry() {
  until $@; do
    echo -n .
    sleep 1
  done
  echo
}

install_korifi() {
  kubectl delete namespace korifi-installer --ignore-not-found
  kubectl apply -f https://github.com/cloudfoundry/korifi/releases/latest/download/install-korifi-kind.yaml
  kubectl --namespace korifi-installer wait --for=jsonpath='.status.ready'=1 jobs install-korifi
  kubectl --namespace korifi-installer logs --follow job/install-korifi
}

function deploy_crossplane_service_broker() {
  echo "Deploying Crossplane..."
  helm repo add crossplane-stable https://charts.crossplane.io/stable
  helm repo update
  helm upgrade \
    --install \
    --namespace crossplane-system \
    --create-namespace \
    crossplane \
    crossplane-stable/crossplane \
    --version v1.20 \
    --wait

  echo "Deploy crossplane functions"
  kubectl apply -f "$SCRIPT_DIR/assets/crossplane-functions"

  echo "Creating crossplane secrets"
  kubectl -n crossplane-system delete secret gcp-family-providerconfig --ignore-not-found
  vault kv get -field=value common/gcp/functions-key |
    kubectl -n crossplane-system create secret generic gcp-family-providerconfig --from-file=sa.json=/dev/stdin

  echo "Deploy crossplane providers"
  kubectl apply -f "$SCRIPT_DIR/assets/crossplane-providers"
  retry kubectl apply -f "$SCRIPT_DIR/assets/crossplane-providerconfigs"

  echo "Building Crossplane Service Broker..."
  export CROSSPLANE_BROKER_IMAGE="korifi/crossplane-service-broker:$(uuidgen)"
  export OSB_SERVICE_IDS="psql-offering"
  pushd "$ROOT_DIR/crossplane-service-broker"
  {
    make build
    docker build . -t "$CROSSPLANE_BROKER_IMAGE"
  }
  popd
  docker push $CROSSPLANE_BROKER_IMAGE

  echo "Deploying Crossplane Service Broker..."
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: crossplane-service-broker
EOF
  cat "$SCRIPT_DIR"/assets/crossplane-broker/* | envsubst | kubectl --namespace crossplane-service-broker apply -f -

  kubectl delete secret -n crossplane-service-broker crossplane-service-broker --ignore-not-found
  kubectl create secret -n crossplane-service-broker generic crossplane-service-broker \
    --from-literal=password=password
  kubectl -n crossplane-service-broker wait --for=condition=available deployment crossplane-service-broker --timeout=15m
}

function create_psql_service_offering() {
  echo "Creating PostgreSQL service offering..."
  kubectl apply -f "$SCRIPT_DIR/assets/psql-offering"
}

main() {
  install_korifi

  deploy_crossplane_service_broker
  create_psql_service_offering
}

main
