# Infrastructure Team Guide - Managing Models in LiteMaaS

Quick reference guide for infrastructure teams to manage AI models after LiteMaaS deployment.

## Prerequisites

- LiteMaaS deployed and running
- `oc` CLI access to the cluster
- Ansible installed with `rhpds.litemaas` collection

## Quick Start: Sync Models After Adding via UI

### Step 1: Get Required Information

```bash
# Get LiteLLM URL
LITELLM_URL=$(oc get route litemaas -n litemaas -o jsonpath='https://{.spec.host}')
echo "LiteLLM URL: $LITELLM_URL"

# Get LiteLLM Master Key
LITELLM_KEY=$(oc get secret litellm-secret -n litemaas -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
echo "Master Key: $LITELLM_KEY"
```

### Step 2: Add Model via LiteLLM Admin UI

1. Open browser: `https://litellm-admin.apps.<your-cluster>.com`
2. Login with admin credentials
3. Click "Models" → "Add Model"
4. Fill in model details:
   - **Model Name**: `granite-8b-code-instruct-128k`
   - **LiteLLM Model**: `openai/granite-3-2-8b-instruct`
   - **API Base**: `https://granite-model.apps.<cluster>.com/v1`
   - **API Key**: `sk-xxxxx` (from OpenShift AI)
5. Click "Add"

### Step 3: Sync to Backend Database

```bash
# Navigate to the collection directory
cd /path/to/rhpds.litemaas

# Create a sync configuration file
cat > sync-models.yml <<EOF
litellm_url: "$LITELLM_URL"
litellm_master_key: "$LITELLM_KEY"
ocp4_workload_litemaas_models_namespace: "litemaas"
ocp4_workload_litemaas_models_backend_enabled: true
ocp4_workload_litemaas_models_sync_from_litellm: true
ocp4_workload_litemaas_models_list: []
EOF

# Run the sync playbook
ansible-playbook playbooks/manage_models.yml -e @sync-models.yml
```

### Step 4: Verify Sync

```bash
# Check models in LiteLLM
curl -X GET "${LITELLM_URL}/model/info" \
  -H "Authorization: Bearer ${LITELLM_KEY}" | jq '.data[].model_name'

# Check models in backend database
oc exec -n litemaas litemaas-postgres-0 -- \
  psql -U litemaas -d litemaas -c "SELECT id, name, provider FROM models;"
```

## Common Scenarios

### Scenario 1: Add Single Model via Playbook

```bash
# Create model configuration
cat > my-model.yml <<EOF
litellm_url: "https://litellm-admin.apps.<cluster>.com"
litellm_master_key: "sk-xxxxx"
ocp4_workload_litemaas_models_namespace: "litemaas"
ocp4_workload_litemaas_models_backend_enabled: true
ocp4_workload_litemaas_models_list:
  - model_name: "granite-8b-code-instruct-128k"
    litellm_model: "openai/granite-3-2-8b-instruct"
    api_base: "https://granite-model.apps.<cluster>.com/v1"
    api_key: "sk-yyyyy"
    display_name: "Granite 8B Code Instruct"
    description: "IBM Granite 8B Code Instruct model"
    provider: "openshift-ai"
    category: "code"
    context_length: 131072
    rpm: 120
    tpm: 100000
EOF

# Run playbook
ansible-playbook playbooks/manage_models.yml -e @my-model.yml
```

### Scenario 2: Add Multiple Models at Once

```bash
# Copy example and edit
cp examples/models.yml production-models.yml
vi production-models.yml

# Run playbook
ansible-playbook playbooks/manage_models.yml -e @production-models.yml
```

### Scenario 3: Sync Only (After Adding via UI)

```bash
ansible-playbook playbooks/manage_models.yml \
  -e litellm_url=https://litellm-admin.apps.<cluster>.com \
  -e litellm_master_key=sk-xxxxx \
  -e ocp4_workload_litemaas_models_namespace=litemaas \
  -e ocp4_workload_litemaas_models_list=[] \
  -e ocp4_workload_litemaas_models_sync_from_litellm=true
```

## Getting Model Information from OpenShift AI

### Find Model Endpoint

```bash
# List all routes in OpenShift AI namespace
oc get routes -n rhods-notebooks

# Get specific model route
oc get route <model-name> -n rhods-notebooks -o jsonpath='{.spec.host}'
```

### Model Configuration Examples

#### Granite Code Model
```yaml
- model_name: "granite-8b-code-instruct-128k"
  litellm_model: "openai/granite-3-2-8b-instruct"
  api_base: "https://granite-model.apps.cluster.com/v1"
  api_key: "sk-xxxxx"
  display_name: "Granite 8B Code Instruct"
  provider: "openshift-ai"
  category: "code"
  context_length: 131072
```

#### Mistral Model
```yaml
- model_name: "mistral-7b-instruct"
  litellm_model: "openai/mistral-7b-instruct-v0.2"
  api_base: "https://mistral-model.apps.cluster.com/v1"
  api_key: "sk-yyyyy"
  display_name: "Mistral 7B Instruct"
  provider: "openshift-ai"
  category: "general"
  context_length: 32768
```

#### LLaMA Model
```yaml
- model_name: "llama-3-8b-instruct"
  litellm_model: "openai/llama-3-8b-instruct"
  api_base: "https://llama-model.apps.cluster.com/v1"
  api_key: "sk-zzzzz"
  display_name: "LLaMA 3 8B Instruct"
  provider: "openshift-ai"
  category: "general"
  context_length: 8192
```

## Troubleshooting

### Error: "Foreign key constraint violation"

**Problem:** Model exists in LiteLLM but not in backend database

**Solution:**
```bash
# Run sync to add models to backend database
ansible-playbook playbooks/manage_models.yml \
  -e litellm_url=https://litellm-admin.apps.<cluster>.com \
  -e litellm_master_key=sk-xxxxx \
  -e ocp4_workload_litemaas_models_list=[] \
  -e ocp4_workload_litemaas_models_sync_from_litellm=true
```

### Verify Model in Both Locations

```bash
# Check LiteLLM
curl -X GET "https://litellm-admin.apps.<cluster>.com/model/info" \
  -H "Authorization: Bearer sk-xxxxx" | jq '.data[] | select(.model_name == "granite-8b-code-instruct-128k")'

# Check backend database
oc exec -n litemaas litemaas-postgres-0 -- \
  psql -U litemaas -d litemaas -c "SELECT * FROM models WHERE id = 'granite-8b-code-instruct-128k';"
```

### User Cannot Create Subscription

**Symptoms:**
- User can login via OAuth
- User can see models listed
- User gets error when clicking "Subscribe"
- Backend logs show: `foreign key constraint "subscriptions_model_id_fkey"`

**Root Cause:** Model not in backend database

**Fix:** Run sync playbook (see above)

## Model Parameters Reference

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `model_name` | Unique model identifier | `granite-8b-code-instruct-128k` |
| `litellm_model` | LiteLLM model format | `openai/granite-3-2-8b-instruct` |
| `api_base` | Model endpoint URL | `https://model.apps.cluster.com/v1` |
| `api_key` | Model authentication key | `sk-xxxxx` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `display_name` | `model_name` | Human-readable name |
| `description` | `"AI model"` | Model description |
| `provider` | `openshift-ai` | Provider name |
| `category` | `general` | Model category (code, chat, general) |
| `context_length` | `null` | Context window size |
| `supports_streaming` | `true` | Enable streaming responses |
| `availability` | `available` | Model availability status |
| `rpm` | `null` | Requests per minute limit |
| `tpm` | `null` | Tokens per minute limit |

## Best Practices

1. **Always sync after UI changes**
   - After adding models via LiteLLM Admin UI, run sync playbook
   - This ensures users can create subscriptions

2. **Use descriptive model names**
   - Good: `granite-8b-code-instruct-128k`
   - Bad: `model1`, `test`

3. **Set rate limits**
   - Set `rpm` and `tpm` to prevent abuse
   - Example: `rpm: 120`, `tpm: 100000`

4. **Document model details**
   - Keep model configurations in version control
   - Include provider, category, and description

5. **Test before announcing**
   - Verify model works in LiteLLM
   - Verify model is in backend database
   - Test user subscription flow

## Quick Reference Commands

```bash
# Get deployment info
oc get all -n litemaas

# Get LiteLLM credentials
oc get secret litellm-secret -n litemaas -o yaml

# Check backend logs
oc logs -n litemaas deployment/litemaas-backend --tail=100

# Check LiteLLM logs
oc logs -n litemaas deployment/litellm --tail=100

# Check database
oc exec -n litemaas litemaas-postgres-0 -- psql -U litemaas -d litemaas -c "SELECT id, name FROM models;"

# Restart backend (if needed)
oc rollout restart deployment/litemaas-backend -n litemaas
```

## Support

For issues or questions:
- Check logs: `oc logs -n litemaas deployment/litemaas-backend`
- Review documentation: [roles/ocp4_workload_litemaas_models/README.md](../roles/ocp4_workload_litemaas_models/README.md)
- Contact: Prakhar Srivastava (Red Hat Demo Platform team)
