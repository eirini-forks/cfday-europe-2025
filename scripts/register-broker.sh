#!/bin/bash

set -euo pipefail

cf create-service-broker cp-broker test password http://crossplane-service-broker.crossplane-service-broker.svc.cluster.local

cf curl "/v3/service_offerings" | jq -r ".resources[].name" | xargs -n 1 cf enable-service-access
