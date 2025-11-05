# Deployment Instructions for RHDP Bastion

## Step 1: Push to GitHub (On Your Mac)

```bash
# You're already in the directory with the initial commit
cd ~/work/code/rhpds-litemaas-collection

# Create the repo on GitHub manually:
# Go to: https://github.com/new
# Repository name: rhpds.litemaas
# Description: Cloud-agnostic Ansible collection for deploying LiteMaaS on OpenShift
# Public repository
# DO NOT initialize with README (we already have one)
# Click "Create repository"

# Then push your code:
git remote add origin https://github.com/prakhar1985/rhpds.litemaas.git
git branch -M main
git push -u origin main
```

## Step 2: Deploy on Bastion (AWS Cluster)

### Connect to Bastion

```bash
ssh lab-user@bastion.9lpft.sandbox2068.opentlc.com
```

### Verify Prerequisites

```bash
# Activate virtualenv
source /opt/virtualenvs/k8s/bin/activate

# Verify you're logged in
oc whoami
# Should show: system:admin

# Check cluster version
oc get clusterversion

# Check storage classes
oc get storageclass
```

### Clone and Deploy

```bash
# Clone the collection
cd ~
git clone https://github.com/prakhar1985/rhpds.litemaas.git
cd rhpds.litemaas

# Build the collection
ansible-galaxy collection build

# Install the collection
ansible-galaxy collection install rhpds-litemaas-*.tar.gz --force

# Deploy LiteMaaS
ansible-playbook playbooks/deploy_litemaas.yml
```

### Expected Output

The playbook will:
1. Auto-detect AWS as the cloud provider
2. Auto-select `gp3-csi` or `gp2-csi` storage class
3. Auto-detect cluster domain
4. Create `rhpds` namespace
5. Deploy PostgreSQL, Backend, Frontend, LiteLLM
6. Display access URLs and credentials

### Verify Deployment

```bash
# Check all resources
oc get all -n rhpds

# Check PVC (should be Bound)
oc get pvc -n rhpds

# Check routes
oc get routes -n rhpds

# View deployment info
cat ~/litemaas-deployment-info.txt
```

### Access the Application

After deployment completes, you'll see:

```
Frontend URL: https://litemaas-rhpds.<cluster-domain>
LiteLLM Admin: https://litellm-rhpds.<cluster-domain>

LiteLLM Admin Credentials:
  Username: admin
  Password: <generated-password>
```

## Step 3: Test the Deployment

### Check Pod Status

```bash
oc get pods -n rhpds -w
```

Wait until all pods show `1/1 Running`:
- `postgres-0`
- `litemaas-backend-xxxxx`
- `litemaas-frontend-xxxxx`
- `litellm-xxxxx`

### Test Frontend Access

```bash
# Get the frontend route
FRONTEND_URL=$(oc get route litemaas-frontend -n rhpds -o jsonpath='{.spec.host}')
echo "Frontend: https://$FRONTEND_URL"

# Test with curl
curl -k https://$FRONTEND_URL
```

### Test LiteLLM Admin

```bash
# Get the LiteLLM route
LITELLM_URL=$(oc get route litellm -n rhpds -o jsonpath='{.spec.host}')
echo "LiteLLM: https://$LITELLM_URL"

# Open in browser (if you have X11 forwarding)
# Or access from your local machine
```

## Troubleshooting

### If Pods Are Not Starting

```bash
# Check pod events
oc describe pod -n rhpds <pod-name>

# Check logs
oc logs -n rhpds <pod-name>

# Check PVC status
oc get pvc -n rhpds
```

### If Storage Class Not Found

```bash
# List available storage classes
oc get storageclass

# Override storage class
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_postgres_storage_class=gp2
```

### Re-deploy After Changes

```bash
# Remove existing deployment
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_remove=true

# Deploy again
ansible-playbook playbooks/deploy_litemaas.yml
```

## Clean Up

```bash
# Remove the entire deployment
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_remove=true

# Or manually delete namespace
oc delete project rhpds
oc delete oauthclient litemaas-rhpds
```

## What's Next?

After successful deployment:

1. Access the frontend URL
2. Login with OpenShift OAuth
3. Configure AI model providers in LiteLLM Admin
4. Create API keys in LiteMaaS
5. Test model access

## Support

For issues or questions:
- GitHub Issues: https://github.com/prakhar1985/rhpds.litemaas/issues
- RHPDS Slack: #rhdp-litemaas
