# Missing GDAP onboarding dispatch

Development runbook; lab validation is still required before production use.
Acceptance, activation, dispatch and worker start are different observations.
Never repeat an ambiguous Microsoft approval POST to repair CIPP onboarding.

## Observe first

1. Open the read-only acceptance status page for the exact relationship ID.
   Preserve the full ID, including composite identifiers. Record customer tenant,
   timestamps, CIPP task/log references and the reported state; exclude tokens.
2. If status is `queued`, work exists but has not started. Inspect CIPP worker
   health and queue processing. Do not clear the row or use retry/cancel to
   manufacture a new first start. Old queued rows remain existing work.
3. If running, succeeded or failed, the worker has started. Use CIPP's existing
   downstream task/log and failure handling; the acceptance journey is finished.
4. If no work exists, verify the relationship is active in the partner tenant.
   Investigate webhook registration, signed delivery and worker health separately.

## Recover a missing first dispatch

The status page links to **Recover missing onboarding dispatch**. An operator
with `Tenant.Administration.ReadWrite` must enter the independently known customer
tenant UUID and explicitly confirm. Navigation and status polling do not mutate.

The recovery endpoint accepts POST only, verifies the active relationship and
customer against a fresh partner-scoped Graph read, and uses the same atomic
reservation as webhook and manual first-start requests. It does not accept GDAP.
Automated onboarding and the development feature must both be enabled.

- Existing job: return the stored observation unchanged, without dispatching.
- No job or reservation: reserve once and request upstream CIPP dispatch.
- Reservation but no job: return conflict; do not dispatch or expire the claim.
- Error/timeout: outcome is unconfirmed. Observe again before another request.

A successful response is not proof of worker start. Follow the read-only status
link and confirm running/succeeded/failed. CIPP continues to own downstream work.

## An orphan reservation requires a maintenance decision

There is deliberately no reset button or automatic timeout. An old claimant may
still resume; deleting its reservation while it can execute permits duplicates.

For `dispatchNeedsReview`, stop here and involve the CIPP infrastructure owner.
Before considering a storage repair they must establish a maintenance window,
quiesce **all** webhook/manual/recovery producers and all possible old workers,
inspect durable queues/tasks/logs plus the exact onboarding row, and prove no
pending execution can resume. Preserve the claim and its ETag as evidence.
If that cannot be proven, do not remove anything.

Any repair needs a separately approved, exact-row conditional storage operation
and a rollback plan; this runbook does not authorize a blind table deletion.
After a verified repair and restored service, use the identity-bound recovery
screen once and observe actual worker start. Validate this operational procedure
in the lab before treating orphan recovery as a closed release gate.
