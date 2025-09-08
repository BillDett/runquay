
export POD=quay-pod

echo "Stopping pod ${POD}..."

podman stop minio
podman stop redis
podman stop postgresql-quay
podman stop quay

podman pod stop ${POD}

podman pod rm ${POD}

echo "done"
