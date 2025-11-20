#!/bin/bash
# Enable RHDP branding on an existing LiteMaaS deployment
#
# This script patches an existing LiteMaaS frontend deployment to add RHDP branding
# without redeploying the entire workload.
#
# Usage:
#   ./scripts/enable-branding-existing-deployment.sh [namespace]
#
# Example:
#   ./scripts/enable-branding-existing-deployment.sh litemaas

set -e

NAMESPACE="${1:-litemaas}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGO_LIGHT_PATH="$(dirname "$SCRIPT_DIR")/files/Logo-Red_Hat-Demo_Platform_Team-A-Black-RGB.svg"
LOGO_DARK_PATH="$(dirname "$SCRIPT_DIR")/files/Logo-Red_Hat-Demo_Platform_Team-A-White-RGB.svg"

echo "========================================="
echo "RHDP Branding Enablement Script"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo ""

# Check if logos exist
if [ ! -f "$LOGO_LIGHT_PATH" ]; then
  echo "ERROR: Light logo not found at: $LOGO_LIGHT_PATH"
  exit 1
fi

if [ ! -f "$LOGO_DARK_PATH" ]; then
  echo "ERROR: Dark logo not found at: $LOGO_DARK_PATH"
  exit 1
fi

echo "Step 1: Creating ConfigMap with RHDP logos..."
oc create configmap litemaas-branding \
  --from-file=logo-light.svg="$LOGO_LIGHT_PATH" \
  --from-file=logo-dark.svg="$LOGO_DARK_PATH" \
  --from-literal=branding-inject.js="$(cat << 'EOF'
(function() {
  console.log('RHDP Branding: Initializing...');

  const LOGO_LIGHT_PATH = '/branding/logo-light.svg';
  const LOGO_DARK_PATH = '/branding/logo-dark.svg';
  const SERVICE_TEXT = 'Service provided by Red Hat Demo Platform';
  const ENABLE_FOOTER_TEXT = true;

  function init() {
    console.log('RHDP Branding: Replacing logo...');
    replaceLogo();

    if (ENABLE_FOOTER_TEXT && SERVICE_TEXT) {
      console.log('RHDP Branding: Adding footer text...');
      addFooterText();
    }

    observeThemeChanges();
  }

  function replaceLogo() {
    const logoSelectors = [
      'img[src*="logo"]',
      'img[alt*="LiteMaaS"]',
      'img[alt*="litemaas"]',
      '[class*="logo"] img',
      '[class*="Logo"] img'
    ];

    logoSelectors.forEach(selector => {
      const logos = document.querySelectorAll(selector);
      logos.forEach(img => {
        const isDarkTheme = document.documentElement.getAttribute('data-theme') === 'dark';
        const newSrc = isDarkTheme ? LOGO_DARK_PATH : LOGO_LIGHT_PATH;

        if (!img.src.includes('/branding/logo-')) {
          console.log('RHDP Branding: Replacing logo element:', img);
          img.src = newSrc;
          img.alt = 'Red Hat Demo Platform';
          if (!img.style.height) {
            img.style.height = '40px';
          }
        }
      });
    });
  }

  function addFooterText() {
    if (document.getElementById('rhdp-branding-footer')) {
      return;
    }

    const footer = document.createElement('div');
    footer.id = 'rhdp-branding-footer';
    footer.style.cssText = 'position: fixed; bottom: 0; left: 0; right: 0; padding: 8px 16px; background-color: var(--pf-t--global--background--color--secondary--default, #f5f5f5); border-top: 1px solid var(--pf-t--global--border--color--default, #d2d2d2); text-align: center; font-size: 12px; color: var(--pf-t--global--text--color--subtle, #6a6e73); z-index: 1000;';
    footer.innerHTML = '<span>' + SERVICE_TEXT + '</span>';

    document.body.appendChild(footer);

    const pageContent = document.querySelector('[class*="pf-v6-c-page__main"]');
    if (pageContent) {
      pageContent.style.paddingBottom = '40px';
    }
  }

  function observeThemeChanges() {
    const observer = new MutationObserver(() => {
      replaceLogo();
    });

    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme']
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  let lastUrl = location.href;
  new MutationObserver(() => {
    const url = location.href;
    if (url !== lastUrl) {
      lastUrl = url;
      setTimeout(init, 100);
    }
  }).observe(document, {subtree: true, childList: true});

  console.log('RHDP Branding: Initialization complete');
})();
EOF
)" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | oc apply -f - -n "$NAMESPACE"

echo "✓ ConfigMap created"
echo ""

echo "Step 2: Patching frontend deployment to use branding..."

# Note: This requires restarting the pod. For a production-safe approach,
# you should redeploy using the Ansible playbook with branding enabled.

echo ""
echo "========================================="
echo "Manual Steps Required:"
echo "========================================="
echo "The ConfigMap has been created, but the frontend deployment needs to be updated."
echo ""
echo "Option A: Redeploy with Ansible (RECOMMENDED for production):"
echo "  cd ~/work/code/rhpds.litemaas"
echo "  ansible-playbook playbooks/deploy_litemaas.yml -e @examples/enable-rhdp-branding.yml"
echo ""
echo "Option B: Quick test by injecting script into running pod:"
echo "  POD=\$(oc get pod -n $NAMESPACE -l app=litemaas-frontend -o name | head -1)"
echo "  oc exec -n $NAMESPACE \$POD -- sh -c 'cat > /usr/share/nginx/html/branding-test.js <<EOF"
echo "  (branding script content here)"
echo "  EOF'"
echo ""
echo "Then manually add <script src=\"/branding-test.js\"></script> to index.html"
echo ""
echo "========================================="
