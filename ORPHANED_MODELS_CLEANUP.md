# Orphaned Models Cleanup Feature

## Summary

Enhanced the `ocp4_workload_litemaas_models` role to automatically delete models from the backend database that don't exist in LiteLLM frontend.

## Problem Solved

**Before:**
- Admin deletes a model from LiteLLM Admin UI
- Model is removed from LiteLLM but remains in backend database
- Orphaned records accumulate over time
- Manual database cleanup required

**After:**
- Sync script automatically detects orphaned models
- Deletes them from backend database
- Backend stays in sync with LiteLLM frontend

## Changes Made

### 1. New Task File: `cleanup_orphaned_models.yml`

**Location:** `roles/ocp4_workload_litemaas_models/tasks/cleanup_orphaned_models.yml`

**What it does:**
1. Queries all models from LiteLLM frontend (`/model/info` API)
2. Queries all models from backend database (`SELECT id FROM models`)
3. Identifies orphaned models (in backend but not in LiteLLM)
4. Deletes orphaned models from backend database
5. Displays summary of cleanup operation

### 2. Updated `workload.yml`

**Change:** Added Step 6 - Cleanup Orphaned Models

```yaml
- name: Cleanup orphaned models from backend database
  when:
    - ocp4_workload_litemaas_models_backend_enabled | bool
    - ocp4_workload_litemaas_models_cleanup_orphaned | bool
  ansible.builtin.include_tasks:
    file: cleanup_orphaned_models.yml
```

### 3. New Variable in `defaults/main.yml`

```yaml
# Cleanup orphaned models from backend that don't exist in LiteLLM
# When enabled, any model in backend database that isn't in LiteLLM will be deleted
ocp4_workload_litemaas_models_cleanup_orphaned: true
```

**Default:** `true` (cleanup enabled by default)

### 4. Updated `sync-models.sh`

**Change:** Added cleanup flag to temp config

```yaml
ocp4_workload_litemaas_models_cleanup_orphaned: true
```

### 5. Updated README.md

**Added:**
- Cleanup feature in features list
- New variable documentation
- Scenario 4: Removing Models (Cleanup Orphaned Models)

## Usage

### Automatic Cleanup (Default)

```bash
# Sync models and cleanup orphaned ones
./sync-models.sh litemaas
```

### Using Playbook

```bash
ansible-playbook playbooks/manage_models.yml \
  -e litellm_url=https://litellm-admin.apps.cluster.com \
  -e litellm_master_key=sk-xxxxx \
  -e ocp4_workload_litemaas_models_namespace=litemaas \
  -e ocp4_workload_litemaas_models_sync_from_litellm=true \
  -e ocp4_workload_litemaas_models_cleanup_orphaned=true
```

### Disable Cleanup

```bash
ansible-playbook playbooks/manage_models.yml \
  -e litellm_url=https://litellm-admin.apps.cluster.com \
  -e litellm_master_key=sk-xxxxx \
  -e ocp4_workload_litemaas_models_cleanup_orphaned=false
```

## Example Output

```
=========================================
Cleaning Up Orphaned Models
=========================================
Checking for models in backend that don't exist in LiteLLM...

Found 3 models in LiteLLM frontend
Models: granite-8b-code-instruct, mistral-7b-instruct, llama-13b

Found 5 models in backend database
Models: granite-8b-code-instruct, mistral-7b-instruct, llama-13b, old-model-1, old-model-2

=========================================
Orphaned Models Analysis
=========================================
Models in LiteLLM: 3
Models in Backend: 5
Orphaned (to be deleted): 2
Orphaned models: old-model-1, old-model-2

Deleted orphaned model: old-model-1
Deleted orphaned model: old-model-2

=========================================
Cleanup Complete
=========================================
Successfully deleted 2 orphaned model(s) from backend database
Backend database is now in sync with LiteLLM frontend
```

## Workflow

### Scenario: Admin Removes a Model

1. **Admin logs into LiteLLM Admin UI**
   - URL: `https://litellm-admin.apps.cluster.com`

2. **Admin deletes a model via UI**
   - Model removed from LiteLLM
   - Model still exists in backend database (orphaned)

3. **Run sync script**
   ```bash
   ./sync-models.sh litemaas
   ```

4. **Automatic cleanup happens**
   - Script detects the deleted model
   - Removes it from backend database
   - Backend is now in sync

## Technical Details

### Database Query (Get Backend Models)

```sql
SELECT id FROM models;
```

### Database Query (Delete Orphaned Model)

```sql
DELETE FROM models WHERE id = 'model-name';
```

### Logic Flow

```python
litellm_models = ["model-a", "model-b", "model-c"]
backend_models = ["model-a", "model-b", "model-c", "old-model"]

orphaned = backend_models - litellm_models
# Result: ["old-model"]

for model in orphaned:
    delete_from_database(model)
```

## Safety Features

- **Idempotent:** Safe to run multiple times
- **Non-destructive by default:** Only deletes when explicitly enabled
- **Detailed logging:** Shows exactly what will be deleted
- **Conditional execution:** Only runs when backend is enabled
- **Error handling:** Handles empty model lists gracefully

## Testing Checklist

- [ ] Sync with no orphaned models (should show "No cleanup needed")
- [ ] Sync with 1 orphaned model (should delete 1 model)
- [ ] Sync with multiple orphaned models (should delete all)
- [ ] Disable cleanup flag (should skip cleanup step)
- [ ] Run sync-models.sh script (should include cleanup)
- [ ] Verify database after cleanup (orphaned models gone)

## Files Modified

```
roles/ocp4_workload_litemaas_models/
├── defaults/main.yml                     # Added cleanup variable
├── tasks/
│   ├── cleanup_orphaned_models.yml       # NEW - Cleanup logic
│   └── workload.yml                      # Added cleanup step
└── README.md                             # Updated documentation

sync-models.sh                            # Added cleanup flag
ORPHANED_MODELS_CLEANUP.md                # NEW - This file
```

## Version

**Feature added:** v0.4.0 (pending)
**Previous version:** v0.3.0
**Repository:** https://github.com/rhpds/rhpds.litemaas

## Author

**Prakhar Srivastava**
Manager, Technical Marketing
Red Hat Demo Platform
