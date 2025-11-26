# Changelog

All notable changes to the LiteMaaS Ansible collection will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2025-01-20

### Added
- **RHDP Branding for HA Deployments**
  - Red Hat Demo Platform logo (theme-aware: black/white)
  - Custom heading: "Service provided by Red Hat Demo Platform"
  - Red Hat favicon
  - Branded footer with Copyright, Privacy/Terms links, GitHub credit
  - Smooth fade-in animations (zero flash of unstyled content)
  - Only applies when `ocp4_workload_litemaas_branding_enabled=true`
  - Implemented via init container modifying frontend files directly
  - Branding variables:
    - `ocp4_workload_litemaas_branding_enabled` (default: false)
    - `ocp4_workload_litemaas_branding_service_text` (default: "Service provided by Red Hat Demo Platform")
    - `ocp4_workload_litemaas_branding_enable_footer` (default: true)
    - Optional custom logo/favicon paths (uses bundled RHDP assets by default)

### Changed
- Branding only applies to HA deployments (`deploy_litemaas_ha.yml`)
- Single-user and multi-user deployments remain unchanged
- Logo files moved to `roles/ocp4_workload_litemaas/files/`

### Technical Details
- Init container injects CSS and JavaScript into index.html before frontend starts
- CSS preloaded in `<head>` to prevent flash of original content
- JavaScript handles:
  - Logo replacement (theme-aware)
  - Favicon replacement with cache-busting
  - Page title and heading replacement
  - Footer injection and original footer removal
  - MutationObserver for React SPA compatibility
- Nginx sidecar approach removed in favor of direct file modification

## [0.3.0] - 2025-01-15

### Added
- High Availability deployment support
- Redis caching for HA mode
- PostgreSQL 16 support
- Storage class auto-detection for CNV/ODF environments
- Frontend and Backend components for OAuth-enabled deployments

### Changed
- Improved OAuth configuration handling
- Better error messages for missing variables
- Enhanced multi-user deployment stability

### Fixed
- Storage class detection on baremetal/CNV clusters
- OAuth redirect URI handling for multi-user deployments
- PostgreSQL image fallback mechanism

## [0.2.0] - 2024-12-10

### Added
- Multi-user deployment mode
- Support for up to 80 concurrent users
- Per-user namespace isolation
- Shared OAuthClient for simplified OAuth setup

### Changed
- Improved resource allocation for multi-user scenarios
- Better PostgreSQL version handling

### Fixed
- User credential generation
- Namespace cleanup on removal

## [0.1.0] - 2024-11-20

### Added
- Initial release
- Single-instance LiteLLM deployment
- Basic PostgreSQL support
- OpenShift OAuth integration
- AgnosticD workload role structure

[0.4.0]: https://github.com/rhpds/rhpds.litemaas/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rhpds/rhpds.litemaas/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rhpds/rhpds.litemaas/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rhpds/rhpds.litemaas/releases/tag/v0.1.0
