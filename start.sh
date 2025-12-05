#!/bin/bash

# 
# Start up a basic Quay environment via podman using object storage
#  If we pass in the argument "bkp" then it will start up the backup minio server as well
#
# It's not as fancy as OpenShift, or even Docker Compose...but it's simple and it works...
#

export QUAY=$(pwd)
export BUCKET_NAME=quaybucket

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
  --publish 3900:3900 \
  --publish 3901:3901 \
  --publish 3902:3902 \
  --publish 3903:3903 \
  --publish 8080:8080 \
  --publish 6379:6379 \
  --publish 8443:8443

garage() {
  podman exec -ti garage /garage "$@"
}


echo "Starting garage..."

mkdir -p $QUAY/garage/meta
mkdir -p $QUAY/garage/data
cat > $QUAY/garage/garage.toml <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "sqlite"

replication_factor = 1

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "$(openssl rand -hex 32)"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage.localhost"
index = "index.html"

[k2v_api]
api_bind_addr = "[::]:3904"

[admin]
api_bind_addr = "[::]:3903"
admin_token = "$(openssl rand -base64 32)"
metrics_token = "$(openssl rand -base64 32)"
EOF
podman run --detach \
  --pod ${POD} \
  --name garage \
  -e RUST_LOG=garage=debug \
  -v $QUAY/garage/garage.toml:/etc/garage.toml:Z \
  -v $QUAY/garage/meta:/var/lib/garage/meta:Z \
  -v $QUAY/garage/data:/var/lib/garage/data:Z \
  docker.io/dxflrs/garage:v2.1.0

sleep 1

garage status
export GARAGE_NODE_ID=$(garage status | awk '/^ID/{getline; print $1}')

echo "making sure garage node $GARAGE_NODE_ID is configured properly..."
if $(garage bucket info $BUCKET_NAME > /dev/null 2>&1); then
  echo "\tSee $BUCKET_NAME, assume garage is set up okay..."
else
  echo "\tDon't see $BUCKET_NAME...let's configure garage"
  garage layout assign -z dc1 -c 1G "$GARAGE_NODE_ID"
  garage layout apply --version 1
  garage bucket create "$BUCKET_NAME"
  export KO=$(garage key create "$BUCKET_NAME"_key)
  export GARAGE_ACCESS_KEY=$(echo "$KO" | awk '/^Key ID/{print $3}')
  export GARAGE_SECRET_KEY=$(echo "$KO" | awk '/^Secret key/{print $3}')
  echo "\tAdding garage keys to quay config..."
  cat $QUAY/config/config_template.yaml | sed "s/{{GARAGE_ACCESS_KEY}}/$GARAGE_ACCESS_KEY/g" | sed "s/{{GARAGE_SECRET_KEY}}/$GARAGE_SECRET_KEY/g" > $QUAY/config/config.yaml
  garage bucket allow --read --write --owner $BUCKET_NAME --key "$BUCKET_NAME"_key
fi

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
podman run --detach \
  --pod ${POD} \
  --name quay \
  -v $QUAY/config:/conf/stack:Z \
   quay.io/projectquay/quay:3.15.0
echo "quay.io console available at http://localhost:8080"

sleep 3

podman ps
