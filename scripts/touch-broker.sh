#!/bin/bash

ktouch() {
  objYaml=$(cat /dev/stdin)
  ns=$(yq .metadata.namespace <<<$objYaml)
  kind=$(yq .kind <<<$objYaml)
  name=$(yq .metadata.name <<<$objYaml)
  kubectl --namespace "$ns" label "$kind" "$name" --overwrite touched-at="$(date +%Y-%m-%d-%H-%M-%S-%N)"
}

broker="$(kubectl --namespace cf get cfservicebrokers.korifi.cloudfoundry.org -ojsonpath='{.items[0].metadata.name}')"
kubectl --namespace cf get cfservicebrokers.korifi.cloudfoundry.org "$broker" -o yaml | ktouch
