# OpenShift OAuth Login for LiteLLM

This feature enables users to login to the LiteLLM UI using their OpenShift credentials instead of a shared admin username/password.

## Overview

When enabled, this feature:
- Creates an OpenShift OAuthClient
- Configures LiteLLM to use OpenShift as OAuth provider
- Allows users to login with their OpenShift username/password
- Optionally restricts access to specific groups

## Quick Start

### Enable OAuth Login

Add this to your deployment variables:

```yaml
ocp4_workload_litemaas_oauth_login_enabled: true
```

### Deploy with OAuth

```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_oauth_login_enabled=true
```

### HA Deployment with OAuth

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_ha_enabled=true \
  -e ocp4_workload_litemaas_oauth_login_enabled=true
```

## Configuration

### Basic Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_oauth_login_enabled` | `false` | Enable OpenShift OAuth login |
| `ocp4_workload_litemaas_oauth_client_name` | `litemaas-oauth` | OAuth client name |
| `ocp4_workload_litemaas_oauth_provider` | `openshift` | OAuth provider type |

### Advanced Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_litemaas_oauth_allowed_groups` | `[]` | Restrict to specific groups (empty = all) |
| `ocp4_workload_litemaas_oauth_scopes` | `["user:info", "user:check-access"]` | OAuth scopes |
| `ocp4_workload_litemaas_oauth_client_secret` | _auto-generated_ | OAuth client secret |

## Usage Examples

### Example 1: Basic OAuth Login

```yaml
# In AgnosticV common.yaml
ocp4_workload_litemaas_oauth_login_enabled: true
```

### Example 2: Restrict to Specific Groups

```yaml
ocp4_workload_litemaas_oauth_login_enabled: true
ocp4_workload_litemaas_oauth_allowed_groups:
  - "cluster-admins"
  - "litemaas-users"
```

### Example 3: Custom OAuth Client Name

```yaml
ocp4_workload_litemaas_oauth_login_enabled: true
ocp4_workload_litemaas_oauth_client_name: "my-litemaas-client"
```

## How It Works

### 1. OAuthClient Creation

The role creates an OpenShift OAuthClient with:
- **Client ID**: `litemaas-oauth` (or custom name)
- **Redirect URI**: `https://litellm-{route_name}.{cluster_domain}/oauth/callback`
- **Grant Method**: `auto` (automatic approval)

### 2. OAuth Endpoints

Auto-detected OAuth endpoints:
- **Authorization**: `https://oauth-openshift.{cluster_domain}/oauth/authorize`
- **Token**: `https://oauth-openshift.{cluster_domain}/oauth/token`
- **UserInfo**: `https://oauth-openshift.{cluster_domain}/oauth/userinfo`
- **Issuer**: `https://oauth-openshift.{cluster_domain}`

### 3. LiteLLM Configuration

Environment variables passed to LiteLLM:
```yaml
OAUTH_ENABLED: "true"
OAUTH_PROVIDER: "openshift"
OAUTH_CLIENT_ID: "litemaas-oauth"
OAUTH_CLIENT_SECRET: "***"
OAUTH_REDIRECT_URI: "https://litellm-rhpds.apps.cluster.com/oauth/callback"
OAUTH_AUTHORIZATION_ENDPOINT: "https://oauth-openshift.apps.cluster.com/oauth/authorize"
OAUTH_TOKEN_ENDPOINT: "https://oauth-openshift.apps.cluster.com/oauth/token"
OAUTH_USERINFO_ENDPOINT: "https://oauth-openshift.apps.cluster.com/oauth/userinfo"
```

## User Experience

### With OAuth Disabled (Default)

1. User opens LiteLLM UI
2. Sees login form
3. Enters admin username/password
4. Accesses LiteLLM

### With OAuth Enabled

1. User opens LiteLLM UI
2. Sees "Login with OpenShift" button
3. Clicks button → redirected to OpenShift login
4. Logs in with OpenShift credentials
5. Redirected back to LiteLLM → authenticated

## Access Control

### Allow All Authenticated Users

```yaml
ocp4_workload_litemaas_oauth_login_enabled: true
# No groups specified = all authenticated users can access
```

### Restrict to Specific Groups

```yaml
ocp4_workload_litemaas_oauth_login_enabled: true
ocp4_workload_litemaas_oauth_allowed_groups:
  - "cluster-admins"
  - "developers"
```

Users must be members of at least one specified group.

## Verification

### Check OAuthClient

```bash
oc get oauthclient litemaas-oauth -o yaml
```

Expected output:
```yaml
apiVersion: oauth.openshift.io/v1
kind: OAuthClient
metadata:
  name: litemaas-oauth
redirectURIs:
  - https://litellm-rhpds.apps.cluster.com/oauth/callback
secret: ***
grantMethod: auto
```

### Check OAuth Secret

```bash
oc get secret litemaas-oauth-config -n litemaas -o yaml
```

### Test OAuth Flow

1. Open LiteLLM URL in browser
2. Click "Login with OpenShift"
3. Should redirect to OpenShift OAuth page
4. Login with OpenShift credentials
5. Should redirect back to LiteLLM

## Troubleshooting

### Issue: "Invalid redirect URI"

**Cause**: Redirect URI doesn't match OAuthClient configuration

**Solution**: Check that the route matches the redirect URI:
```bash
oc get route litellm -n litemaas -o jsonpath='{.spec.host}'
oc get oauthclient litemaas-oauth -o jsonpath='{.redirectURIs[0]}'
```

### Issue: "Access denied"

**Cause**: User not in allowed groups

**Solution**: Check group membership:
```bash
oc get groups
oc describe group <group-name>
```

### Issue: OAuth login button not appearing

**Cause**: OAuth environment variables not set in LiteLLM pod

**Solution**: Check pod environment:
```bash
POD=$(oc get pod -n litemaas -l app=litemaas -o jsonpath='{.items[0].metadata.name}')
oc exec -n litemaas $POD -- env | grep OAUTH
```

## Compatibility

| Deployment Mode | OAuth Support |
|----------------|---------------|
| Single Instance | ✅ Yes |
| Multi-User | ✅ Yes (per-user) |
| HA Mode | ✅ Yes |

## Security Considerations

1. **Client Secret**: Auto-generated and stored in Kubernetes secret
2. **HTTPS Required**: OAuth only works over HTTPS (OpenShift routes)
3. **Group-based Access**: Use `oauth_allowed_groups` to restrict access
4. **Token Expiration**: Follows OpenShift token expiration policies

## Removal

OAuth configuration is automatically removed when:
```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_remove=true
```

Manual removal:
```bash
oc delete oauthclient litemaas-oauth
oc delete secret litemaas-oauth-config -n litemaas
```

## Integration with AgnosticV

### Catalog Configuration

```yaml
# In common.yaml
workloads:
  - rhpds.litemaas.ocp4_workload_litemaas

# Enable OAuth
ocp4_workload_litemaas_oauth_login_enabled: true

# Optional: Restrict to groups
ocp4_workload_litemaas_oauth_allowed_groups:
  - "{{ guid }}-users"
```

### User Info Message

When OAuth is enabled, users receive:
```
LiteLLM Admin Portal: https://litellm-rhpds.apps.cluster.com
Login with your OpenShift credentials
```

## Limitations

1. **LiteLLM Support**: Requires LiteLLM version that supports OAuth (check compatibility)
2. **Single OAuth Provider**: Only OpenShift OAuth is configured
3. **No SSO**: Each LiteLLM instance has separate OAuth client
4. **Group Sync**: Groups must exist in OpenShift

## Future Enhancements

- Support for other OAuth providers (Google, GitHub, etc.)
- Automatic group synchronization
- Role-based access control (RBAC)
- Session management and timeout configuration
- Multi-factor authentication (MFA) support

## References

- [OpenShift OAuth Documentation](https://docs.openshift.com/container-platform/latest/authentication/configuring-internal-oauth.html)
- [LiteLLM OAuth Configuration](https://docs.litellm.ai/)
- [Kubernetes OAuthClient API](https://docs.openshift.com/container-platform/latest/rest_api/oauth_apis/oauthclient-oauth-openshift-io-v1.html)
