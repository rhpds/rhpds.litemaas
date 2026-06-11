# OpenShift AI Model Integration

This guide shows how to integrate locally hosted AI models from Red Hat OpenShift AI with LiteMaaS.

## Prerequisites

- Red Hat OpenShift AI (RHOAI) deployed on your cluster
- Model serving enabled in OpenShift AI
- At least one model deployed (e.g., Granite, Llama, Mistral)
- Model inference endpoint accessible

## OpenShift AI Model Serving Overview

OpenShift AI provides model serving through:
- **Single-model serving**: Deploy one model per endpoint
- **Multi-model serving**: Deploy multiple models on one inference server
- **KServe/ModelMesh**: Underlying serving platforms

## Step 1: Deploy a Model in OpenShift AI

### Option A: Using the OpenShift AI Dashboard

1. **Login to OpenShift AI Dashboard**
2. **Navigate to Data Science Projects**
3. **Create or select a project**
4. **Click "Deploy Model"**
5. **Select model:**
   - Granite 3.0 8B Instruct
   - Llama 3.1 8B Instruct
   - Mistral 7B Instruct
   - Or custom model from S3/PVC
6. **Configure inference endpoint:**
   - Model server: vLLM or Caikit+TGIS
   - Replicas: 1-3
   - Resources: GPU/CPU allocation
7. **Deploy and wait for model to be ready**

### Option B: Using CLI

```bash
# Example: Deploy Granite model
oc apply -f - <<EOF
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: granite-8b-instruct
  namespace: rhoai-models
  annotations:
    serving.kserve.io/deploymentMode: ModelMesh
spec:
  predictor:
    model:
      modelFormat:
        name: caikit
      runtime: caikit-tgis-runtime
      storage:
        key: granite-storage
        path: models/granite-8b-instruct
EOF
```

## Step 2: Get Model Inference Endpoint

### Find the Route URL

```bash
# Get inference service route
oc get route -n rhoai-models

# Or get from InferenceService
oc get inferenceservice granite-8b-instruct -n rhoai-models -o jsonpath='{.status.url}'
```

Example output:
```
https://granite-8b-instruct-rhoai-models.apps.cluster-xxxx.opentlc.com
```

### Test the Endpoint

```bash
MODEL_URL="https://granite-8b-instruct-rhoai-models.apps.cluster-xxxx.opentlc.com"

curl ${MODEL_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "granite-8b-instruct",
    "messages": [
      {"role": "user", "content": "What is AI?"}
    ]
  }'
```

## Step 3: Add OpenShift AI Model to LiteLLM

### Via LiteLLM Admin UI

1. **Login to LiteLLM Admin Portal**
   - URL: `https://maas-rhdp.apps.your-cluster.com`
   - Use admin credentials from deployment output

2. **Click "Add Model"**

3. **Fill in the form:**

```
Provider: OpenAI-Compatible Endpoints (Together AI, etc.)
LiteLLM Model Name(s): granite-8b-instruct
Model Mappings:
  Public Name: Granite 8B Instruct
  LiteLLM Model: granite-8b-instruct
Mode: Chat - /chat/completions
API Base: https://granite-8b-instruct-rhoai-models.apps.cluster-xxxx.opentlc.com/v1
API Key: (leave empty or use token if required)
```

4. **Click "Test Connect"** to verify
5. **Click "Add Model"**

### Via ConfigMap (For Production)

Create a configuration file with OpenShift AI models:

```yaml
model_list:
  # Granite 8B Instruct
  - model_name: granite-8b-instruct
    litellm_params:
      model: openai/granite-8b-instruct
      api_base: https://granite-8b-instruct-rhoai-models.apps.cluster-xxxx.opentlc.com/v1
      api_key: ""  # Leave empty if no auth required

  # Llama 3.1 8B Instruct
  - model_name: llama-3.1-8b-instruct
    litellm_params:
      model: openai/llama-3.1-8b-instruct
      api_base: https://llama-rhoai-models.apps.cluster-xxxx.opentlc.com/v1
      api_key: ""

  # Mistral 7B Instruct
  - model_name: mistral-7b-instruct
    litellm_params:
      model: openai/mistral-7b-instruct
      api_base: https://mistral-rhoai-models.apps.cluster-xxxx.opentlc.com/v1
      api_key: ""

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
  database_url: "os.environ/DATABASE_URL"
```

Apply the configuration:

```bash
# Create ConfigMap
oc create configmap litellm-rhoai-config \
  -n rhpds \
  --from-file=config.yaml=litellm-rhoai-config.yaml

# Update LiteLLM deployment
oc set volume deployment/litellm -n rhpds \
  --add \
  --name=rhoai-config \
  --type=configmap \
  --configmap-name=litellm-rhoai-config \
  --mount-path=/app/rhoai-config.yaml \
  --sub-path=config.yaml

oc set env deployment/litellm -n rhpds \
  CONFIG_FILE_PATH=/app/rhoai-config.yaml

# Restart LiteLLM
oc rollout restart deployment/litellm -n rhpds
```

## Step 4: Create Virtual Keys for Users

Once models are added, create virtual keys:

```bash
# Get LiteLLM credentials
LITELLM_MASTER_KEY=$(oc get secret litellm-secret -n rhpds -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
LITELLM_URL=$(oc get route litellm -n rhpds -o jsonpath='{.spec.host}')

# Create virtual key with access to Granite model
curl "https://${LITELLM_URL}/key/generate" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "models": ["granite-8b-instruct", "llama-3.1-8b-instruct"],
    "max_budget": 100,
    "duration": "30d",
    "metadata": {
      "user": "data-scientist@example.com",
      "description": "Access to OpenShift AI models"
    }
  }'
```

Response:
```json
{
  "key": "sk-xxxxxxxxxxxxxx",
  "expires": "2025-12-05"
}
```

## Step 5: Users Access OpenShift AI Models

Share the virtual key with users. They can now access locally hosted models:

### Using curl

```bash
curl https://maas-rhdp.apps.your-cluster.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-user-virtual-key" \
  -d '{
    "model": "granite-8b-instruct",
    "messages": [
      {"role": "system", "content": "You are a helpful AI assistant."},
      {"role": "user", "content": "Explain quantum computing in simple terms."}
    ]
  }'
```

### Using Python

```python
import openai

client = openai.OpenAI(
    api_key="sk-user-virtual-key",
    base_url="https://maas-rhdp.apps.your-cluster.com"
)

response = client.chat.completions.create(
    model="granite-8b-instruct",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is Red Hat OpenShift?"}
    ]
)

print(response.choices[0].message.content)
```

## Common OpenShift AI Model Configurations

### Granite Models

```yaml
# Granite 3.0 8B Instruct
- model_name: granite-8b-instruct
  litellm_params:
    model: openai/granite-8b-instruct
    api_base: https://granite-8b-rhoai-models.apps.cluster.com/v1

# Granite 3.0 2B Instruct (smaller, faster)
- model_name: granite-2b-instruct
  litellm_params:
    model: openai/granite-2b-instruct
    api_base: https://granite-2b-rhoai-models.apps.cluster.com/v1

# Granite Code 8B (for coding tasks)
- model_name: granite-code-8b
  litellm_params:
    model: openai/granite-code-8b
    api_base: https://granite-code-rhoai-models.apps.cluster.com/v1
```

### Meta Llama Models

```yaml
# Llama 3.1 8B Instruct
- model_name: llama-3.1-8b-instruct
  litellm_params:
    model: openai/llama-3.1-8b-instruct
    api_base: https://llama-8b-rhoai-models.apps.cluster.com/v1

# Llama 3.1 70B Instruct (requires GPU)
- model_name: llama-3.1-70b-instruct
  litellm_params:
    model: openai/llama-3.1-70b-instruct
    api_base: https://llama-70b-rhoai-models.apps.cluster.com/v1
```

### Mistral Models

```yaml
# Mistral 7B Instruct
- model_name: mistral-7b-instruct
  litellm_params:
    model: openai/mistral-7b-instruct
    api_base: https://mistral-rhoai-models.apps.cluster.com/v1

# Mixtral 8x7B (MoE model)
- model_name: mixtral-8x7b-instruct
  litellm_params:
    model: openai/mixtral-8x7b-instruct
    api_base: https://mixtral-rhoai-models.apps.cluster.com/v1
```

## Troubleshooting

### Model Not Accessible

1. **Check model is running in OpenShift AI:**
   ```bash
   oc get inferenceservice -n rhoai-models
   ```

2. **Verify route exists:**
   ```bash
   oc get route -n rhoai-models
   ```

3. **Test direct access:**
   ```bash
   curl https://granite-8b-rhoai-models.apps.cluster.com/v1/models
   ```

### Connection Timeout

- **Check network policies** allow traffic from `rhpds` namespace to OpenShift AI namespace
- **Verify service mesh** configuration if using Istio/ServiceMesh

```bash
# Allow traffic from rhpds to rhoai-models
oc apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-litellm
  namespace: rhoai-models
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: rhpds
EOF
```

### Authentication Errors

If OpenShift AI models require authentication:

1. **Create service account token:**
   ```bash
   oc create sa litellm-client -n rhpds
   oc policy add-role-to-user view system:serviceaccount:rhpds:litellm-client -n rhoai-models
   TOKEN=$(oc create token litellm-client -n rhpds)
   ```

2. **Add token to LiteLLM configuration:**
   ```yaml
   - model_name: granite-8b-instruct
     litellm_params:
       model: openai/granite-8b-instruct
       api_base: https://granite-rhoai-models.apps.cluster.com/v1
       api_key: "os.environ/RHOAI_TOKEN"
   ```

3. **Store token in secret:**
   ```bash
   oc create secret generic rhoai-token \
     -n rhpds \
     --from-literal=RHOAI_TOKEN=${TOKEN}

   oc set env deployment/litellm -n rhpds \
     --from=secret/rhoai-token
   ```

## Best Practices

1. **Use Internal Service Names**: For better performance, use internal service names when LiteLLM and OpenShift AI are in the same cluster:
   ```yaml
   api_base: http://granite-8b-instruct.rhoai-models.svc.cluster.local:8080/v1
   ```

2. **Set Resource Limits**: Configure model replicas and autoscaling in OpenShift AI based on expected load

3. **Monitor Performance**: Use OpenShift AI metrics to monitor model performance and response times

4. **Cost Tracking**: Use LiteLLM's cost tracking features even for local models to monitor usage

5. **Load Balancing**: Deploy multiple replicas of models in OpenShift AI for high availability

## Example: Complete Integration

Here's a complete example integrating multiple OpenShift AI models:

```yaml
model_list:
  # Granite for general tasks
  - model_name: granite-8b
    litellm_params:
      model: openai/granite-8b-instruct
      api_base: http://granite-8b.rhoai-models.svc.cluster.local:8080/v1
      rpm: 100

  # Granite Code for programming
  - model_name: granite-code
    litellm_params:
      model: openai/granite-code-8b
      api_base: http://granite-code.rhoai-models.svc.cluster.local:8080/v1
      rpm: 50

  # Llama for conversational AI
  - model_name: llama-8b
    litellm_params:
      model: openai/llama-3.1-8b-instruct
      api_base: http://llama-8b.rhoai-models.svc.cluster.local:8080/v1
      rpm: 100

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
  database_url: "os.environ/DATABASE_URL"

router_settings:
  routing_strategy: simple-shuffle  # Load balance across replicas
  num_retries: 2
  timeout: 30
```

This configuration provides users with access to locally hosted AI models through a unified API, with cost tracking, rate limiting, and access control managed by LiteLLM.
