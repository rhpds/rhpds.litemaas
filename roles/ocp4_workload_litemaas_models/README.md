# LiteMaaS Models Management Role

Ansible role to manage AI models in LiteMaaS - adds models to LiteLLM and syncs them to the backend database.

## Purpose

This role solves the model synchronization issue where:
1. Infrastructure team adds models via LiteLLM Admin UI
2. Models need to be synced to backend database for users to create subscriptions
3. Manual database inserts are error-prone and not scalable

## Features

- ✅ Add models to LiteLLM via API
- ✅ Sync models to backend PostgreSQL database
- ✅ Sync all existing LiteLLM models to backend
- ✅ **Cleanup orphaned models** - automatically delete models from backend that don't exist in LiteLLM
- ✅ Idempotent - safe to run multiple times
- ✅ Can be used standalone or integrated into deployment

## Usage

### 1. Standalone Playbook (Recommended for Infra Team)

```bash
# Copy and customize the example
cp examples/models.yml my-models.yml

# Edit with your models
vi my-models.yml

# Run the playbook
ansible-playbook playbooks/manage_models.yml -e @my-models.yml
```

### 2. Sync Existing LiteLLM Models

After adding models via LiteLLM Admin UI, sync them to backend:

```bash
ansible-playbook playbooks/manage_models.yml \
  -e litellm_url=https://litellm-admin.apps.cluster.com \
  -e litellm_master_key=sk-xxxxx \
  -e ocp4_workload_litemaas_models_namespace=litemaas \
  -e ocp4_workload_litemaas_models_list=[] \
  -e ocp4_workload_litemaas_models_sync_from_litellm=true
```

### 3. Add Single Model

```bash
ansible-playbook playbooks/manage_models.yml \
  -e litellm_url=https://litellm-admin.apps.cluster.com \
  -e litellm_master_key=sk-xxxxx \
  -e '{"ocp4_workload_litemaas_models_list":[{
    "model_name":"granite-8b-code-instruct-128k",
    "litellm_model":"openai/granite-3-2-8b-instruct",
    "api_base":"https://granite.apps.cluster.com/v1",
    "api_key":"sk-yyy",
    "display_name":"Granite 8B Code Instruct",
    "description":"IBM Granite Code model",
    "provider":"openshift-ai",
    "category":"code",
    "context_length":131072,
    "rpm":120,
    "tpm":100000
  }]}'
```

### 4. Integrated with LiteMaaS Deployment

Models are automatically configured during deployment:

```yaml
# catalog_item.yml or extra vars
ocp4_workload_litemaas_litellm_models:
  - model_name: "granite-8b-code-instruct-128k"
    litellm_model: "openai/granite-3-2-8b-instruct"
    api_base: "https://granite-model.apps.cluster.com/v1"
    api_key: "sk-xxxxx"
    display_name: "Granite 8B Code Instruct"
    description: "IBM Granite 8B Code Instruct model"
    provider: "openshift-ai"
    category: "code"
    context_length: 131072
    rpm: 120
    tpm: 100000
```

## Model Parameters

### Required

- `model_name`: Unique identifier (used as model ID in both LiteLLM and backend)
- `litellm_model`: LiteLLM model identifier (format: `provider/model-name`)
- `api_base`: Model endpoint URL (OpenAI-compatible)
- `api_key`: Authentication key for the model endpoint

### Optional

- `display_name`: Human-readable name (defaults to `model_name`)
- `description`: Model description (defaults to "AI model")
- `provider`: Provider name (defaults to "openshift-ai")
- `category`: Model category - "general", "code", "chat", etc. (defaults to "general")
- `context_length`: Context window size (defaults to null)
- `supports_streaming`: Enable streaming (defaults to true)
- `availability`: Model availability status (defaults to "available")
- `rpm`: Requests per minute limit (defaults to null = unlimited)
- `tpm`: Tokens per minute limit (defaults to null = unlimited)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `litellm_url` | (required) | LiteLLM API URL |
| `litellm_master_key` | (required) | LiteLLM master API key |
| `ocp4_workload_litemaas_models_namespace` | `litemaas` | Namespace where LiteMaaS is deployed |
| `ocp4_workload_litemaas_models_list` | `[]` | List of models to add/sync |
| `ocp4_workload_litemaas_models_backend_enabled` | `true` | Sync to backend database |
| `ocp4_workload_litemaas_models_sync_from_litellm` | `true` | Sync all existing LiteLLM models |
| `ocp4_workload_litemaas_models_cleanup_orphaned` | `true` | Delete orphaned models from backend |
| `ocp4_workload_litemaas_models_verify_ssl` | `false` | Verify SSL certificates |

## Workflow for Infrastructure Team

### Scenario 1: Adding Models via LiteLLM Admin UI

1. Admin logs into LiteLLM Admin UI at `https://litellm-admin.apps.cluster.com`
2. Admin clicks "Add Model" and configures model
3. Model is now in LiteLLM but **not** in backend database
4. Users cannot create subscriptions (foreign key error)
5. **Solution:** Run sync playbook:

```bash
ansible-playbook playbooks/manage_models.yml \
  -e litellm_url=https://litellm-admin.apps.cluster.com \
  -e litellm_master_key=sk-xxxxx \
  -e ocp4_workload_litemaas_models_list=[] \
  -e ocp4_workload_litemaas_models_sync_from_litellm=true
```

### Scenario 2: Pre-configuring Models for Deployment

1. Create `models.yml` with all required models
2. Deploy LiteMaaS with models:

```bash
ansible-playbook playbooks/deploy_litemaas.yml -e @models.yml
```

3. Models are automatically added to both LiteLLM and backend database

### Scenario 3: Adding Models After Deployment

1. Create/update `models.yml` with new models
2. Run model management playbook:

```bash
ansible-playbook playbooks/manage_models.yml -e @models.yml
```

### Scenario 4: Removing Models (Cleanup Orphaned Models)

When you delete a model from LiteLLM Admin UI, it remains in the backend database. The sync script now automatically cleans up these orphaned models.

**Automatic cleanup (default):**
```bash
# Run the sync script - it will automatically remove orphaned models
./sync-models.sh litemaas
```

**What happens:**
1. Gets all models from LiteLLM frontend
2. Gets all models from backend database
3. Identifies models in backend that aren't in LiteLLM (orphaned)
4. Deletes orphaned models from backend database
5. Backend stays in sync with LiteLLM

**Disable cleanup (if you want to keep orphaned models):**
```bash
ansible-playbook playbooks/manage_models.yml \
  -e litellm_url=https://litellm-admin.apps.cluster.com \
  -e litellm_master_key=sk-xxxxx \
  -e ocp4_workload_litemaas_models_cleanup_orphaned=false
```

## Troubleshooting

### Error: "Foreign key constraint violation"

**Problem:** Model exists in LiteLLM but not in backend database

**Solution:** Run sync playbook to add models to backend database

### Error: "Model already exists in LiteLLM"

**Expected behavior** - the role is idempotent and will skip models that already exist

### How to verify models are synced

```bash
# Check LiteLLM models
curl https://litellm-admin.apps.cluster.com/model/info \
  -H "Authorization: Bearer sk-xxxxx"

# Check backend database models
oc exec -n litemaas litemaas-postgres-0 -- \
  psql -U litemaas -d litemaas -c "SELECT id, name, provider FROM models;"
```

## Examples

See `examples/models.yml` for a complete configuration example.

## Author

**Prakhar Srivastava**
Manager, Technical Marketing - Red Hat Demo Platform
Red Hat

## License

MIT
