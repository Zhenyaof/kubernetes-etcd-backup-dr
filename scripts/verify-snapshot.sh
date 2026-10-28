#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /var/backups/etcd/SNAPSHOT.db"
  exit 2
fi

SNAPSHOT="$1"

if [[ ! -f "$SNAPSHOT" ]]; then
  echo "ERROR: Snapshot file not found: $SNAPSHOT"
  exit 1
fi

echo "=== Snapshot File ==="
sudo ls -lh "$SNAPSHOT"

echo
echo "=== SHA-256 Checksum ==="
sudo sha256sum "$SNAPSHOT"

echo
echo "=== etcd Snapshot Status ==="
echo "Using a temporary Kubernetes pod with the backup directory mounted read-only."

kubectl run "etcd-snapshot-check-$(date +%s)" \
  --image=registry.k8s.io/etcd:3.7.0-0 \
  --restart=Never \
  --attach \
  --rm \
  --overrides="{\"spec\":{\"automountServiceAccountToken\":false,\"containers\":[{\"name\":\"verify\",\"image\":\"registry.k8s.io/etcd:3.7.0-0\",\"command\":[\"etcdutl\",\"snapshot\",\"status\",\"/backup/$(basename "$SNAPSHOT")\",\"--write-out=table\"],\"volumeMounts\":[{\"name\":\"backup\",\"mountPath\":\"/backup\",\"readOnly\":true}]}],\"volumes\":[{\"name\":\"backup\",\"hostPath\":{\"path\":\"/var/backups/etcd\",\"type\":\"Directory\"}}]}}"
