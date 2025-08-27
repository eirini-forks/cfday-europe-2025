#!/bin/bash

gcloud container clusters create cfday \
  --location europe-west1-b \
  --node-locations europe-west1-b \
  --machine-type=e2-custom-6-8192 \
  --num-nodes 1
