# Kubernetes etcd Backup and Disaster Recovery

A Kubernetes project for automated etcd snapshot backups, snapshot validation, secure backup storage, retention management, and disaster recovery verification.

This project demonstrates how to create and validate etcd snapshots without modifying the live etcd data directory or performing a live-cluster restore.

## Table of Contents

- [Overview](#overview)
- [Architecture and Workflow](#architecture-and-workflow)
- [Project Structure](#project-structure)
- [Environment](#environment)
- [Backup Workflow](#backup-workflow)
- [Validation Results](#validation-results)
- [Backup Security and Retention](#backup-security-and-retention)
- [Disaster Recovery Testing](#disaster-recovery-testing)
- [Cluster Health Checks](#cluster-health-checks)
- [Usage](#usage)
- [Safety Considerations](#safety-considerations)
- [Future Improvements](#future-improvements)
- [Evidence and Screenshots](#evidence-and-screenshots)

## Overview

etcd stores Kubernetes cluster state, including information about resources and cluster configuration. Losing this data can prevent a Kubernetes control plane from recovering correctly.

This project implements a backup workflow that:

1. Creates an etcd snapshot using authenticated TLS.
2. Validates the snapshot using `etcdutl`.
3. Finalizes the snapshot with a timestamped filename.
4. Applies restrictive file permissions.
5. Retains the seven newest automated backups.
6. Provides a standalone script for verifying saved snapshots.
7. Provides a cluster health-check script.
8. Supports isolated disaster recovery testing.

The project was tested on a running Kubernetes environment using a manually triggered Job created from the backup CronJob.

**Important:** The scheduled CronJob remains suspended. Manual execution was used to test the backup workflow without enabling recurring scheduled execution.

## Architecture and Workflow

The backup process is implemented as a Kubernetes CronJob with multiple stages.

1. **Temporary-file preparation:** Checks for and handles stale temporary snapshot files.
2. **Snapshot creation:** Connects to the local etcd endpoint using TLS credentials and creates a snapshot.
3. **Snapshot validation:** Uses `etcdutl snapshot status` to validate the snapshot and display its metadata.
4. **Finalization:** Renames the validated snapshot to a timestamped filename and applies restrictive file permissions.
5. **Retention:** Keeps the seven newest automated snapshots and removes older automated backups.

The workflow uses a temporary filename before finalization so that an incomplete snapshot is not treated as a completed backup.

The standalone verification script provides an additional check by running `etcdutl` in a temporary Kubernetes Pod with the backup directory mounted read-only.

## Project Structure

```text
kubernetes-etcd-backup-dr/
├── manifests/
│   └── etcd-backup-cronjob.yaml
├── scripts/
│   ├── check-cluster-health.sh
│   └── verify-snapshot.sh
├── docs/
│   └── SCREENSHOT-GUIDE.md
└── README.md
```

## Environment

The project was tested in the following environment.

| Component | Version or Configuration |
|---|---|
| Operating system | Ubuntu 24.04 |
| Kubernetes | v1.37.0 |
| etcd | 3.7.0 |
| Backup execution | Kubernetes CronJob and manually triggered Job |
| Snapshot validation | `etcdutl snapshot status` |
| Backup directory | `/var/backups/etcd` |
| Scheduled timezone | `Asia/Tehran` |
| Automated retention | Seven newest automated backups |
| Scheduled execution | Suspended during testing |

## Backup Workflow

The CronJob manifest is located at:

`manifests/etcd-backup-cronjob.yaml`

Its schedule is configured as follows:

```yaml
schedule: "0 0 * * *"
timeZone: "Asia/Tehran"
suspend: true
```

The schedule represents midnight every day in the configured timezone. Because `suspend` is set to `true`, Kubernetes does not launch scheduled Jobs while the CronJob remains suspended.

### Manual execution

A manual Job was created from the CronJob template to test the workflow:

```bash
kubectl create job etcd-backup-final-test \
  --from=cronjob/etcd-backup

kubectl get job etcd-backup-final-test -w
```

The observed execution completed successfully:

```text
NAME                     STATUS              COMPLETIONS   DURATION   AGE
etcd-backup-final-test   Running             0/1           5s         5s
etcd-backup-final-test   SuccessCriteriaMet  0/1           6s         6s
etcd-backup-final-test   Complete            1/1           6s         6s
```

The completed Job confirms that Kubernetes successfully executed the Job. Snapshot validation and file checks provide additional evidence that the resulting backup is usable.

## Validation Results

### 1. Snapshot creation

The snapshot creation container reported the following output. JSON log lines have been abbreviated to the relevant fields for readability.

```text
{"level":"info","msg":"created temporary db file","path":"/backup/etcd-snapshot-pending.db.part"}
{"level":"info","msg":"opened snapshot stream; downloading"}
{"level":"info","msg":"fetching snapshot","endpoint":"https://127.0.0.1:2379"}
{"level":"info","msg":"completed snapshot read; closing"}
{"level":"info","msg":"fetched snapshot","endpoint":"https://127.0.0.1:2379","size":"2.8 MB","took":"118.69827ms","etcd-version":"3.7.0"}
{"level":"info","msg":"saved","path":"/backup/etcd-snapshot-pending.db"}
Snapshot saved at /backup/etcd-snapshot-pending.db
Server version 3.7.0
```

The output confirms that the snapshot was fetched from the local etcd endpoint and saved to the temporary backup location.

### 2. Snapshot validation

The validation stage returned:

```text
HASH 74f9a6d
REVISION 73556
TOTAL KEYS 405
TOTAL SIZE 2.8 MB
VERSION 3.7.0
```

This confirms that `etcdutl` successfully read the snapshot and reported its metadata.

### 3. Snapshot finalization

The finalization container reported:

```text
Snapshot finalized: /backup/etcd-snapshot-20261029-070003.db
-rw------- 1 root root 2.6M Oct 29 07:00 /backup/etcd-snapshot-20261029-070003.db
Applying seven-backup retention policy...
Automated backups remaining:
-rw------- 1 root root 2.6M Oct 26 14:24 /backup/etcd-snapshot-20261026-142456.db
-rw------- 1 root root 2.6M Oct 29 07:00 /backup/etcd-snapshot-20261029-070003.db
```

The finalized snapshot was stored on the host at:

```text
/var/backups/etcd/etcd-snapshot-20261029-070003.db
```

Its observed properties were:

| Property | Result |
|---|---|
| File size | 2,773,024 bytes |
| Owner | `root:root` |
| Permissions | `600` |
| SHA-256 | `63ae79893210074863533ad6ab1cce87d091d3426ee2a8f052153fd1882904d1` |
| etcd version | 3.7.0 |
| Snapshot revision | 73556 |
| Total keys | 405 |

Permission mode `600` means that only the file owner can read or write the file.

### 4. Standalone snapshot verification

The verification script is located at:

` scripts/verify-snapshot.sh `

Run it with:

```bash
./scripts/verify-snapshot.sh \
  /var/backups/etcd/etcd-snapshot-20261029-070003.db
```

The script:

1. Checks that the snapshot file exists.
2. Displays the file details.
3. Calculates and displays the SHA-256 checksum.
4. Creates a temporary verification Pod.
5. Waits for the verification Pod to complete successfully.
6. Displays the `etcdutl snapshot status` output.
7. Deletes the temporary Pod through its cleanup handler.

Actual verification output:

```text
=== Snapshot File ===
-rw------- 1 root root 2.7M Oct 29 10:30 /var/backups/etcd/etcd-snapshot-20261029-070003.db

=== SHA-256 Checksum ===
63ae79893210074863533ad6ab1cce87d091d3426ee2a8f052153fd1882904d1  /var/backups/etcd/etcd-snapshot-20261029-070003.db

=== Creating Verification Pod ===
pod/etcd-snapshot-check-1793257924-9175 created

=== Waiting for Verification ===
pod/etcd-snapshot-check-1793257924-9175 condition met

=== etcd Snapshot Status ===
┌─────────┬──────────┬────────────┬────────────┬─────────┐
│  HASH   │ REVISION │ TOTAL KEYS │ TOTAL SIZE │ VERSION │
├─────────┼──────────┼────────────┼────────────┼─────────┤
│ 74f9a6d │    73556 │        405 │     2.8 MB │   3.7.0 │
└─────────┴──────────┴────────────┴────────────┴─────────┘

SUCCESS: Snapshot status command completed.
```

The matching snapshot metadata and checksum provide evidence that the expected file was inspected and its contents could be read by the verification tool.

### 5. Previous snapshot validation

An earlier automated snapshot was also inspected.

| Property | Result |
|---|---|
| File | `etcd-snapshot-20261026-142456.db` |
| Size | 2,773,024 bytes |
| SHA-256 | `4a6fd63f9308c5a5ce145c5908bc18e59a6670c51e31e8f8d6c7a983cbd2f838` |
| Snapshot hash | `c6833532` |
| Revision | 40240 |
| Total keys | 324 |
| etcd version | 3.7.0 |

A separately named manual test snapshot was also validated.

| Property | Result |
|---|---|
| File | `manual-test-20261026-1635.db` |
| Size | 2,773,024 bytes |
| SHA-256 | `e0867f7816c4297da83afc797c626e51f422d07a36a7dda2def03c299e03005a` |
| Snapshot hash | `ef7515a5` |
| Revision | 33443 |
| Total keys | 425 |
| etcd version | 3.7.0 |

These snapshots were captured at different times, so their revisions, hashes, and key counts are not expected to match.

## Backup Security and Retention

The workflow includes the following controls:

- Uses TLS credentials to connect to the etcd endpoint.
- Validates the snapshot before finalizing it.
- Uses timestamped filenames for automated snapshots.
- Applies `600` permissions to finalized backup files.
- Retains the seven newest automated backups.
- Keeps manually named test snapshots outside the automated retention filename pattern.
- Uses a separate verification Pod with the backup directory mounted read-only.
- Disables automatic service-account token mounting in the verification Pod.

The retention logic was tested with dummy backup files. The test confirmed that only the seven newest automated snapshots were retained and that a manually named test snapshot was not removed by the automated retention policy.

During the end-to-end Job test, two automated snapshots existed, and both remained after the retention step. Seven is the maximum number of automated backups retained, not a requirement to maintain seven files when fewer backups exist.

## Disaster Recovery Testing

A previous snapshot was tested in an isolated etcd restore environment.

The isolated test demonstrated that the snapshot could be restored and that the recovered etcd instance elected a leader and reported internal gRPC health as `SERVING`.

This provides evidence that the snapshot contains recoverable etcd data. It does not, by itself, prove that a complete Kubernetes control plane can be restored successfully in production.

The restore test was isolated from the live etcd data directory.

**No restore was performed over the live cluster's etcd data.**

A complete disaster-recovery exercise should additionally validate the restored control plane, API readiness, required cluster resources, and application behavior in an isolated environment.

## Cluster Health Checks

The cluster health-check script is located at:

` scripts/check-cluster-health.sh `

Run it with:

```bash
./scripts/check-cluster-health.sh
```

The script checks:

- Kubernetes node readiness.
- Kubernetes API readiness.
- Backup CronJob status.
- Locally available `.db` backup files.

During testing, the Kubernetes nodes were `Ready`, and the API readiness endpoint returned:

```text
ok
```

After testing, the backup CronJob remained suspended:

```text
suspend=true
```

## Usage

### Inspect the CronJob

```bash
kubectl get cronjob etcd-backup -o yaml
kubectl get cronjob etcd-backup
```

### Check the CronJob suspension state

```bash
kubectl get cronjob etcd-backup \
  -o jsonpath='{.spec.suspend}{"\n"}'
```

Expected output in the current safety configuration:

```text
true
```

### Run a manual backup test

Use a unique Job name for each test:

```bash
kubectl create job etcd-backup-manual-test \
  --from=cronjob/etcd-backup

kubectl get job etcd-backup-manual-test -w
```

A Job created from a CronJob inherits its template, but its execution is independent of the CronJob's scheduled trigger.

### Inspect the Job and its Pods

```bash
kubectl describe job etcd-backup-final-test
kubectl get pods
```

To find the Pod belonging to the Job:

```bash
kubectl get pods \
  -l job-name=etcd-backup-final-test
```

### Inspect backup files

```bash
sudo ls -lah /var/backups/etcd
```

### Verify a snapshot

```bash
./scripts/verify-snapshot.sh \
  /var/backups/etcd/etcd-snapshot-20261029-070003.db
```

Replace the example filename with the actual snapshot you want to verify.

### Check cluster health

```bash
./scripts/check-cluster-health.sh
```

### Validate the repository state

```bash
git status -sb
git log -1 --oneline
```

The verification-script fix was committed and pushed in:

```text
5060831 Fix standalone snapshot verification output
```

## Safety Considerations

This project is designed to test backup creation and verification without risking the live etcd database.

- Keep the CronJob suspended until scheduled execution has been explicitly reviewed and approved.
- Do not run `kubeadm reset` as part of backup testing.
- Do not delete or overwrite `/var/lib/etcd`.
- Do not restore a snapshot over the live etcd data directory as a routine verification step.
- Protect backup files because etcd snapshots can contain sensitive Kubernetes state.
- Ensure the backup directory has sufficient disk space.
- Store a copy of important backups outside the cluster or host to protect against host failure.
- Periodically test recovery in an isolated environment.
- Treat a successful snapshot-status command as evidence of snapshot readability, not proof of complete production recovery.

## Future Improvements

Possible extensions include:

- Off-host or object-storage backup replication.
- Encryption at rest for exported backup files.
- Monitoring and alerting for failed backups.
- Automated backup-age and disk-space checks.
- A documented, fully isolated Kubernetes disaster-recovery exercise.
- Automated testing of retention edge cases.
- A recovery runbook covering control-plane restoration and post-recovery validation.

## Evidence and Screenshots

A separate screenshot guide is maintained at:

`docs/SCREENSHOT-GUIDE.md`

Recommended screenshots include:

- CronJob configuration and suspended state.
- Successful manual Job execution.
- Snapshot creation logs.
- Snapshot validation output.
- Finalized backup file and permissions.
- SHA-256 checksum.
- Retention behavior.
- Cluster health checks.
- Standalone snapshot verification.

Screenshots should show actual terminal or Kubernetes output. Redact credentials, tokens, private keys, and other sensitive information before publishing them.

## Project Status

The following components have been tested:

- Backup workflow triggered manually.
- Snapshot creation using etcd TLS credentials.
- Snapshot validation using `etcdutl`.
- Timestamped snapshot finalization.
- Restrictive file permissions.
- Seven-backup retention logic.
- Standalone snapshot verification.
- Basic Kubernetes cluster health checks.
- An isolated etcd snapshot restore test.

The scheduled CronJob remains suspended. A complete production disaster-recovery exercise has not been claimed.
