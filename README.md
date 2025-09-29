# cfday-europe-2025

This repository aims to demonstrate how Korifi with managed service support can leverage the power of crossplane and bring all sorts of cloud native services to the Cloud Foundry ecosystem. This integration benefits both App Developers and CF Providers as follows:
- App Developers can push apps that run on Kubernetes and use a wide range of Cloud Native services that are currently not accessible to the cloud foundry ecosystem, while sticking to the well known and proven cf cli interface.
- CF Providers can add a multitude of services to their CF Platform purely declaratively, without writing a single line of code.
- Kubernetes as a standard runtime platform combined with the diverse crossplane ecosystem helps avoid vendor lockin.

This repository is meant to complement [Plug, Push, and Play: Building Hybrid Apps With Korifi and Cloud Native](https://cfdayeu2025.sched.com/event/27Dnn/plug-push-and-play-building-hybrid-apps-with-korifi-and-cloud-native-georgi-sabev-danail-branekov-sap-se): a session presented as CF Day Europe 2025. If you are interested you may watch the session recording before you get your hands dirty.

### Repository Structure

This repository combines a couple of other git repositories bundled as submodules, as well as some local assets
- crossplane-service-broker: This a fork of the [crossplane-service-broker](https://github.com/vshn/crossplane-service-broker). The main change in the fork is support for generic declarative services, so that providers don't have to modify the code of the broker itself.
- deploy/services: These are the definitions of the sample services used in the proposed scenario.
- csv2db: This is a simple serverless functions that converts csv to database tables.
- cloud-storage-file-browser: This is a fork of the [cloud-storage-file-browser](https://github.com/bashbaugh/cloud-storage-file-browser) app. The main change is introducing support for the VCAP_SERVICES env var.
- pgweb: This is a fork of the [pgweb](https://github.com/sosedoff/pgweb) app, where we have introduced support for the VCAP_SERVICES env var.
- scripts: Useful scripts for cluster setup, installation as well as "touching" the service broker so that we can add services dynamically without restarting Korifi or the Crossplane Broker.

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

First make sure you sync all the submodules

```
git submodule update --init --recursive'

```
Deploy the components

```
./scripts/deploy.sh
```

At this stage you will have Korifi and the Crossplane Service Broker Installed on your custer. In the next section you are going to register some services and push apps that make use of them.

### Usage

To showcase the power of Korifi + Crossplane in this section we are going to push some apps that can convert unstructured data from a cloud bucket to structured relational database format. This is achieved by installing and using a coulpe of services:
- storage: a service for managing cloud buckets
- psql: a database service
- storageevent: a serverless service that lets you register a handler to a bucket event.

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

5. Register the crossplane broker

```
cf create-service-broker cp-broker test password http://crossplane-service-broker.crossplane-service-broker.svc.cluster.local
```

Note: the broker is only accessible within the cluster

6. Install services

First apply the service definitions and "touch" the broker to force the system to see the change

```
kubectl apply -f "./deploy/services/*"
scripts/touch-broker.sh
```

Now enable the newly installed services

```
cf enable-service-access psql
cf enable-service-access storage
cf enable-service-access storageevent
```

Your marketplace is ready

```
cf marketplace
```

Next, we are going to create instances of each of the service offerings

7. Create psql and storage service instances

```
cf create-service psql standard mypsql --wait
cf create-service storage standard mystorage --wait
```

8. Create service keys

```
cf create-service-key mypsql mypsql
cf create-service-key mystorage mystorage
```

9. Create storageevent service

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

The "eventHandlerImage" contains the custom code that will convert unstructured data from the bucket to a database table, whenever the bucket is updated.

10. Deploy apps

```
cf push -f cloud-storage-file-browser/manifest.yaml
cf push -f pgweb/manifest.yaml
```

11. Open the file browser app and upload `deploy/examples/data.csv` to the bucket

12. Open the pgweb app and see the data from the csv has been inserted into the `data` table


