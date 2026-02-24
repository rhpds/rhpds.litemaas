# OpenShift OAuth Login for LiteMaaS

Authentication is handled by the LiteMaaS backend using OpenShift OAuth (OAuthClient). Users log in with their OpenShift credentials through the frontend UI.

## Quick Start

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_oauth_enabled=true
```

Or with the deploy script:

```bash
./deploy-litemaas.sh litellm-rhpds --oauth
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_oauth_enabled` | `false` | Enable OAuth login |
| `ocp4_workload_litemaas_oauth_provider` | `openshift` | OAuth provider |
| `ocp4_workload_litemaas_oauth_client_id` | `{{ namespace }}` | OAuthClient name |
| `ocp4_workload_litemaas_oauth_client_secret` | _auto-generated_ | OAuthClient secret |

## How It Works

```
User → Frontend UI → Backend /api/auth/callback → OpenShift OAuth → JWT session
```

1. The Ansible role creates an OpenShift `OAuthClient` resource with redirect URIs pointing to the backend callback endpoint
2. User clicks "Login" on the frontend
3. Backend redirects to OpenShift OAuth login page
4. After login, OpenShift redirects back to the backend callback
5. Backend creates/updates the user in the database and issues a JWT session

The `OAuthClient` and redirect URIs are configured automatically during `pre_workload.yml`.

## What Gets Created

- **OAuthClient** named after the namespace (e.g., `litemaas`)
- **Redirect URIs**: `https://litellm.<cluster>/api/auth/callback` and `https://litellm-frontend.<cluster>/api/auth/callback`
- **Backend secret** with `OAUTH_CLIENT_SECRET`

## Verification

```bash
# Check OAuthClient
oc get oauthclient <namespace> -o yaml

# Redirect URIs should include both API and frontend callbacks
# Check backend logs for OAuth flow
oc logs deployment/litellm-backend -n <namespace> --tail=50
```

## AgnosticV Integration

```yaml
# In common.yaml
workloads:
  - rhpds.litemaas.ocp4_workload_litemaas

ocp4_workload_litemaas_oauth_enabled: true
```

## Troubleshooting

### OAuth callback fails

Check redirect URIs match the actual route hostnames:
```bash
oc get oauthclient <namespace> -o jsonpath='{.redirectURIs}'
oc get route -n <namespace>
```

### Users can't log in after migration

If users were migrated from an older version, their `oauth_id` in the database may not match the OpenShift user UID. The v0.2.1+ backend has an email fallback — it looks up by email if oauth_id doesn't match and updates the oauth_id automatically.

## Removal

OAuth cleanup happens automatically when removing the deployment:
```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_remove=true
```

This removes the OAuthClient along with the namespace.
