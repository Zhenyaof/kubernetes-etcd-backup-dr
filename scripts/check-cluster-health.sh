#!/usr/bin/env bash
set -u

echo "=== Kubernetes Node Status ==="
if ! kubectl get nodes; then
  echo "ERROR: Unable to retrieve Kubernetes nodes."
  exit 1
fi

echo
echo "=== API Server Readiness ==="
if ! kubectl get --raw='/readyz'; then
  echo "ERROR: Kubernetes API readiness check failed."
  exit 1
fi
echo

echo
echo "=== etcd Backup CronJob Status ==="
if ! kubectl get cronjob etcd-backup \
  -o custom-columns='NAME:.metadata.name,SUSPENDED:.spec.suspend,LAST-SCHEDULE:.status.lastScheduleTime'; then
  echo "WARNING: Could not inspect the etcd-backup CronJob."
fi

echo
echo "=== Local Snapshot Files ==="
if sudo find /var/backups/etcd -maxdepth 1 -type f -name '*.db' \
  -printf '%f (%s bytes)\n'; then
  :
else
  echo "WARNING: Could not list snapshot files."
fi
