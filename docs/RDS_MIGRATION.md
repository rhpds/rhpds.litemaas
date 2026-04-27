# PostgreSQL Migration: Container → AWS RDS

Migration plan for the LiteLLM PostgreSQL database from a containerized
StatefulSet on OpenShift to an existing AWS RDS instance.

---

## Phase 1 — Current Database Analysis

### Current Environment

| Item               | Value                                                   |
| ------------------ | ------------------------------------------------------- |
| Cluster            | `maas.redhatworkshops.io`                               |
| Namespace          | `litellm-rhpds`                                         |
| Workload           | StatefulSet `litellm-postgres` (1 replica)              |
| Image              | `postgres:16` (Debian)                                  |
| PostgreSQL Version | 16.10                                                   |
| PVC                | `postgres-storage-litellm-postgres-0` — 10 Gi (gp3-csi) |
| Encoding           | UTF-8, Collate `en_US.utf8`                             |
| Extensions         | `plpgsql` 1.0, `pgcrypto` 1.3                           |
| User / Database    | `litellm` / `litellm`                                   |
| Pod uptime         | 152 days                                                |

### Database Size

| Metric                      | Value                 |
| --------------------------- | --------------------- |
| Total database size         | **2906 MB (~2.9 GB)** |
| SQL dump (uncompressed)     | ~4.0 GB               |
| SQL dump (gzip)             | **~212 MB**           |
| `pg_dump` time (inside pod) | **~27 seconds**       |

### Top 10 Tables by Size

| Table                              | Size (incl. indexes) | Rows   |
| ---------------------------------- | -------------------- | ------ |
| `LiteLLM_SpendLogs`                | 2607 MB              | ~1.2 M |
| `LiteLLM_DailyTagSpend`            | 90 MB                | ~198 K |
| `LiteLLM_DailyUserSpend`           | 66 MB                | ~63 K  |
| `LiteLLM_DailyTeamSpend`           | 61 MB                | ~126 K |
| `audit_logs`                       | 52 MB                | ~93 K  |
| `LiteLLM_VerificationToken`        | 11 MB                | ~14 K  |
| `LiteLLM_DeletedVerificationToken` | 1.8 MB               | ~1.3 K |
| `daily_usage_cache`                | 1.4 MB               | ~151   |
| `LiteLLM_DailyEndUserSpend`        | 944 KB               | ~735   |
| `users`                            | 808 KB               | ~815   |

Total tables: **61** (all in `public` schema).

### Schema Highlights

- **1 custom enum**: `JobStatus` (`ACTIVE`, `INACTIVE`)
- **1 custom function**: `update_updated_at_column` (trigger function)
- **8 views**: Standard SQL views for spend reporting (no PG 16 features)
- **All pgcrypto functions**: Standard extension functions

### How LiteLLM Connects to the Database

LiteLLM uses the `DATABASE_URL` environment variable from the Secret
`litemaas-db`. Additionally, individual variables are set:

```
DATABASE_URL = postgresql://litellm:<password>@litellm-postgres:5432/litellm?sslmode=disable
DB_HOST      = litellm-postgres  (hardcoded in Deployment)
DB_PORT      = 5432              (hardcoded in Deployment)
DB_NAME      = litellm           (from secret)
DB_USER      = litellm           (from secret)
DB_PASSWORD  = <password>        (from secret)
```

### PostgreSQL 16 → 15 Compatibility Assessment

The target RDS instance runs **PostgreSQL 15**. The source runs **PostgreSQL 16.10**.
Restoring a PG 16 dump into PG 15 is not officially supported (downgrade),
but after analysis the risk is **low** for this database because:

- **No PG 16-specific features** are used (no `MERGE`, no new JSON functions,
  no identity columns with PG 16 syntax).
- The only custom enum (`JobStatus`) and function (`update_updated_at_column`)
  use syntax available since PG 12+.
- All 8 views use standard SQL that works on PG 15.
- The `pgcrypto` extension is available on both PG 15 and PG 16.
- The `pg_dump --clean --if-exists` output is largely version-agnostic DDL.

**Risk mitigation**: We will test the restore on the RDS instance first
(creating the `litellm` database for testing) before scheduling the
production migration.

### Security Alert

Two suspicious tables were found, created by unauthorized activity:

- **`_exfil`** (10 rows) — contains network scan results (MCS port 22623),
  kubeadmin access attempts, and debug pod errors.
- **`_x`** (1 row) — contains container capabilities dump.

**Recommendation**: Investigate the security incident separately (see
`docs/investigate-suspicious-tables.md`). These tables will be **excluded**
from the migration dump.

---

## Phase 2 — Preparation and Validation

### 2.1 Prerequisites

- `psql` client installed locally (version 15+ or 16)
- `oc` CLI authenticated to the OpenShift cluster
- Network access from the restore machine to the RDS endpoint
- RDS security group updated to allow inbound access on port **54327**

### 2.2 Target RDS Instance

| Parameter           | Value                                                           |
| ------------------- | --------------------------------------------------------------- |
| Engine              | PostgreSQL **15** (existing RDS cluster)                        |
| Endpoint (RW)       | `prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com` |
| Endpoint (RO)       | Available but not needed — LiteLLM does both reads and writes   |
| Port                | **54327**                                                       |
| Region              | `us-east-1`                                                     |
| Database Name       | `litellm` (to be created)                                       |
| Username            | `litellm` (same as current container)                           |
| Password            | *(same as current container — see note below)*                  |
| SSL Mode            | `require`                                                       |
| Required Extensions | `pgcrypto`                                                      |

> **Obtaining the database password**: The password is stored in the
> OpenShift cluster Secret. Retrieve it with:
>
> ```bash
> oc get secret litemaas-db -n litellm-rhpds -o jsonpath='{.data.password}' | base64 -d
> ```

> **Cross-region note**: The OpenShift cluster is in `us-west-2` and the RDS
> is in `us-east-1`. This requires cross-region connectivity (VPC Peering,
> Transit Gateway, or public endpoint with security group). Latency will be
> ~60-70ms per query (cross-region). This is acceptable for LiteLLM since
> database calls are not in the hot path of LLM inference.

### 2.3 Pre-migration: Create Database on RDS (Done)

Connect to the RDS cluster using DBeaver (or any PostgreSQL client) as
the master/admin user, then run these SQL statements **in order**:

**Step 1** — Connect to the `postgres` database and create the user + database:

```sql
-- Create the litellm user with the same password as the current container
-- Obtain the password from the cluster: oc get secret litemaas-db -n litellm-rhpds -o jsonpath='{.data.password}' | base64 -d
CREATE USER litellm WITH PASSWORD '<DB_PASSWORD>';

-- Create the litellm database owned by the litellm user
CREATE DATABASE litellm OWNER litellm;
```

**Step 2** — Connect to the newly created `litellm` database (switch
connection in DBeaver) and run:

```sql
-- Grant full privileges
GRANT ALL PRIVILEGES ON DATABASE litellm TO litellm;

-- Grant schema permissions
GRANT ALL ON SCHEMA public TO litellm;

-- Enable pgcrypto extension (required by LiteLLM)
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

**Step 3** — Verify the setup (still on the `litellm` database):

```sql
-- Verify user exists
SELECT usename, usecreatedb, usesuper FROM pg_user WHERE usename = 'litellm';

-- Verify pgcrypto is enabled
SELECT extname, extversion FROM pg_extension WHERE extname = 'pgcrypto';

-- Test that litellm user can connect and create tables
-- (run this as the litellm user in a separate DBeaver connection)
CREATE TABLE _migration_test (id serial PRIMARY KEY, created_at timestamp DEFAULT now());
INSERT INTO _migration_test DEFAULT VALUES;
SELECT * FROM _migration_test;
DROP TABLE _migration_test;
```

### 2.4 Validate Connectivity from Cluster (Done)

After creating the database, test that the OpenShift cluster can reach the RDS:

```bash
export KUBECONFIG=~/secrets/maas.redhatworkshop.io.kubeconfig

# Test connectivity from inside the cluster using a temporary pod
oc run pg-connectivity-test --rm -it --restart=Never \
  --image=postgres:15 -n litellm-rhpds -- \
  pg_isready -h prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com \
  -p 54327 -U litellm -d litellm -t 10
```

- If it returns **`accepting connections`** — connectivity is OK.
- If it **times out** — the RDS security group needs an inbound rule:
  - Protocol: TCP
  - Port: 54327
  - Source: cluster VPC CIDR or the peered VPC CIDR

### 2.5 Test Dump/Restore Results (Done — 2026-04-27)

> **Important**: Use `pg_dump` version 16 — version 15 refuses to connect
> to a PG 16 server. On macOS: `brew install postgresql@16`, then use
> `/opt/homebrew/opt/postgresql@16/bin/pg_dump`.
>
> **Recommended method**: Use `oc port-forward` and run `pg_dump` locally
> instead of `oc exec` inside the pod, to avoid impacting the running
> PostgreSQL container's memory/CPU.

| Step                               | Estimated | Actual (test) |
| ---------------------------------- | --------- | ------------- |
| `pg_dump` (local via port-forward) | ~30 sec   | **210 sec**   |
| Dump size (gzip)                   | ~212 MB   | **224 MB**    |
| `psql` restore on RDS (PG 15)      | ~3-5 min  | **128 sec**   |
| Validation                         | ~1 min    | ~1 min        |
| **Total dump/restore**             | ~5-7 min  | **~6 min**    |

**Restore errors** (all harmless):

- `must be owner of extension pgcrypto` — dump tries to drop/recreate
  the extension, but only the RDS admin can. Extension was already created
  manually — no impact.
- `\restrict` / `\unrestrict` — PG 16 psql metacommands not recognized
  by psql 15. Cosmetic, no data impact.

**Validation results on RDS**:

- Tables: **59** (61 original - 2 excluded: `_exfil`, `_x`)
- Database size: **3302 MB**
- SpendLogs rows: **1,209,981**
- pgcrypto extension: present (v1.3)
- All key tables verified (users, models, teams, tokens, audit_logs)

---

## Phase 3 — Configuration Changes

### 3.1 What Needs to Change

To migrate to RDS, only the Secret `litemaas-db` and the `DB_HOST`/`DB_PORT`
environment variables in the Deployment need to be updated. LiteLLM already
uses environment variables for the connection.

#### Cluster Resources to Update

| Resource   | Name          | Namespace       | Change                                  |
| ---------- | ------------- | --------------- | --------------------------------------- |
| Secret     | `litemaas-db` | `litellm-rhpds` | Update `DATABASE_URL`, `password`       |
| Deployment | `litellm`     | `litellm-rhpds` | Update `DB_HOST` and `DB_PORT` env vars |

#### Current vs New Values

```yaml
# CURRENT (Secret litemaas-db)
DATABASE_URL: "postgresql://litellm:<DB_PASSWORD>@litellm-postgres:5432/litellm?sslmode=disable"

# NEW (after RDS migration)
DATABASE_URL: "postgresql://litellm:<DB_PASSWORD>@prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com:54327/litellm?sslmode=require"
```

```yaml
# CURRENT (Deployment litellm env vars — hardcoded)
DB_HOST: "litellm-postgres"
DB_PORT: "5432"

# NEW
DB_HOST: "prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com"
DB_PORT: "54327"
```

> **Note**: `sslmode` changes from `disable` to `require` for RDS.
> Username and password remain the same.

### 3.2 Repository Changes (for PR)

To support external databases in future deployments, the following
changes are needed in the Ansible role:

#### 3.2.1 File: `roles/ocp4_workload_litemaas/defaults/ha.yml`

Add variables for external database support:

```yaml
# External database configuration (e.g., AWS RDS)
# When enabled, skips PostgreSQL StatefulSet deployment
ocp4_workload_litemaas_external_db_enabled: false
ocp4_workload_litemaas_external_db_host: ""
ocp4_workload_litemaas_external_db_port: "5432"
ocp4_workload_litemaas_external_db_name: "litellm"
ocp4_workload_litemaas_external_db_user: "litellm"
ocp4_workload_litemaas_external_db_password: ""
ocp4_workload_litemaas_external_db_sslmode: "require"
```

#### 3.2.2 File: `roles/ocp4_workload_litemaas/tasks/workload_litemaas_ha.yml`

Condition the PostgreSQL StatefulSet deployment:

```yaml
- name: Deploy PostgreSQL 16 database
  when:
    - ocp4_workload_litemaas_ha_enable_postgres | bool
    - not (ocp4_workload_litemaas_external_db_enabled | default(false) | bool)
  block:
    # ... (existing block unchanged)
```

Add block for external database Secret:

```yaml
- name: Configure external database connection
  when: ocp4_workload_litemaas_external_db_enabled | default(false) | bool
  block:
    - name: Create database secret for external DB
      kubernetes.core.k8s:
        state: present
        namespace: "{{ _litemaas_ha_namespace }}"
        definition:
          apiVersion: v1
          kind: Secret
          metadata:
            name: litemaas-db
            labels:
              app: litellm-postgres
              component: database
          type: Opaque
          stringData:
            username: "{{ ocp4_workload_litemaas_external_db_user }}"
            password: "{{ ocp4_workload_litemaas_external_db_password }}"
            database: "{{ ocp4_workload_litemaas_external_db_name }}"
            DATABASE_URL: "postgresql://{{ ocp4_workload_litemaas_external_db_user }}:{{ ocp4_workload_litemaas_external_db_password }}@{{ ocp4_workload_litemaas_external_db_host }}:{{ ocp4_workload_litemaas_external_db_port }}/{{ ocp4_workload_litemaas_external_db_name }}?sslmode={{ ocp4_workload_litemaas_external_db_sslmode }}"
```

#### 3.2.3 File: `roles/ocp4_workload_litemaas/templates/litemaas-ha-deployment.yml.j2`

Parameterize `DB_HOST` and `DB_PORT`:

```yaml
# Change from:
- name: DB_HOST
  value: "litellm-postgres"
- name: DB_PORT
  value: "5432"
# To:
- name: DB_HOST
  value: "{{ ocp4_workload_litemaas_external_db_host | default('litellm-postgres') }}"
- name: DB_PORT
  value: "{{ ocp4_workload_litemaas_external_db_port | default('5432') }}"
```

Condition init containers (no need to wait for internal PostgreSQL when using RDS):

```yaml
      initContainers:
{% if not (ocp4_workload_litemaas_external_db_enabled | default(false) | bool) %}
        - name: wait-for-postgres
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              until nc -z litellm-postgres 5432; do
                echo "Waiting for PostgreSQL..."
                sleep 2
              done
              echo "PostgreSQL is ready"
{% endif %}
        - name: wait-for-redis
          # ... (unchanged)
```

### 3.3 Usage After Changes

```bash
# Deploy with external RDS
./deploy-litemaas.sh litellm-rhpds \
  -e ocp4_workload_litemaas_external_db_enabled=true \
  -e ocp4_workload_litemaas_external_db_host=prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com \
  -e ocp4_workload_litemaas_external_db_port=54327 \
  -e ocp4_workload_litemaas_external_db_password='<DB_PASSWORD>'
```

### 3.4 Files to Change in PR

| File                                                                   | Change                                                      |
| ---------------------------------------------------------------------- | ----------------------------------------------------------- |
| `roles/ocp4_workload_litemaas/defaults/ha.yml`                         | Add `external_db_*` variables                               |
| `roles/ocp4_workload_litemaas/tasks/workload_litemaas_ha.yml`          | Condition PG deploy, add external DB block                  |
| `roles/ocp4_workload_litemaas/templates/litemaas-ha-deployment.yml.j2` | Parameterize `DB_HOST`/`DB_PORT`, condition init containers |

---

## Phase 4 — Migration Runbook

### 4.1 Prerequisites (do in advance)

- [x] Create `litellm` user and database on the existing RDS instance
- [x] Enable `pgcrypto` extension on the `litellm` database
- [x] Update RDS security group — prefix list `maas-us-west-2` added to SG
- [x] Validate network connectivity from cluster to RDS on port 54327
- [x] Run a test dump/restore to validate PG 16 → PG 15 compatibility (see results below)
- [ ] Communicate maintenance window to users

### 4.2 Security Group Configuration (Done)

The RDS uses a public endpoint. The cluster egress traffic goes through
3 NAT Gateways (one per AZ). The NAT IPs must be allowed in the RDS
security group.

**RDS Security Group**: [`sg-0ca7baf8992e2d828`](https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#SecurityGroup:groupId=sg-0ca7baf8992e2d828)

**Cluster NAT Gateway IPs** (maas.redhatworkshops.io, us-west-2):

| NAT IP              | Cluster AZ / Nodes                                            |
| ------------------- | ------------------------------------------------------------- |
| `52.89.174.89/32`   | 10.0.4.x, 10.0.8.x, 10.0.9.x, 10.0.10.x, 10.0.12.x, 10.0.26.x |
| `54.69.12.187/32`   | 10.0.38.x — 10.0.46.x, 10.0.62.x                              |
| `44.253.146.107/32` | 10.0.66.x — 10.0.73.x (litellm-postgres node)                 |

**Existing prefix list** `ocp-us-west-2` (`pl-0e5bc0043279f11b5`) contains
IPs from a different cluster — do NOT add our IPs there.

**Done**: Created prefix list **`maas-us-west-2`** in us-east-1
([VPC → Managed prefix lists](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#ManagedPrefixLists:))
with the 3 NAT IPs above and added it as an inbound rule in the SG on
port 54327. Connectivity verified on 2026-04-27.

#### Test Connectivity

After updating the SG, test from within the cluster:

```bash
export KUBECONFIG=~/secrets/maas.redhatworkshop.io.kubeconfig
oc run pg-connectivity-test --rm -i --restart=Never \
  --image=postgres:15 -n litellm-rhpds -- \
  pg_isready -h prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com \
  -p 54327 -U litellm -d litellm -t 10
```

### 4.3 Migration Timeline

Based on actual test results (2026-04-27). Dump via port-forward is slower
than `oc exec` but avoids impacting the PostgreSQL pod's memory/CPU.

| Step                                                | Tested   | Cumulative      |
| --------------------------------------------------- | -------- | --------------- |
| 1. Communicate maintenance start                    | —        | T+0             |
| 2. Scale down LiteLLM (0 replicas)                  | ~30 sec  | T+1 min         |
| 3. Port-forward + pg_dump (local, pg_dump 16)       | ~4 min   | T+5 min         |
| 4. Restore dump to RDS (psql, cross-region)         | ~2.5 min | T+7.5 min       |
| 5. Validate data on RDS (table/row counts)          | ~1 min   | T+8.5 min       |
| 6. Update Secret `litemaas-db` on cluster           | ~30 sec  | T+9 min         |
| 7. Update Deployment `litellm` (DB_HOST, DB_PORT)   | ~30 sec  | T+9.5 min       |
| 8. Scale up LiteLLM (3 replicas)                    | ~2 min   | T+11.5 min      |
| 9. Validate LiteLLM health checks and functionality | ~3 min   | T+14.5 min      |
| 10. Communicate maintenance end                     | —        | T+15 min        |
| **Estimated total downtime**                        |          | **~15 minutes** |

> Note: during the test, dump took 210s and restore 128s. During the actual
> migration LiteLLM will be scaled down (no concurrent writes), so dump
> should be slightly faster.

### 4.4 Detailed Procedure

#### Step 1 — Pre-migration Test (before the window)

```bash
export KUBECONFIG=~/secrets/maas.redhatworkshop.io.kubeconfig
oc project litellm-rhpds

# Test RDS connectivity from inside the cluster
oc run pg-test --rm -it --restart=Never \
  --image=postgres:15 -n litellm-rhpds -- \
  pg_isready -h prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com \
  -p 54327 -U litellm -d litellm
```

#### Step 2 — Start Downtime

```bash
# Scale LiteLLM to 0 replicas
oc scale deployment litellm -n litellm-rhpds --replicas=0

# Confirm no active connections
oc exec litellm-postgres-0 -n litellm-rhpds -- \
  psql -U litellm -d litellm \
  -c "SELECT count(*) FROM pg_stat_activity WHERE datname='litellm' AND state='active';"
```

#### Step 3 — Dump (via port-forward)

```bash
# Start port-forward in background
oc port-forward statefulset/litellm-postgres 15432:5432 -n litellm-rhpds &
PF_PID=$!
sleep 3

# Run pg_dump locally (requires pg_dump 16)
# macOS: /opt/homebrew/opt/postgresql@16/bin/pg_dump
# Get password: oc get secret litemaas-db -n litellm-rhpds -o jsonpath='{.data.password}' | base64 -d
PGPASSWORD='<DB_PASSWORD>' \
  /opt/homebrew/opt/postgresql@16/bin/pg_dump \
  -h 127.0.0.1 -p 15432 -U litellm -d litellm \
  --clean --if-exists \
  --exclude-table='_exfil' --exclude-table='_x' \
  | gzip > litellm-migration-$(date +%Y%m%d-%H%M%S).sql.gz

# Stop port-forward
kill $PF_PID
```

#### Step 4 — Restore to RDS

```bash
export RDS_ENDPOINT="prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com"
# Get password: oc get secret litemaas-db -n litellm-rhpds -o jsonpath='{.data.password}' | base64 -d
export RDS_PASSWORD="<DB_PASSWORD>"

# Restore
gunzip -c litellm-migration-*.sql.gz | \
  PGPASSWORD="$RDS_PASSWORD" psql -h "$RDS_ENDPOINT" -p 54327 \
    -U litellm -d litellm \
    --single-transaction
```

#### Step 5 — Validate Data on RDS

```bash
export RDS_ENDPOINT="prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com"
export RDS_PASSWORD="<DB_PASSWORD>"  # see Section 2.2 for how to obtain

# Count tables (expected: 59 = 61 original - 2 excluded)
PGPASSWORD="$RDS_PASSWORD" psql -h "$RDS_ENDPOINT" -p 54327 \
  -U litellm -d litellm \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"

# Check database size
PGPASSWORD="$RDS_PASSWORD" psql -h "$RDS_ENDPOINT" -p 54327 \
  -U litellm -d litellm \
  -c "SELECT pg_size_pretty(pg_database_size('litellm'));"

# Verify main table
PGPASSWORD="$RDS_PASSWORD" psql -h "$RDS_ENDPOINT" -p 54327 \
  -U litellm -d litellm \
  -c "SELECT count(*) FROM \"LiteLLM_SpendLogs\";"
# Expected: ~1.2M rows
```

#### Step 6 — Update Cluster Configuration

```bash
# Update Secret litemaas-db (only DATABASE_URL changes — same password)
oc patch secret litemaas-db -n litellm-rhpds -p '{
  "stringData": {
    "DATABASE_URL": "postgresql://litellm:<DB_PASSWORD>@prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com:54327/litellm?sslmode=require"
  }
}'

# Update DB_HOST and DB_PORT in the Deployment
oc set env deployment/litellm -n litellm-rhpds \
  DB_HOST=prod-cluster.cluster-cxlxqnxl63vv.us-east-1.rds.amazonaws.com \
  DB_PORT=54327
```

#### Step 7 — Restore Service

```bash
# Scale LiteLLM back up
oc scale deployment litellm -n litellm-rhpds --replicas=3

# Monitor rollout
oc rollout status deployment/litellm -n litellm-rhpds --timeout=120s

# Check pods
oc get pods -n litellm-rhpds -l app=litellm
```

#### Step 8 — Functional Validation

```bash
# Check LiteLLM readiness
LITELLM_ROUTE=$(oc get route litellm -n litellm-rhpds -o jsonpath='{.spec.host}')
curl -s "https://${LITELLM_ROUTE}/health/readiness" | jq .

# Verify models are available
curl -s "https://${LITELLM_ROUTE}/v1/models" \
  -H "Authorization: Bearer <MASTER_KEY>" | jq '.data | length'
```

### 4.5 Rollback Plan

If the migration fails at any step after the restore:

```bash
# Revert Secret to point to internal PostgreSQL
oc patch secret litemaas-db -n litellm-rhpds -p '{
  "stringData": {
    "DATABASE_URL": "postgresql://litellm:<DB_PASSWORD>@litellm-postgres:5432/litellm?sslmode=disable"
  }
}'

# Revert DB_HOST and DB_PORT
oc set env deployment/litellm -n litellm-rhpds \
  DB_HOST=litellm-postgres \
  DB_PORT=5432

# Scale LiteLLM back up
oc scale deployment litellm -n litellm-rhpds --replicas=3
```

> The internal PostgreSQL StatefulSet will remain running throughout the
> migration. **Do not** scale it down or delete it until the migration is
> validated and stable for at least 24-48 hours.

### 4.6 Post-migration (after 24-48h of stability)

- [x] Update backup script (`setup-litemaas-backup-cronjob.sh`) — now
      auto-detects internal vs external DB, skips VolumeSnapshot for RDS
- [ ] Scale StatefulSet `litellm-postgres` to 0 replicas
- [ ] Delete the old PostgreSQL PVC (after confirming stability)
- [ ] Update DR documentation (`docs/BACKUP.md`)
- [x] Create PR with Phase 3 repository changes
- [ ] Verify `_exfil` and `_x` tables were NOT migrated to RDS

### 4.7 Best Time for Migration

Estimated downtime is ~15 minutes. Recommended:

- **Day**: Weekday (support availability)
- **Time**: Early morning (ET) or late afternoon (PT) — lowest usage
- **Advance notice**: 24h before via relevant channels

---

## Additional Notes

### Connectivity: Cluster → RDS

The OpenShift cluster runs on AWS **us-west-2** (based on node hostnames)
and the RDS cluster is in **us-east-1**. This is a **cross-region** setup
that requires one of:

- **VPC Peering** (cross-region) between the two VPCs
- **Transit Gateway** with cross-region attachments
- **RDS public endpoint** with security group restricting to cluster egress IPs

Expected cross-region latency: **~60-70ms**. This is acceptable for LiteLLM
since database queries are not in the hot path of LLM inference requests.

### SSL/TLS

RDS PostgreSQL uses SSL by default. LiteLLM supports `sslmode=require` in
the `DATABASE_URL`. No client certificate is needed — only the RDS CA bundle
(already included in most distributions).

### Estimated RDS Cost (incremental)

Since the RDS instance already exists, the incremental cost is only the
additional storage:

| Item           | Estimated Cost |
| -------------- | -------------- |
| Storage ~5 GB  | ~$1-2/month    |
| Backup storage | Included       |

### Optional: Clean Up SpendLogs Before Migration

The `LiteLLM_SpendLogs` table is **90% of the database** (2.6 GB, 1.2M rows).
If older historical data is not needed, cleaning it before migration would
significantly reduce dump/restore time:

```sql
-- Example: remove logs older than 90 days
DELETE FROM "LiteLLM_SpendLogs" WHERE "startTime" < NOW() - INTERVAL '90 days';
VACUUM FULL "LiteLLM_SpendLogs";
```

This could reduce the dump from ~4 GB to hundreds of MB and the total
migration time to under 5 minutes.
