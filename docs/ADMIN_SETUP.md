# Admin User Setup for LiteMaaS

## How Admin Access Works

LiteMaaS uses **API keys** for admin operations, not role-based access control.

### User Roles

1. **Regular Users**: Login via Google OAuth, get standard permissions
2. **Admins**: Login via Google OAuth + use admin API keys for admin operations

### Admin Users

When using **OpenShift htpasswd authentication**, the admin user is:
- **admin** (htpasswd username)

When using **Google OAuth** (future), admin users would be identified by email:
- sborenst@redhat.com
- ankay@redhat.com
- psrivast@redhat.com
- rshah@redhat.com
- ajammula@redhat.com

**Note**: The `ocp4_workload_litemaas_admin_emails` variable accepts both usernames (for htpasswd) and email addresses (for Google OAuth).

## Admin API Keys

Admin API keys are configured in the backend via `ADMIN_API_KEYS` environment variable.

### Getting Admin API Keys

After deployment, retrieve the admin API key:

```bash
# Get the auto-generated admin API key
oc get secret backend-secret -n rhpds -o jsonpath='{.data.ADMIN_API_KEY}' | base64 -d
echo ""
```

### Using Admin API Keys

Admins can use the API key in two ways:

1. **Frontend**: Set the admin API key in the UI settings
2. **API**: Include in API requests:
   ```bash
   curl -H "X-API-Key: <admin-api-key>" https://litemaas-rhpds.../api/admin/...
   ```

### Adding More Admin Keys

To add additional admin API keys, update the deployment:

```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_oauth_client_id=... \
  -e ocp4_workload_litemaas_oauth_client_secret=... \
  -e '{"ocp4_workload_litemaas_admin_api_keys": ["key1", "key2", "key3"]}'
```

## Security Notes

- Admin API keys grant full admin access
- Keep keys secure and rotate regularly
- Don't share keys in public channels
- Each admin can have their own unique key
