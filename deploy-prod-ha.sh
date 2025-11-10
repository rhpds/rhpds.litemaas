#!/bin/bash
set -e

echo "========================================="
echo "LiteMaaS Production HA Deployment Script"
echo "========================================="

# Navigate to repo directory
cd ~/work/code/rhpds.litemaas

# Pull latest changes
echo "Pulling latest changes from git..."
git pull origin redis-ha-scaling

# Remove old collection tarball
echo "Cleaning up old collection tarball..."
rm -f rhpds-litemaas-0.1.2.tar.gz

# Rebuild collection
echo "Building collection..."
ansible-galaxy collection build --force

# Install collection
echo "Installing collection..."
ansible-galaxy collection install rhpds-litemaas-0.2.0.tar.gz --force

# Deploy Production HA
echo "Deploying Production HA (Redis Enterprise + 3 LiteLLM replicas)..."
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_deploy_redis=true \
  -e ocp4_workload_litemaas_litellm_replicas=3 \
  -e ocp4_workload_litemaas_postgres_storage_class=ocs-external-storagecluster-ceph-rbd

echo "========================================="
echo "Deployment complete!"
echo "========================================="
