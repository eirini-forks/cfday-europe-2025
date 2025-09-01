#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"
DEPLOY_DIR="${ROOT_DIR}/deploy"

retry() {
  until $@; do
    echo -n .
    sleep 1
  done
  echo
}

install_korifi() {
  $SCRIPT_DIR/helpers/install-dependencies.sh

  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: cf
EOF

  kubectl --namespace cf delete secret image-registry-credentials --ignore-not-found
  kubectl --namespace cf create secret docker-registry image-registry-credentials \
    --docker-username="_json_key" \
    --docker-password="$(vault kv get -field=value common/gcp/functions-key)" \
    --docker-server="europe-docker.pkg.dev"

  helm repo add korifi https://cloudfoundry.github.io/korifi/
  helm repo update

  helm upgrade --install korifi korifi/korifi \
    --namespace korifi \
    --create-namespace \
    --set=adminUserName="cf-admin" \
    --set=defaultAppDomainName="cfday.korifi.cf-app.com" \
    --set=generateIngressCertificates="true" \
    --set=logLevel="debug" \
    --set=debug="false" \
    --set=stagingRequirements.buildCacheMB="1024" \
    --set=api.apiServer.url="cf.cfday.korifi.cf-app.com" \
    --set=controllers.taskTTL="5s" \
    --set=jobTaskRunner.jobTTL="5s" \
    --set=containerRepositoryPrefix="europe-docker.pkg.dev/cf-on-k8s-wg/cfday-images/" \
    --set=kpackImageBuilder.builderRepository="europe-docker.pkg.dev/cf-on-k8s-wg/cfday-images/kpack-builder" \
    --set=networking.gatewayClass="contour" \
    --set=experimental.managedServices.enabled="true" \
    --set=experimental.managedServices.trustInsecureBrokers="true" \
    --set=api.resources.limits.cpu=50m \
    --set=api.resources.limits.memory=100Mi \
    --set=controllers.resources.limits.cpu=50m \
    --set=controllers.resources.limits.memory=100Mi \
    --set=kpackImageBuilder.resources.limits.cpu=50m \
    --set=kpackImageBuilder.resources.limits.memory=100Mi \
    --set=statefulsetRunner.resources.limits.cpu=50m \
    --set=statefulsetRunner.resources.limits.memory=100Mi \
    --set=jobTaskRunner.resources.limits.cpu=50m \
    --set=jobTaskRunner.resources.limits.memory=100Mi \
    --set=api.image="korifi/korifi-api-cfday2025:0.0.1" \
    --set=controllers.image="korifi/korifi-controllers-cfday2025:0.0.1" \
    --wait

  kubectl wait --for=condition=ready clusterbuilder --all=true --timeout=15m
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
  kubectl apply -f "$DEPLOY_DIR/crossplane-functions"

  echo "Creating crossplane secrets"
  kubectl -n crossplane-system delete secret gcp-family-providerconfig --ignore-not-found
  vault kv get -field=value common/gcp/functions-key |
    kubectl -n crossplane-system create secret generic gcp-family-providerconfig --from-file=sa.json=/dev/stdin

  echo "Deploy crossplane providers"
  kubectl apply -f "$DEPLOY_DIR/crossplane-providers"
  retry kubectl apply -f "$DEPLOY_DIR/crossplane-providerconfigs"

  echo "Building Crossplane Service Broker..."
  export CROSSPLANE_BROKER_IMAGE="korifi/crossplane-service-broker:$(uuidgen)"
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
  cat "$DEPLOY_DIR"/crossplane-broker/* | envsubst | kubectl --namespace crossplane-service-broker apply -f -

  kubectl delete secret -n crossplane-service-broker crossplane-service-broker --ignore-not-found
  kubectl create secret -n crossplane-service-broker generic crossplane-service-broker \
    --from-literal=password=password
  kubectl -n crossplane-service-broker wait --for=condition=available deployment crossplane-service-broker --timeout=15m
}

function create_services() {
  echo "Creating service offerings..."
  kubectl apply -f "$DEPLOY_DIR/services/*"
}

function update_cluster_dns() {
  kubectl get service envoy-korifi -n korifi-gateway -ojsonpath='{.status.loadBalancer.ingress[0]}'
  gcloud dns record-sets update "*.cfday.korifi.cf-app.com." \
    --rrdatas="$(kubectl get service envoy-korifi -n korifi-gateway -ojsonpath='{.status.loadBalancer.ingress[0].ip}')" \
    --type=A \
    --ttl=300 \
    --zone=korifi
}

main() {
  install_korifi

  deploy_crossplane_service_broker
  create_services
  update_cluster_dns
}

main
