# Custom CIPP image — development candidate

This fork builds both the frontend and an owned PowerShell API overlay. The
official Craft executable remains unchanged. The base image is pinned by digest;
`backend/Build-Overlay.ps1` also checks module hashes and export layout. Unsupported
upstream changes fail the build. Yarn installs use the committed frozen lockfile.

The custom frontend adds an **Accept and onboard** action to each GDAP invite.
It checks backend readiness before launching
`gdap-acceptor://v1/accept/<instance-id>/<relationship-id>`. The independent
`acdxsec/GDAP-Acceptor` companion bundles the reviewed portal adapter; no separate
M365Internals installation is required. Instance enrollment is explicit and the
expected customer tenant is entered locally before authentication.

## Original-body host integration

Craft's marshaler still discards original bytes. The image now includes a small
ASP.NET Core hosting-startup module that captures them before parsing and hands
them to PowerShell through single-use in-process handles. `Craft.dll` is unchanged;
no separate proxy or service is required. See `backend/hosting/README.md`.

The actual Craft startup smoke test and an HTTP-to-Craft-to-PowerShell signature
test pass locally. The latter uses a synthetic certificate, not Microsoft's PKI.
Readiness requires the installed module and a new signed test-delivery receipt.
Missing capture while enabled rejects callbacks; explicitly disabled retains
legacy upstream behavior. Do not deploy as production-ready: live portal/Partner
Center evidence, safe recovery, signed installers and desktop validation remain.

See `docs/GDAP-IMPLEMENTATION-STATUS.md` for all outstanding release work.

## Publish

CI builds candidates without publishing. Explicit workflow publication is blocked
while `.github/GDAP_RELEASE_READY` is absent. Add that marker only after all release
gates have passed review. Approved publication uses:

```text
ghcr.io/acdxsec/cipp-custom:<cipp-version>-<workflow-run-number>-<run-attempt>
ghcr.io/acdxsec/cipp-custom:edge
```

Tags remain mutable. Deploy by `ghcr.io/acdxsec/cipp-custom@sha256:...` in Azure
App Service. The package must be public or Azure must have GHCR credentials.
This implementation has not changed Azure or published a production image.

## Upgrade

When updating from upstream CIPP:

1. Merge the new upstream release.
2. Confirm `public/version.json` matches the intended official base image.
3. Pull that official image and resolve its linux/amd64 digest.
4. Review the base digest, module hashes, request and caching contracts together.
5. Run backend, frontend, live integration, and companion tests before promotion.

Do not point production at `edge`; retain the previous digest and configuration
backup for rollback. Preserve the upstream licenses in all releases.
