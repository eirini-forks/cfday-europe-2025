#!/bin/bash

set -euo pipefail

cf delete-service-broker cp-broker -f
kubectl delete cfserviceofferings,cfserviceplans --all -n cf
