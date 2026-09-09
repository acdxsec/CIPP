# GDAP acceptance implementation status — 2026-09-09

This is a development candidate, not a completed production journey. User approval
to implement supersedes the earlier Wayfinder map's planning-only scope; it does
not authorize deploying into Azure. No tenant approval has been performed.

## Implemented and checked locally

- Opaque composite invitation IDs remain intact across CIPP, native launcher, and
  portal adapter. URI input cannot choose a script, command, or callback origin.
- Trusted CIPP instances are enrolled locally with HTTPS origin and partner UUID.
  Expected customer UUID is entered before authentication, not inferred from the
  account that happens to sign in. The URI itself is not authenticated origin proof.
- Approval defaults to fresh private authentication, checks tenant and partner,
  displays roles/duration/extension, rechecks after consent, and never retries an
  ambiguous approval POST. Active relationships return; approved/activating resume
  observation. Missing evidence fails closed. Synthetic tests cover these paths.
- The independent native companion serializes per-user requests, bounds queue age
  and size, bundles pinned M365Internals sources, and exports sanitized diagnostics.
  A console workflow is implemented; a richer TUI has not been usability-tested.
- CIPP readiness binds delivery-validation evidence to the exact registration.
  Tests cover changed/stale configuration. Delivery success is not proof of a
  working approval-to-onboarding chain.
- Read-only, exact-ID status polling starts on navigation and stops after three
  minutes or proven start. Queued is not started; running, succeeded, and failed
  indicate the worker started. React tests cover polling and completed state.
- Atomic webhook dispatch claims suppress duplicates and expose orphan claims.
- Backend overlay and full custom-image build passed against the pinned base.
  The final source also uses a frozen lockfile and build-time React tests.
- Production publishing is disabled until explicit promotion and release review.
- Original bytes now cross the Craft-to-PowerShell seam through an in-process
  ASP.NET hosting-startup module, without replacing Craft or adding a service.
  Signed/tampered HTTP tests use the actual pinned Craft marshaller and PowerShell.
  A network-isolated boot of the real Craft entrypoint also passes capture guards.
- Readiness rejects legacy delivery tests without a matching signed receipt.
- Companion assembly and contract checks passed Windows/Linux CI; the initial
  CIPP draft image build passed CI. These are not target-desktop lifecycle tests.

## Open gates — do not close the map or release ticket

1. **Live webhook validation.** The original-body transport blocker is resolved in
   the development image using a hosting-startup extension. The HTTP integration
   check uses a synthetic certificate; verify the complete Microsoft certificate
   chain/revocation path and actual signed Partner Center test-event ResourceUri
   in a lab. Readiness requires fresh correlated signed-receipt evidence. Craft's
   source repository is no longer required for this implementation path.
2. **Portal evidence.** The strict v1 partner/customer/role/duration/ETag adapter
   requires sanitized live fixtures. Synthetic shapes are not proof of Microsoft's
   current undocumented API. Exercise wrong tenant, generic/customer-bound invites,
   identity changes, cancellation, ambiguity, and active/activating transitions.
3. **Recovery.** A claim created before a crashed dispatch is deliberately not
   expired automatically. A unified authorized recovery contract and concurrency
   tests spanning webhook and existing manual controls remain unimplemented.
4. **Native installation.** Windows development registration and Debian templates
   are not signed installers. Build/test a **per-user** Windows MSI and scoped signed
   APT repository; test installation, upgrade, removal and multi-user isolation on
   Windows 11 and Kubuntu 26.04. The earlier per-machine research suggestion is not
   the approved product choice. Managed signing identities are not configured.
5. **Browser and lifecycle.** Test CA, PIM, passkeys/MFA, managed-browser policies,
   profile cleanup after cancellation/crash, native activation from real browsers,
   default-browser return, and terminal lifetime on both desktops.
6. **Release UX.** Signed update notification and one tested recovery runbook are
   outstanding. The current releases link has no production installer behind it.
7. **End-to-end trial.** An authorized partner/customer lab must prove approval to
   actual CIPP worker start. Keep downstream CIPP task/failure ownership unchanged.

## Verification commands

```sh
node --test tests/gdap-acceptance.node.test.mjs
pwsh -NoProfile -File backend/Test-Overlay.ps1
docker build -f Dockerfile.custom -t cipp-gdap:development .
# In GDAP-Acceptor:
dotnet run --project src -- self-test
pwsh -NoProfile -File tests/functions/Approve-GdapRelationship.Checks.ps1
```

Microsoft's [webhook authentication contract](https://learn.microsoft.com/en-us/partner-center/developer/partner-center-webhooks)
requires verifying the signature over the request content before processing it.
The unsupported `granular-admin-relationship-created` subscription event is not
reintroduced by this implementation. Check the service's supported-event list
when registering; readiness requires approval and test-delivery notifications.
