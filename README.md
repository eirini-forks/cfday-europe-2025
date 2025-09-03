# cfday-europe-2025

### Installation

1. Create a gcp cluster

```
./scripts/create-gcp-cluster.sh
```

2. Target the cluster:

```
gcloud container clusters get-credentials
```

3. Deploy Korifi, Crossplane Broker and Service Catalog

```
./scripts/deploy.sh
```

### Usage

1. Target and login

```
cf login -u cf-admin -a https://cf.cfday.korifi.cf-app.com
```

4. Create an org and space

```
cf create-org cfday
cf create-space -o cfday cfday
cf target -o cfday -s cfday
```

5. Register broker and enable services

```
cf create-service-broker cp-broker test password http://crossplane-service-broker.crossplane-service-broker.svc.cluster.local
cf enable-service-access psql
cf enable-service-access storage
cf enable-service-access storageevent
```

Note: the broker is only accessible within the cluster

6. Create psql and storage service instances

```
cf create-service psql standard mypsql --wait
cf create-service storage standard mystorage --wait
```

7. Create service keys

```
cf create-service-key mypsql mypsql
cf create-service-key mystorage mystorage
```

8. Create storageevent service

```
cf create-service storageevent standard mystorageevent --wait -c "$(
  cat <<EOF
{
  "bucketName": "$(cf service-key mystorage mystorage | tail -n +2 | jq -r .credentials.bucketName)",
  "eventHandlerImage": "korifi/csv2db:0.0.1",
  "args": [
    "$(cf service-key mypsql mypsql | tail -n +2 | jq -r .credentials.dbURL)"
  ]
}
EOF
)"
```

9. Deploy apps

```
cf push -f cloud-storage-file-browser/manifest.yaml
cf push -f pgweb/manifest.yaml
```

10. Open the file browser app and upload `deploy/examples/data.csv` to the bucket

11. Open the pgweb app and see the data from the csv has been inserted into the `data` table


