# Kubernetes etcd Backup and Disaster Recovery — Validation

## Environment
- Kubernetes: v1.37.0
- etcd: v3.7.0
- Topology: single-node control plane
- Backup directory: /var/backups/etcd

## Backup validation
Two existing etcd snapshots were independently checked using
`etcdutl snapshot status` inside Kubernetes pods with the backup
directory mounted read-only.

| Snapshot | Revision | Total keys | Size | Result |
|---|---:|---:|---:|---|
| etcd-snapshot-20261026-142456.db | 40240 | 324 | 2.8 MB | Passed |
| manual-test-20261026-1635.db | 33443 | 425 | 2.8 MB | Passed |

The checks establish that etcd can read and inspect both snapshots.
They do not, by themselves, establish a successful recovery.

## Isolated restore validation
The primary snapshot was restored to `/restore-data` in a test pod.
The restore command completed successfully.

A separate test pod then started etcd v3.7.0 using the restored data.
Its logs reported:
- The backend database opened successfully.
- The restored revision was 40240.
- The node elected itself leader.
- The gRPC health service reported SERVING.
- etcd reported that it was ready to serve client requests.

This is strong evidence that the restored data can start an isolated
single-node etcd instance. A fresh independent endpoint-health command
was not completed because the old test pod had already stopped.

## Cluster health
At the time of validation:
- Kubernetes node status: Ready.
- Kubernetes API `/readyz`: returned `ok`.
- The live cluster's etcd data directory was not used for the restore test.

## Network configuration
A persistent Netplan configuration was added for the control-plane
compatibility address `192.168.198.145/32` on `ens33`, alongside DHCP.
Netplan generation and configuration application succeeded. A reboot
persistence test has not yet been performed.

## Scheduled backup
The `etcd-backup` CronJob is intentionally suspended during validation.
It should remain suspended until its configuration, image availability,
credentials, and backup execution are reviewed.

## Limitations and next steps
- Perform a fresh isolated restore-and-health test.
- Validate automated CronJob execution before enabling its schedule.
- Confirm backup retention behavior.
- Copy backups off the VM to protect against disk or VM loss.
- Test network configuration persistence during a planned maintenance
  window with VMware console access.
- Record recovery steps and expected recovery time.

## Safety
Do not restore a test snapshot over the live `/var/lib/etcd` directory.
Keep snapshot files and Kubernetes credentials out of version control.
