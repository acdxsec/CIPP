# CIPP automated-onboarding trigger and observability contract

Research date: 2026-09-04

Scope: current CIPP frontend at `dccb09f489f5325025e4187ce079583afa65de07`, current CIPP-API at `df3738d6e60d417f912c1842d9c64f985ae348f8`, and Microsoft's Partner Center webhook documentation. This note describes the existing contract and the seams a GDAP acceptance launcher can safely use; it does not prescribe the companion's authentication implementation.

## Executive result

CIPP already has a coherent correlation key and post-acceptance execution path: the Partner Center `granular-admin-relationship-approved` event is enriched from its audit record, the audit object's GDAP relationship `Id` becomes the `TenantOnboarding` row key, and the same ID drives the onboarding worker and frontend status lookup. The launcher should therefore pass and retain only the relationship ID and return the operator to `/tenant/gdap-management/onboarding/start?id=<relationship-id>`.

What CIPP does **not** currently have is a single, durable “automated onboarding is ready” result or webhook-to-job reconciliation endpoint. Readiness is distributed across configuration, Partner Center registration, URL comparison, and a transient validation-event test. A reliable **Accept and onboard** action needs a small backend-owned readiness contract and a relationship-keyed status/reconcile contract rather than duplicating those judgments in React.

## Existing flow

1. Saving **Automated Onboarding** invokes `ExecPartnerWebhook?Action=CreateSubscription`. The backend chooses the instance hostname, registers a Partner Center callback, and stores `PartnerWebhookOnboarding.Enabled` plus the standards-exclusion preference. The subscription builder always adds `test-created` and `granular-admin-relationship-approved`; optional UI event types are additive. Leaving the optional event selector empty is valid and produces exactly the required events. [Create/list endpoint](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPHTTP/Public/Entrypoints/HTTP%20Functions/CIPP/Core/Invoke-ExecPartnerWebhook.ps1#L14-L90), [subscription construction](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPCore/Public/Webhooks/New-CIPPGraphSubscription.ps1#L19-L101)
2. Partner Center POSTs the event to CIPP's public callback. CIPP authorizes the route by looking up the `CIPPID` embedded in the registered URL, stores the body in `WebhookIncoming`, and later dispatches records of type `PartnerCenter` to `Invoke-CippPartnerWebhookProcessing`. [Public intake](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPHTTP/Public/Entrypoints/HTTP%20Functions/Tenant/Administration/Alerts/Invoke-PublicWebhooks.ps1), [dispatcher](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPActivityTriggers/Public/Entrypoints/Activity%20Triggers/Webhooks/Push-PublicWebhookProcess.ps1)
3. For `granular-admin-relationship-approved`, CIPP fetches the event's `AuditUri` only when it is an HTTPS URL on `api.partnercenter.microsoft.com`. It parses `resourceNewValue`, takes `AuditObj.Id`, creates a queued `TenantOnboarding` row keyed by that ID, and starts the worker only when `PartnerWebhookOnboarding.Enabled` is true. An approval event without a retrievable `resourceNewValue` is logged but does not start onboarding. [Webhook processor](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPCore/Public/Webhooks/Invoke-CIPPPartnerWebhookProcessing.ps1#L7-L101)
4. The worker changes the row from `queued` to `running`, fetches the Graph relationship by the same ID, polls until its status is `active`, and then runs role validation, access-assignment mapping, CPV refresh, and an API-access test. It persists step states, messages, relationship data, logs, customer ID, exception, and overall status into the same table row. [Onboarding worker](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPActivityTriggers/Public/Entrypoints/Activity%20Triggers/Push-ExecOnboardTenantQueue.ps1)
5. `ListTenantOnboarding` returns all rows, deserializing their steps, relationship, and logs. `ExecOnboardTenant` supports relationship-ID lookup, manual start/status polling, forced retry, and cancellation. The frontend table exposes status, steps, logs, retry, and cancel; the start page accepts `?id=`, finds the relationship and matching onboarding row by ID, and polls `ExecOnboardTenant` every five seconds while a job is active. [List endpoint](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPHTTP/Public/Entrypoints/HTTP%20Functions/Tenant/Administration/Tenant/Invoke-ListTenantOnboarding.ps1), [execute/status endpoint](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPHTTP/Public/Entrypoints/HTTP%20Functions/Tenant/Administration/Tenant/Invoke-ExecOnboardTenant.ps1), [onboarding table](https://github.com/acdxsec/CIPP/blob/dccb09f489f5325025e4187ce079583afa65de07/src/pages/tenant/gdap-management/onboarding/index.js), [start/status page](https://github.com/acdxsec/CIPP/blob/dccb09f489f5325025e4187ce079583afa65de07/src/pages/tenant/gdap-management/onboarding/start.js)

Microsoft defines `granular-admin-relationship-approved` as the event raised when the customer tenant approves GDAP. Its event model includes `EventName`, `ResourceUri`, `ResourceName`, optional `AuditUri`, and the resource-change timestamp. Partner Center sends events to one registered webhook URL and documents digital signing for validating callbacks. [Partner Center webhooks](https://learn.microsoft.com/en-us/partner-center/developer/partner-center-webhooks), [event definitions](https://learn.microsoft.com/en-us/partner-center/developer/partner-center-webhook-events)

## Readiness: what can be known today

The frontend can currently derive these independent facts from `ListSubscription`:

- whether CIPP's `PartnerWebhookOnboarding` setting is enabled;
- whether Partner Center returned a registration and which events it contains;
- whether the registered URL differs, case-insensitively, from the URL CIPP would register for the current instance;
- which custom hostname CIPP selected.

It can also request a Partner Center validation event and poll its correlation ID until `completed` or `failed`. That result is held only in component state; the backend does not persist a last-success time or combine these facts into readiness. [Settings UI](https://github.com/acdxsec/CIPP/blob/dccb09f489f5325025e4187ce079583afa65de07/src/pages/cipp/settings/partner-webhooks.js), [settings API](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPHTTP/Public/Entrypoints/HTTP%20Functions/CIPP/Core/Invoke-ExecPartnerWebhook.ps1#L14-L90)

Consequently, the proposed action cannot honestly promise readiness from `enabled` alone. The backend should own a new read-only readiness response with at least:

- `enabled`: stored CIPP switch is true;
- `registered`: Partner Center registration exists;
- `requiredEventsPresent`: `test-created` and `granular-admin-relationship-approved` are registered;
- `webhookUrlCurrent`: registered and expected URLs match;
- `lastValidationStatus` and `lastValidationAt`: persisted result of the most recent delivery test, with an explicit freshness policy;
- `ready`: a backend-computed result plus machine-readable reasons and a repair URL.

The frontend should consume that result immediately before launching the companion. React should render the explanation and repair link, but should not independently define readiness.

## Correlation and observability

The GDAP relationship ID is already the canonical key across:

- `GDAPInvites.RowKey` and the current custom protocol action;
- Partner Center audit `resourceNewValue.Id`;
- `TenantOnboarding.RowKey`;
- worker Graph requests and logs;
- manual onboarding deep-link selection and status lookup.

No second correlation identifier is needed for acceptance-to-onboarding. Partner Center validation-event correlation IDs are test-delivery identifiers only and should not be reused for GDAP jobs.

The current observable lifecycle is `queued` → `running` → `succeeded` or `failed`, augmented by five step objects and timestamped logs. The existing onboarding table is the correct operator destination after local acceptance. A safe handoff URL is `/tenant/gdap-management/onboarding/start?id=<relationship-id>`; it already recognizes active or approval-pending relationships and finds the matching onboarding row. The custom invitation table currently launches the protocol with `RowKey`, but does not perform readiness checking or provide a handoff acknowledgement. [Invite action](https://github.com/acdxsec/CIPP/blob/dccb09f489f5325025e4187ce079583afa65de07/src/pages/tenant/gdap-management/invites/index.js), [start/status page](https://github.com/acdxsec/CIPP/blob/dccb09f489f5325025e4187ce079583afa65de07/src/pages/tenant/gdap-management/onboarding/start.js)

### Status caveat

The worker currently sets overall `TenantOnboarding.Status` to `succeeded` when the final Graph API test fails, even while marking Step 5 `failed` and emitting an error log. Consumers must inspect both overall status and step status until that inconsistency is fixed; a reconciliation API must not treat overall `succeeded` alone as proof that every step succeeded. [Worker final status](https://github.com/KelvinTegelaar/CIPP-API/blob/df3738d6e60d417f912c1842d9c64f985ae348f8/Modules/CIPPActivityTriggers/Public/Entrypoints/Activity%20Triggers/Push-ExecOnboardTenantQueue.ps1#L561-L598)

## Idempotency and reconciliation gaps

- Webhook processing force-writes a fresh queued row and directly invokes the worker for every qualifying event. There is no check for an existing running or completed relationship row, so duplicate deliveries can overwrite status and restart work.
- Manual start suppresses a new job only when an onboarding row is newer than ten minutes; `Retry` bypasses that guard. This is a time-window policy, not a durable idempotency guarantee.
- If automated onboarding is disabled when the approval arrives, CIPP logs the fact but creates no onboarding row. Enabling it later does not reconcile that relationship automatically in the inspected path.
- If the event has no usable audit `resourceNewValue`, CIPP logs it but creates no row. The processor does not fall back to extracting the relationship ID from `ResourceUri` or querying the relationship directly.
- There is no endpoint whose meaning is “for this accepted relationship, report whether its approval webhook was observed; if absent and the relationship is active, enqueue it exactly once.” The existing retry endpoint can be driven manually but also starts/status-polls work and does not distinguish webhook receipt from reconciliation.

The backend should therefore expose a relationship-keyed status/reconcile operation. Its write side should atomically create a job only when no active/successful job exists, preserve completed history rather than resetting it on duplicate events, and record trigger provenance (`partner-webhook`, `manual`, or `reconciliation`). The companion should **not** call this endpoint: after acceptance it should open the trusted CIPP handoff page. CIPP remains responsible for detecting delayed/missed webhooks and offering an authorized reconciliation action.

## Ownership boundary

### CIPP frontend

- Show **Accept and onboard** in creation results and the invites table.
- Ask the backend for readiness immediately before launch; block and link to settings when not ready.
- Launch only the versioned relationship-ID URI contract.
- After the companion returns via the trusted configured base URL, display the relationship-keyed onboarding state and delayed-webhook/reconcile affordance.
- Reuse the current onboarding status components rather than inventing another task UI.

### CIPP backend / CIPP-API

- Own the authoritative readiness calculation and persisted validation-test result.
- Continue owning webhook registration, intake, audit enrichment, onboarding queueing, task state, logs, retry, and cancellation.
- Add durable duplicate suppression and the relationship-keyed status/reconcile contract.
- Fix or explicitly model the Step 5/overall-status inconsistency.
- Consider validating Partner Center's documented webhook signature in addition to the current CIPPID registration lookup; this is a security-hardening gap visible in the inspected public intake path, though it is not required merely to wire the launcher.

### Desktop companion

- Own interactive customer authentication, tenant/relationship confirmation, and acceptance.
- Treat the relationship ID as the only cross-system correlation key.
- Open the installer-configured, allowlisted CIPP base URL at the onboarding handoff route after the relationship becomes active.
- Never claim that CIPP observed the webhook or started onboarding; only CIPP's relationship-keyed status can make that assertion.

## Implementation decisions unblocked by this research

1. Keep the event-driven boundary: local acceptance does not directly start onboarding.
2. Use the GDAP relationship ID everywhere; no new journey ID is needed.
3. Define “journey complete” for the launcher as CIPP showing a `TenantOnboarding` row in `queued` or `running` state for that relationship. Later step failures remain CIPP's existing responsibility.
4. Add backend readiness and reconciliation seams before presenting **Accept and onboard** as guaranteed behavior.
5. Deep-link the companion back to CIPP's existing onboarding start/status page, initially with `?id=<relationship-id>`; a dedicated status route can be added only if UX prototyping shows it is necessary.

## Open implementation questions

- What validation-test freshness window should make `ready` true? Current behavior supplies no persisted evidence from which to infer one.
- Should a missed-event reconciliation be automatic after the handoff timeout, operator-triggered, or both? The idempotent backend primitive should support either policy.
- Should onboarding history become append-only/multi-attempt, or should CIPP retain its current one-row-per-relationship model with separate attempt metadata? Duplicate delivery safety requires this to be decided before backend implementation.
