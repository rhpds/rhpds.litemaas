# Red Hat Demo Platform Branding for LiteMaaS

This document describes how to enable Red Hat Demo Platform (RHDP) branding in LiteMaaS deployments.

## Overview

The RHDP branding feature allows you to:
- **Replace the LiteMaaS logo** with the Red Hat Demo Platform logo
- **Support light and dark themes** with appropriate logo variants
- **Add service attribution text** (optional footer)
- **No application code changes required** - pure deployment-time customization

## Quick Start

### New Deployments

1. **Place logo files** in `files/` directory:
   ```bash
   cp Logo-Red_Hat-Demo_Platform_Team-A-Black-RGB.svg files/
   cp Logo-Red_Hat-Demo_Platform_Team-A-White-RGB.svg files/
   ```

2. **Deploy with branding enabled**:
   ```bash
   cd ~/work/code/rhpds.litemaas
   ansible-playbook playbooks/deploy_litemaas.yml \
     -e @examples/enable-rhdp-branding.yml
   ```

### Existing Deployments

**Option A: Redeploy with branding (RECOMMENDED)**
```bash
cd ~/work/code/rhpds.litemaas
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_branding_enabled=true \
  -e ocp4_workload_litemaas_branding_logo_light_path=files/Logo-Red_Hat-Demo_Platform_Team-A-Black-RGB.svg \
  -e ocp4_workload_litemaas_branding_logo_dark_path=files/Logo-Red_Hat-Demo_Platform_Team-A-White-RGB.svg
```

**Option B: Quick test on running deployment**

See `scripts/enable-branding-existing-deployment.sh` for manual patching instructions.

## Configuration Variables

Add these to your deployment variables or AgnosticV configuration:

```yaml
# Enable branding
ocp4_workload_litemaas_branding_enabled: true

# Logo file paths (local paths on Ansible control machine)
ocp4_workload_litemaas_branding_logo_light_path: "files/Logo-Red_Hat-Demo_Platform_Team-A-Black-RGB.svg"
ocp4_workload_litemaas_branding_logo_dark_path: "files/Logo-Red_Hat-Demo_Platform_Team-A-White-RGB.svg"

# Service attribution text
ocp4_workload_litemaas_branding_service_text: "Service provided by Red Hat Demo Platform"

# Show footer with service text (optional, default: false)
ocp4_workload_litemaas_branding_enable_footer: true
```

## How It Works

### Architecture

The branding system uses:

1. **ConfigMap** (`litemaas-branding`) containing:
   - Logo SVG files (light and dark variants)
   - JavaScript injection script

2. **Init Container** (`setup-branding`) that:
   - Copies branding assets to nginx html directory
   - Injects branding script reference into `index.html`

3. **JavaScript Injection** that:
   - Replaces logo elements on page load
   - Watches for theme changes (light/dark mode)
   - Optionally adds footer with service attribution
   - Handles SPA navigation (React Router)

### Logo Replacement Logic

The script searches for logo images using multiple selectors:
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

## Multi-User Deployments

Branding is currently supported for single-user deployments only.

Multi-user support coming soon - the ConfigMap will need to be created per-user namespace.

## Troubleshooting

### Logo not appearing

1. **Check ConfigMap exists**:
   ```bash
   oc get configmap litemaas-branding -n litemaas
   ```

2. **Check init container logs**:
   ```bash
   POD=$(oc get pod -n litemaas -l app=litemaas-frontend -o name | head -1)
   oc logs -n litemaas $POD -c setup-branding
   ```

3. **Check branding script is loaded**:
   - Open browser DevTools Console
   - Look for "RHDP Branding: Initializing..." message
   - Check for `/branding/branding-inject.js` in Network tab

### Theme not switching

The script watches for `data-theme` attribute changes. If your frontend uses a different theme mechanism, update the `observeThemeChanges()` function.

### Footer overlapping content

If the footer overlaps page content, adjust the `addFooterText()` function:
```javascript
pageContent.style.paddingBottom = '60px'; // Increase padding
```

## AgnosticV Integration

### Catalog Configuration

Add to your `common.yaml`:

```yaml
# In AgnosticV catalog item
workloads:
  - rhpds.litemaas.ocp4_workload_litemaas

# Enable branding
ocp4_workload_litemaas_branding_enabled: true
ocp4_workload_litemaas_branding_logo_light_path: "{{ playbook_dir }}/files/Logo-Red_Hat-Demo_Platform_Team-A-Black-RGB.svg"
ocp4_workload_litemaas_branding_logo_dark_path: "{{ playbook_dir }}/files/Logo-Red_Hat-Demo_Platform_Team-A-White-RGB.svg"
ocp4_workload_litemaas_branding_service_text: "Service provided by Red Hat Demo Platform"
ocp4_workload_litemaas_branding_enable_footer: false  # Usually false for catalog items
```

### Logo File Placement

Place logo files in AgnosticV repository:
```
agnosticv/
├── includes/
│   └── files/
│       ├── Logo-Red_Hat-Demo_Platform_Team-A-Black-RGB.svg
│       └── Logo-Red_Hat-Demo_Platform_Team-A-White-RGB.svg
```

Update paths accordingly:
```yaml
ocp4_workload_litemaas_branding_logo_light_path: "{{ playbook_dir }}/includes/files/Logo-Red_Hat-Demo_Platform_Team-A-Black-RGB.svg"
```

## Examples

See `examples/enable-rhdp-branding.yml` for complete configuration example.

## Disabling Branding

To disable branding on a deployment:

```bash
ansible-playbook playbooks/deploy_litemaas.yml \
  -e ocp4_workload_litemaas_branding_enabled=false
```

Or manually remove:
```bash
oc delete configmap litemaas-branding -n litemaas
oc rollout restart deployment/litemaas-frontend -n litemaas
```

## Future Enhancements

Planned improvements:
- Multi-user deployment support
- Custom CSS injection
- Additional branding elements (header bar, custom colors)
- Support for external logo URLs (CDN)

## Support

For issues or questions:
- File issue in rhpds.litemaas repository
- Contact RHDP team: psrivast@redhat.com
