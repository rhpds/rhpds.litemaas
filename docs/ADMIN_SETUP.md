# Admin User Setup for LiteMaaS

## How Admin Access Works

LiteMaaS uses a three-tier role hierarchy: `admin > adminReadonly > user`.

- **user**: Default role assigned on first OAuth login. Can browse models, create API keys, manage own subscriptions.
- **adminReadonly**: Read-only admin access. Can view all users, analytics, and system state.
- **admin**: Full admin access. Can manage users, approve subscriptions, configure models and budgets.

## Adding Admin Users

**Important**: Users must log in via OAuth first to create their account with the correct OpenShift `oauth_id`. Do NOT insert users directly into PostgreSQL — the OAuth ID from OpenShift is a UUID, not the username.

### Step 1: User logs in via the frontend

Have the user visit the frontend URL and log in with their OpenShift credentials. This creates their account with the correct OAuth identity.

### Step 2: Promote to admin

Use the `promote-admin.sh` script:

```bash
./promote-admin.sh <namespace> <email>

# Examples:
./promote-admin.sh prod-rhdp psrivast@redhat.com
./promote-admin.sh prod-rhdp ajammula@redhat.com
```

Or manually via psql:

```bash
oc exec $(oc get pods -n <namespace> -l app=litellm-postgres -o name) \
  -n <namespace> -- psql -U litellm -d litellm -c \
  "UPDATE users SET roles = ARRAY['admin', 'user'] WHERE email = 'user@redhat.com';"
```

### Step 3: Verify

```bash
oc exec $(oc get pods -n <namespace> -l app=litellm-postgres -o name) \
  -n <namespace> -- psql -U litellm -d litellm -c \
  "SELECT username, email, roles FROM users WHERE 'admin' = ANY(roles);"
```

## Admin API Key

The backend admin API key is auto-generated during deployment and stored in the `backend-secret`:

```bash
oc get secret backend-secret -n <namespace> -o jsonpath='{.data.ADMIN_API_KEY}' | base64 -d
```

This key is used for backend API operations (e.g., `Authorization: Bearer <key>`).

## LiteLLM Master Key

The LiteLLM master key is for the LiteLLM admin UI and API:

```bash
oc get secret litellm-secret -n <namespace> -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d
```

## Security Notes

- Admin API keys grant full admin access — keep them secure
- Users must log in via OAuth before being promoted (direct DB inserts will break OAuth login)
- The OAuth ID from OpenShift is a UUID (`1185a310-eace-401e-8ce7-60e72d68bf3e`), not the username
