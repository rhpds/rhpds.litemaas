# Red Hat Demo Platform Branding for LiteMaaS

Enable RHDP branding in LiteMaaS deployments with a single flag.

## Quick Start

### Deploy with Branding

```bash
# Using deploy script
./deploy-litemaas.sh litellm-rhpds --rhdp

# Using Ansible directly
ansible-playbook playbooks/deploy_litemaas_ha.yml \
  -e ocp4_workload_litemaas_branding_enabled=true
```

### What It Does

- Replaces the LiteMaaS logo with the Red Hat Demo Platform logo
- Supports light and dark themes with appropriate logo variants
- Adds service attribution text (optional footer)
- No application code changes required - pure deployment-time customization

## Configuration Variables

```yaml
# Enable branding
ocp4_workload_litemaas_branding_enabled: true

# Logo file paths (local paths on Ansible control machine)
ocp4_workload_litemaas_branding_logo_light_path: "files/Logo-Red_Hat-Demo_Platform_Team-A-Black-RGB.svg"
ocp4_workload_litemaas_branding_logo_dark_path: "files/Logo-Red_Hat-Demo_Platform_Team-A-White-RGB.svg"

# Service attribution text
ocp4_workload_litemaas_branding_service_text: "Service provided by Red Hat Demo Platform"

# Show footer with service text (optional, default: true)
ocp4_workload_litemaas_branding_enable_footer: true
```

## How It Works

### Architecture

The branding system uses an nginx sidecar proxy pattern:

1. **ConfigMap** (`litemaas-branding`) containing:
   - Logo SVG files (light and dark variants)
   - JavaScript injection script

2. **ConfigMap** (`litemaas-branding-nginx-config`) containing:
   - Nginx configuration for the branding proxy

3. **Init Container** (`setup-branding`) that:
   - Copies branding assets from ConfigMap to a shared volume

4. **Sidecar Container** (`branding-proxy`) that:
   - Runs nginx on port 8081
   - Proxies requests to the frontend on port 8080
   - Injects the branding JavaScript into HTML responses via `sub_filter`
   - Serves branding assets (logos, favicon) from `/branding/` path

5. **Service** routes traffic to port 8081 (branding proxy) instead of 8080 (frontend)

### Logo Replacement Logic

The injected script searches for logo images using multiple selectors:
- `img[src*="logo"]`
- `img[alt*="LiteMaaS"]` or `img[alt*="litemaas"]`
- `[class*="logo"] img` or `[class*="Logo"] img`

When found, it replaces the `src` with:
- `/branding/logo-light.svg` for light theme
- `/branding/logo-dark.svg` for dark theme

### Theme Detection

Uses `data-theme` attribute on `<html>` element:
```javascript
const isDarkTheme = document.documentElement.getAttribute('data-theme') === 'dark';
```

## Logo Requirements

- **Format**: SVG (recommended) or PNG
- **Light theme logo**: Dark/black colored (shows on light background)
- **Dark theme logo**: Light/white colored (shows on dark background)
- **Recommended size**: 1116.2 x 163.8 px (Red Hat Demo Platform standard)
- **Max height**: Will be resized to 40px height automatically

## Troubleshooting

### Logo not appearing

1. **Check ConfigMaps exist**:
   ```bash
   oc get configmap litemaas-branding -n litemaas
   oc get configmap litemaas-branding-nginx-config -n litemaas
   ```

2. **Check init container logs**:
   ```bash
   POD=$(oc get pod -n litemaas -l app=litellm-frontend -o name | head -1)
   oc logs -n litemaas $POD -c setup-branding
   ```

3. **Check branding proxy logs**:
   ```bash
   POD=$(oc get pod -n litemaas -l app=litellm-frontend -o name | head -1)
   oc logs -n litemaas $POD -c branding-proxy
   ```

4. **Check branding script is loaded**:
   - Open browser DevTools Console
   - Look for "RHDP Branding: Initializing..." message
   - Check for `/branding/branding-inject.js` in Network tab

### Frontend pod shows 2/2 containers

This is expected when branding is enabled. The pod runs both the frontend container and the branding-proxy sidecar.

## AgnosticV Integration

```yaml
# In common.yaml
workloads:
  - rhpds.litemaas.ocp4_workload_litemaas

ocp4_workload_litemaas_branding_enabled: true
ocp4_workload_litemaas_branding_logo_light_path: "{{ playbook_dir }}/files/Logo-Red_Hat-Demo_Platform_Team-A-Black-RGB.svg"
ocp4_workload_litemaas_branding_logo_dark_path: "{{ playbook_dir }}/files/Logo-Red_Hat-Demo_Platform_Team-A-White-RGB.svg"
ocp4_workload_litemaas_branding_service_text: "Service provided by Red Hat Demo Platform"
ocp4_workload_litemaas_branding_enable_footer: false
```

## Disabling Branding

Redeploy without the branding flag:

```bash
ansible-playbook playbooks/deploy_litemaas_ha.yml
```

Or manually remove:
```bash
oc delete configmap litemaas-branding litemaas-branding-nginx-config -n litemaas
oc rollout restart deployment/litellm-frontend -n litemaas
```

## Support

For issues or questions:
- File issue in rhpds.litemaas repository
- Contact RHDP team: psrivast@redhat.com
