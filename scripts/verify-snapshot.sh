#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /var/backups/etcd/SNAPSHOT.db"
  exit 2
fi

SNAPSHOT="$1"
BACKUP_DIR="/var/backups/etcd"
POD="etcd-snapshot-check-$(date +%s)-$RANDOM"

if ! sudo test -f "$SNAPSHOT"; then
  echo "ERROR: Snapshot file not found: $SNAPSHOT"
  exit 1
fi

echo "=== Snapshot File ==="
sudo ls -lh "$SNAPSHOT"

echo
echo "=== SHA-256 Checksum ==="
sudo sha256sum "$SNAPSHOT"

echo
echo "=== Creating Verification Pod ==="

cleanup() {
  kubectl delete pod "$POD" --ignore-not-found --wait=true \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl run "$POD" \
  --image=registry.k8s.io/etcd:3.7.0-0 \
  --restart=Never \
  --overrides="{\"spec\":{\"automountServiceAccountToken\":false,\"containers\":[{\"name\":\"verify\",\"image\":\"registry.k8s.io/etcd:3.7.0-0\",\"command\":[\"etcdutl\",\"snapshot\",\"status\",\"/backup/$(basename "$SNAPSHOT")\",\"--write-out=table\"],\"volumeMounts\":[{\"name\":\"backup\",\"mountPath\":\"/backup\",\"readOnly\":true}]}],\"volumes\":[{\"name\":\"backup\",\"hostPath\":{\"path\":\"$BACKUP_DIR\",\"type\":\"Directory\"}}]}}"

echo
echo "=== Waiting for Verification ==="

if ! kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  "pod/$POD" --timeout=120s; then
  echo "ERROR: Verification did not succeed."
  kubectl logs "$POD" || true
  kubectl describe pod "$POD" || true
  exit 1
fi

echo
echo "=== etcd Snapshot Status ==="
kubectl logs "$POD"

echo
echo "SUCCESS: Snapshot status command completed."
