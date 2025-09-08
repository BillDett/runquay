#!/bin/bash

# 
# Start up a basic Quay environment via podman using object storage
#  If we pass in the argument "bkp" then it will start up the backup minio server as well
#
# It's not as fancy as OpenShift, or even Docker Compose...but it's simple and it works...
#

export QUAY=$(pwd)

export POD=quay-pod
if podman pod exists ${POD}; then
  echo "Existing pod ${POD} found. Removing..."
  podman pod rm -f ${POD}
fi

# 2. Create the pod
# The --publish flags map the pod's internal ports to the host machine.
echo "Creating pod ${POD}..."
podman pod create --name ${POD} \
  --publish 5432:5432 \
  --publish 9000:9000 \
  --publish 9001:9001 \
  --publish 8080:8080 \
  --publish 443:8443

echo "Starting minio..."
MINIO_USER=miniouser
MINIO_PASS=miniopassword
mkdir -p $QUAY/objectstorage
podman run --detach \
  --pod ${POD} \
  --name minio \
  -v $QUAY/objectstorage:/data:Z \
  -e "MINIO_ROOT_USER=${MINIO_USER}" \
  -e "MINIO_ROOT_PASSWORD=${MINIO_PASS}" \
  quay.io/minio/minio server /data --console-address ":9001"
echo "minio console available at http://localhost:9001"

sleep 1

echo "making sure the bucket is available..."
podman run --detach \
  --pod ${POD} \
  --name bucket_check \
  -e AWS_ACCESS_KEY_ID="${MINIO_USER}" \
  -e AWS_SECRET_ACCESS_KEY="${MINIO_PASS}" \
  -e AWS_DEFAULT_REGION="us-east-1" \
  public.ecr.aws/aws-cli/aws-cli \
  --endpoint-url http://localhost:9000 \
  s3api create-bucket --bucket ${BUCKET_NAME} || true


echo "Starting Postgres..."
mkdir -p $QUAY/postgres-quay
podman run --detach \
  --pod ${POD} \
  --name postgresql-quay \
  -e POSTGRES_USER=quayuser \
  -e POSTGRES_PASSWORD=quaypass \
  -e POSTGRES_DB=quay \
  -e POSTGRES_ADMIN_PASSWORD=adminpass \
  -v $QUAY/postgres-quay:/var/lib/postgresql/data:Z \
  docker.io/library/postgres:12.1

sleep 5

podman exec -it postgresql-quay /bin/bash -c 'echo "CREATE EXTENSION IF NOT EXISTS pg_trgm" | psql -d quay -U quayuser'


echo "Starting Redis..."
podman run --detach \
  --pod ${POD} \
  --name redis \
  docker.io/library/redis:latest


echo "Starting Quay..."
mkdir -p $QUAY/storage
podman run --detach \
  --pod ${POD} \
  --name quay \
  -v $QUAY/config:/conf/stack:Z \
  -v $QUAY/storage:/datastorage:Z \
  quay.io/projectquay/quay:3.15.0
echo "quay.io console available at http://localhost:8080"

# Optionally start the backup minio server
if [ "$1" = "bkp" ]; then
	echo; echo;
        mkdir -p $QUAY/backupstorage
        podman run --detach \
          --pod ${POD} \
          --name bkpminio \
       	  -v $QUAY/backupstorage:/data:Z \
	  -e "MINIO_ROOT_USER=miniouser" \
          -e  "MINIO_ROOT_PASSWORD=miniopassword" \
          quay.io/minio/minio server /data --console-address ":7001"
        echo "backup minio console available at http://localhost:7001"
fi

sleep 3

podman ps
