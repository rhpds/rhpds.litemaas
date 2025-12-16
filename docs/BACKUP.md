# LiteMaaS Backup and Disaster Recovery

This document describes the automated backup solution for LiteMaaS deployments.

## Overview

LiteMaaS includes automated monthly backups for:
- **PostgreSQL Database**: Logical backup via `pg_dump` → uploaded to S3
- **PVC Data**: VolumeSnapshot stored in OpenShift storage backend

## Backup Schedule

Backups run **monthly on the 1st at 2 AM** via cronjob on the bastion host.

```bash
# Cronjob schedule
0 2 1 * * /usr/local/bin/backup-litemaas-<namespace>.sh
```

## Retention Policy

- **S3 Database Dumps**: Last 12 backups (1 year of monthly backups)
- **VolumeSnapshots**: Last 3 snapshots (recent restore points)

Older backups are automatically deleted when retention limits are exceeded.

## Setup

### Prerequisites

1. **S3 Bucket**: Create an S3 bucket for backups (e.g., `maas-db-backup`)
2. **IAM Role**: Create IAM role with S3 permissions
3. **Bastion Access**: SSH access to bastion host
4. **OpenShift CLI**: `oc` command authenticated to cluster

### IAM Configuration

Create an IAM role with the following policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowS3BackupBucketAccess",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::your-bucket-name/*"
        },
        {
            "Sid": "AllowS3BackupBucketList",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": "arn:aws:s3:::your-bucket-name"
        }
    ]
}
```

Trust relationship:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Important**: After attaching the IAM instance profile to the bastion EC2 instance, you must **stop and start** (not reboot) the instance for the metadata service to recognize the new role.

### Installation

Run the setup script from the repository:

```bash
cd ~/work/code/rhpds.litemaas

# Install backup cronjob
./setup-litemaas-backup-cronjob.sh <namespace> <s3-bucket>

# Example
./setup-litemaas-backup-cronjob.sh litellm-rhpds maas-db-backup
```

The script will:
1. Create backup script at `/usr/local/bin/backup-litemaas-<namespace>.sh`
2. Configure monthly cronjob
3. Verify prerequisites (oc, aws CLI, namespace exists)

## Verification

### Check Cronjob

```bash
# View configured cronjobs
crontab -l

# Should show:
# 0 2 1 * * /usr/local/bin/backup-litemaas-litellm-rhpds.sh
```

### Manual Backup Test

```bash
# Run backup manually
sudo /usr/local/bin/backup-litemaas-<namespace>.sh

# View logs
tail -f /var/log/litemaas-backup.log
```

### Verify Backups

**S3 Database Backups:**

```bash
# List S3 backups
aws s3 ls s3://maas-db-backup/litemaas-backups/

# Example output:
# 2025-12-16 05:39:00    1.6 MiB database-20251216-053856.sql.gz
# 2025-12-16 06:33:08    1.6 MiB database-20251216-063305.sql.gz
```

**VolumeSnapshots in OpenShift:**

```bash
# List VolumeSnapshots
oc get volumesnapshot -n litellm-rhpds

# Example output:
# NAME                                READYTOUSE   RESTORESIZE   AGE
# litemaas-snapshot-20251216-051214   true         10Gi          87m
# litemaas-snapshot-20251216-053857   true         10Gi          61m
# litemaas-snapshot-20251216-063306   true         10Gi          7m
```

## Disaster Recovery

### Restore Database from S3

```bash
# 1. Download backup from S3
aws s3 cp s3://maas-db-backup/litemaas-backups/database-20251216-053856.sql.gz /tmp/

# 2. Decompress
gunzip /tmp/database-20251216-053856.sql.gz

# 3. Get PostgreSQL pod name
DB_POD=$(oc get pods -n litellm-rhpds -l app=litellm-postgres -o jsonpath='{.items[0].metadata.name}')

# 4. Copy SQL file to pod
oc cp /tmp/database-20251216-053856.sql litellm-rhpds/${DB_POD}:/tmp/restore.sql

# 5. Get database credentials
DB_USER=$(oc get secret litemaas-db -n litellm-rhpds -o jsonpath='{.data.username}' | base64 -d)
DB_PASSWORD=$(oc get secret litemaas-db -n litellm-rhpds -o jsonpath='{.data.password}' | base64 -d)
DB_NAME=$(oc get secret litemaas-db -n litellm-rhpds -o jsonpath='{.data.database}' | base64 -d)

# 6. Restore database
oc exec -n litellm-rhpds ${DB_POD} -- \
  bash -c "PGPASSWORD='${DB_PASSWORD}' psql -U ${DB_USER} -d ${DB_NAME} -f /tmp/restore.sql"
```

### Restore PVC from VolumeSnapshot

```bash
# 1. Scale down PostgreSQL
oc scale statefulset litellm-postgres -n litellm-rhpds --replicas=0

# 2. Create PVC from snapshot
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-storage-restored
  namespace: litellm-rhpds
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  dataSource:
    name: litemaas-snapshot-20251216-053857
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

# 3. Update StatefulSet to use restored PVC
# (or delete old PVC and rename restored one)

# 4. Scale up PostgreSQL
oc scale statefulset litellm-postgres -n litellm-rhpds --replicas=1
```

## Troubleshooting

### Backup Logs

```bash
# View full backup log
cat /var/log/litemaas-backup.log

# Watch backup in real-time
tail -f /var/log/litemaas-backup.log
```

### Common Issues

**S3 Upload Failed - Credentials Not Found**
```
Solution: Verify IAM instance profile is attached and stop/start the EC2 instance
aws ec2 describe-instances --region us-east-2 --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'
```

**PostgreSQL Pod Not Found**
```
Solution: Check if PostgreSQL is running
oc get pods -n litellm-rhpds -l app=litellm-postgres
```

**VolumeSnapshot Fails**
```
Solution: Verify VolumeSnapshotClass exists
oc get volumesnapshotclass
```

### Cleanup Old Backups Manually

```bash
# Delete old S3 backups (keep last 12)
aws s3 ls s3://maas-db-backup/litemaas-backups/ | \
  grep "database-" | sort -r | tail -n +13 | \
  awk '{print $4}' | xargs -I {} aws s3 rm s3://maas-db-backup/litemaas-backups/{}

# Delete old VolumeSnapshots (keep last 3)
oc get volumesnapshot -n litellm-rhpds -l app=litemaas-backup \
  --sort-by=.metadata.creationTimestamp -o name | head -n -3 | \
  xargs oc delete -n litellm-rhpds
```

## HAProxy Timeout Configuration

LiteMaaS routes are configured with a **600-second (10-minute) timeout** to support long-running LLM inference requests, especially for models with large context windows (e.g., Llama Scout 17B with 400k context).

All routes include this annotation:

```yaml
metadata:
  annotations:
    haproxy.router.openshift.io/timeout: 600s
```

This prevents HAProxy from timing out during:
- Long-running chat completions
- Large context window processing
- Tool calling with multiple iterations
- Model loading delays

## Related Documentation

- [Infrastructure Team Guide](INFRA_TEAM_GUIDE.md)
- [Admin Setup](ADMIN_SETUP.md)
- [HA Deployment](HA_DEPLOYMENT.md)
