# GDAP acceptance and authentication contract

Research question: What Microsoft-supported and observed contracts can the companion rely on to authenticate the intended customer tenant, inspect a pending GDAP relationship, approve it, and determine that it is active—and which parts remain undocumented compatibility risks requiring a fail-closed fallback?

## Decision summary

The companion can support an interactive, customer-authorized workflow, but it cannot describe its programmatic acceptance step as a Microsoft-supported API integration.

- Microsoft supports sending the customer the Microsoft 365 admin-center invitation URL and having a **Global Administrator** approve all requested roles there. This is the authoritative fallback.
- Microsoft Entra supports tenant-scoped interactive sign-in and `prompt=select_account`. The companion should use both, then independently prove that the authenticated portal tenant equals the relationship's customer tenant before enabling approval.
- Microsoft Graph provides the supported relationship schema and lifecycle states. It is suitable for partner-side preflight/correlation when CIPP's existing credentials have the documented permissions. It does **not** document a customer-side approval API: Graph's `approve` request action is specifically for an **indirect reseller** approving a relationship created by an indirect provider.
- The existing M365Internals prototype demonstrates a workable but undocumented Microsoft 365 admin-center contract: read an invitation from `/fd/commerceMgmt2/.../gdapInvitations/...`, obtain its `etag`, POST `{status:"approved"}` with `If-Match` to `/fd/GdapPartnerManage/.../UpdateStatus`, then poll the invitation resource. All `/fd/` paths, response shapes, cookies, and headers are compatibility risks and must fail closed.
- A relationship is complete for this workflow only at documented status `active`, not at `approved` or `activating`. Unknown or terminal states must stop the flow.
- Treat the relationship identifier as an opaque invitation path segment, not a single GUID. Microsoft's documented invitation example uses two GUIDs joined with a hyphen. The current prototype's “first GUID anywhere” parser can truncate that documented form and must not become the companion contract.

## Supported contracts

### Invitation and customer authority

Microsoft documents this invitation form:

```text
https://admin.microsoft.com/AdminPortal/Home#/partners/invitation/granularAdminRelationships/{adminRelationshipID}
```

The Graph GDAP overview says the partner builds and sends that link after locking the relationship for approval. Its example `adminRelationshipID` is a composite value containing two GUIDs separated by a hyphen, so consumers must not assume a 36-character GUID ([Microsoft Graph GDAP API overview](https://learn.microsoft.com/en-us/graph/api/resources/delegatedadminrelationships-api-overview?view=graph-rest-beta)).

Microsoft's customer-approval procedure requires the customer to open the invitation link and select **Approve all** in Microsoft 365 admin center; the documented appropriate role is **Global admin** ([Customer approval of partner GDAP request](https://learn.microsoft.com/en-us/partner-center/customers/gdap-customer-approval)). This UI procedure is the only Microsoft-documented customer acceptance contract found in the reviewed sources.

### Authentication to the intended tenant

Microsoft Entra documents that a tenant identifier in the authorization endpoint controls the directory into which the user signs in; for a guest scenario, the resource tenant identifier must be supplied. It also documents that `prompt=select_account` interrupts SSO and lets the user choose a remembered or different account ([OAuth 2.0 authorization code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow)).

Account selection is a user-experience control, not proof of tenant. Microsoft defines `tid` as the immutable tenant in which the user is signing in and recommends considering it with other claims; issuer and audience must also be validated when an application validates its own tokens ([Access-token claims reference](https://learn.microsoft.com/en-us/entra/identity-platform/access-token-claims-reference), [Access tokens in the Microsoft identity platform](https://learn.microsoft.com/en-us/entra/identity-platform/access-tokens)). Because the prototype captures artifacts for Microsoft-owned services rather than tokens issued to the companion, the companion must not parse a Microsoft-owned access token as its trust decision. It should instead use the authenticated admin-portal context returned by the portal and compare its resolved tenant ID to the customer tenant returned for the invitation.

Consequently, the acceptance gate is:

1. Launch an ephemeral interactive session with account selection forced. Scope it to the expected tenant only when that tenant was obtained through a separately trusted partner-side preflight; the relationship ID alone does not contain it.
2. Resolve the active Microsoft 365 admin-portal tenant after sign-in.
3. Read the invitation through the authenticated customer portal session and obtain its customer tenant ID, customer display name, partner display name, roles, canonical relationship ID, and status.
4. Require exact, case-insensitive equality of canonical GUID tenant IDs. Display the verified tenant/customer and requested roles for explicit confirmation.
5. Refuse approval if the tenant cannot be resolved, differs, or changes before the write.

The explicit comparison is essential: tenant-scoping and `login_hint` guide sign-in but do not replace post-authentication verification.

### Relationship inspection and lifecycle

Microsoft Graph v1.0 supports:

```http
GET /tenantRelationships/delegatedAdminRelationships/{delegatedAdminRelationshipId}
```

The documented least-privileged permission is `DelegatedAdminRelationship.Read.All` for delegated or application access, and the returned object includes customer tenant/display name, requested role IDs, status, dates, and an OData ETag ([Get delegatedAdminRelationship](https://learn.microsoft.com/en-us/graph/api/delegatedadminrelationship-get?view=graph-rest-1.0)). This is a partner-side relationship API; it should be used by CIPP for preflight/correlation rather than assumed callable using the customer's admin-center session.

The documented state machine is:

- `created`: partner can still modify the relationship.
- `approvalPending`: partner finalized it for customer approval.
- `approved`: customer approved it.
- `activating`: Microsoft is provisioning it.
- `active`: provisioning is complete.
- `terminationRequested`, `terminating`, `terminated`, `expiring`, and `expired`: not approvable/success states.
- `unknownFutureValue`: an evolvable-enum sentinel and not a success state.

These meanings come from the v1.0 [`delegatedAdminRelationship` resource](https://learn.microsoft.com/en-us/graph/api/resources/delegatedadminrelationship?view=graph-rest-1.0). The companion may treat `approved` and `activating` as bounded polling states, but must report success only for `active`. It should treat `active` at initial inspection as idempotent success; all other unrecognized or terminal states stop without a write.

Graph relationship requests do not supply the missing customer-approval operation. The documented `approve` action is explicitly for an **indirect reseller** approving an indirect-provider-created relationship in `approvalPending`; it is not documented as customer approval ([delegatedAdminRelationshipRequest resource](https://learn.microsoft.com/en-us/graph/api/resources/delegatedadminrelationshiprequest?view=graph-rest-1.0)).

## Observed M365 admin-center contract

At M365Internals baseline commit `21e8728b9491eda1c13e1e05ce03678ca75d64cc`, the local prototype performs these calls:

```http
GET /fd/commerceMgmt2/partnermanage/gdapInvitations/{relationshipId}?api-version=3.0

POST /fd/GdapPartnerManage/CustomerServiceAdminApi/Web/v1/GranularAdminRelationships/{relationshipId}/UpdateStatus
If-Match: {relationship.etag}
x-adminapp-request: /partners/invitation/granularAdminRelationships/{relationshipId}
Content-Type: application/json

{"status":"approved"}
```

It permits the write only when the GET returns `relationship.status == "approvalPending"` and a nonempty `relationship.etag`, then polls the same GET until `active`. During polling it accepts only `approvalPending` or `approved` as transient states; anything else fails (direct inspection of `/home/fizlian/Documents/M365Internals/scripts/Approve-GdapRelationship.ps1`, an uncommitted local prototype on the stated baseline).

The authentication implementation demonstrates further observed behavior:

- It derives the Entra login URL from `admin.cloud.microsoft`, replaces `common`/`organizations` with an optional tenant ID, and appends `prompt=select_account` when no username is supplied.
- Its private mode creates a temporary browser profile and removes it on exit.
- It uses Chromium DevTools Protocol to read Microsoft 365 admin-center cookies into an in-memory PowerShell web session.
- It resolves the active tenant from `s.UserTenantId` or validated portal bootstrap responses.

These are directly inspected behaviors in [`Connect-M365PortalByBrowser.ps1`](https://github.com/MSCloudInternals/M365Internals/blob/21e8728b9491eda1c13e1e05ce03678ca75d64cc/M365Internals/functions/Connect-M365PortalByBrowser.ps1), [`Get-M365AdminLoginState.ps1`](https://github.com/MSCloudInternals/M365Internals/blob/21e8728b9491eda1c13e1e05ce03678ca75d64cc/M365Internals/internal/functions/Get-M365AdminLoginState.ps1), [`Invoke-M365BrowserAuthentication.ps1`](https://github.com/MSCloudInternals/M365Internals/blob/21e8728b9491eda1c13e1e05ce03678ca75d64cc/M365Internals/internal/functions/Invoke-M365BrowserAuthentication.ps1), and [`Set-M365PortalConnectionSettings.ps1`](https://github.com/MSCloudInternals/M365Internals/blob/21e8728b9491eda1c13e1e05ce03678ca75d64cc/M365Internals/internal/functions/Set-M365PortalConnectionSettings.ps1) at the same M365Internals baseline. They are useful implementation evidence, not Microsoft API commitments. Notably, the existing approval script passes `TenantId` into sign-in but does not itself compare the resolved connection tenant to an expected tenant; the companion must add that gate.

## Fail-closed compatibility policy

Every element below is undocumented and must be isolated behind a versioned adapter:

- `/fd/commerceMgmt2` and `/fd/GdapPartnerManage` routes and API-version value.
- Admin-center cookie names, availability, domain, and semantics.
- Chromium DevTools cookie capture and admin-center bootstrap behavior.
- Invitation JSON shape, field casing, role/partner/customer fields, and embedded `etag` location.
- `UpdateStatus` method, body, `If-Match`, and `x-adminapp-request` behavior.
- The observed transient sequence and timing of portal responses.

The adapter must stop before mutation unless all of these hold:

- Identifier is a single safely encoded path segment matching the invitation's returned canonical ID exactly; reject traversal, separators, query/fragment characters, control characters, and truncation.
- HTTP response and JSON media type are expected; response is not an HTML sign-in/error shell.
- Required relationship, customer, partner, roles, status, and ETag fields exist and pass strict type/shape checks.
- Authenticated portal tenant exactly matches the returned customer tenant immediately before confirmation and again before POST.
- Status is exactly `approvalPending` (or exactly `active`, which returns without writing).
- The ETag used for POST is the one just read; `412 Precondition Failed` causes a fresh inspection and confirmation decision, never a blind retry.

After POST, poll with a bounded timeout and backoff. Accept `approved` and `activating` as nonterminal documented states in addition to the prototype-observed `approvalPending`. Report success only on `active`. Do not issue another POST on timeout, network ambiguity, HTML, schema drift, `unknownFutureValue`, or any unexpected status. Sanitize logs: record relationship ID, verified tenant ID/display name, state transitions, status codes, and correlation timestamps, but never cookies, tokens, ETags, request headers, or response bodies that may contain authentication material.

## Fallback and release implication

On any compatibility failure, open or display the exact Microsoft-documented invitation URL and instruct the authorized customer Global Administrator to complete **Approve all** in Microsoft 365 admin center. Preserve the relationship ID so CIPP can correlate and observe the normal approved-relationship webhook/onboarding path. The fallback must not synthesize another acceptance request.

Production readiness therefore requires a live compatibility test against the undocumented adapter on both supported desktop platforms and an emergency switch that disables programmatic POST while retaining the documented invitation fallback. The UI and documentation should label the automation as dependent on an observed Microsoft 365 admin-center implementation, not a supported Graph acceptance API.
