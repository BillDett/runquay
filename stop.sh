
export POD=quay-pod

echo "Stopping pod ${POD}..."

podman stop garage
podman stop redis
podman stop postgresql-quay
podman stop quay

podman pod stop ${POD}

podman pod rm ${POD}

echo "done"
