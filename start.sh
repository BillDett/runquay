#!/bin/bash

# 
# Start up a basic Quay environment via podman using object storage
#  If we pass in the argument "bkp" then it will start up the backup minio server as well
#
# It's not as fancy as OpenShift, or even Docker Compose...but it's simple and it works...
#

export QUAY=$(pwd)

echo "Starting minio..."
MINIO_USER=miniouser
MINIO_PASS=miniopassword
mkdir -p $QUAY/objectstorage
sudo podman run -d --rm --replace --name minio \
	-p 9000:9000 -p 9001:9001 \
        -v $QUAY/objectstorage:/data:Z \
	-e "MINIO_ROOT_USER=${MINIO_USER}" \
	-e "MINIO_ROOT_PASSWORD=${MINIO_PASS}" \
	quay.io/minio/minio server /data --console-address ":9001"
echo "minio console available at http://localhost:9001"

sleep 1

MINIOIP=$(sudo podman inspect -f "{{.NetworkSettings.IPAddress}}" minio)

echo "making sure the bucket is available..."
sudo podman run --rm \
  -e AWS_ACCESS_KEY_ID="${MINIO_USER}" \
  -e AWS_SECRET_ACCESS_KEY="${MINIO_PASS}" \
  -e AWS_DEFAULT_REGION="us-east-1" \
  public.ecr.aws/aws-cli/aws-cli \
  --endpoint-url http://${MINIOIP}:9000 \
  s3api create-bucket --bucket ${BUCKET_NAME} || true


echo "Starting Postgres..."
mkdir -p $QUAY/postgres-quay
sudo podman run -d --rm --replace --name postgresql-quay \
  -e POSTGRES_USER=quayuser \
  -e POSTGRES_PASSWORD=quaypass \
  -e POSTGRES_DB=quay \
  -e POSTGRES_ADMIN_PASSWORD=adminpass \
  -p 5432:5432 \
  -v $QUAY/postgres-quay:/var/lib/postgresql/data:Z \
  docker.io/library/postgres:12.1

sleep 5

sudo podman exec -it postgresql-quay /bin/bash -c 'echo "CREATE EXTENSION IF NOT EXISTS pg_trgm" | psql -d quay -U quayuser'

POSTGRESIP=$(sudo podman inspect -f "{{.NetworkSettings.IPAddress}}" postgresql-quay)

echo "Starting Redis..."
sudo podman run -d --rm --replace --name redis \
  -p 6379:6379 \
  docker.io/library/redis:latest

REDISIP=$(sudo podman inspect -f "{{.NetworkSettings.IPAddress}}" redis)

echo "Fixing config with Minio, Postgres and Redis IP addresses..."
cat $QUAY/config/config_template.yaml | sed "s/{{MINIOIP}}/$MINIOIP/g" | sed "s/{{POSTGRESIP}}/$POSTGRESIP/g" | sed "s/{{REDISIP}}/$REDISIP/g" > $QUAY/config/config.yaml

echo "Starting Quay..."
mkdir -p $QUAY/storage
sudo podman run -d --replace -p 8080:8080 -p 8443:8443  \
   --name=quay \
   -v $QUAY/config:/conf/stack:Z \
   -v $QUAY/storage:/datastorage:Z \
	   quay.io/projectquay/quay:3.15.0
echo "quay.io console available at http://localhost:8080"

# Optionally start the backup minio server
if [ "$1" = "bkp" ]; then
	echo; echo;
        mkdir -p $QUAY/backupstorage
	sudo podman run -d --rm --replace --name bkpminio \
		-p 7000:7000 -p 7001:7001 \
       		-v $QUAY/backupstorage:/data:Z \
		-e "MINIO_ROOT_USER=miniouser" \
		-e  "MINIO_ROOT_PASSWORD=miniopassword" \
		quay.io/minio/minio server /data --console-address ":7001"
        echo "backup minio console available at http://localhost:7001"
fi

sleep 3

sudo podman ps
