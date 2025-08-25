#!/bin/bash

gcloud --quiet container clusters delete cfday \
  --location europe-west1-b
