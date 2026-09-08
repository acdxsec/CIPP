import test from 'node:test';
import assert from 'node:assert/strict';
import { acceptanceUri, hasOnboardingStarted, readinessAllowsLaunch } from '../src/utils/gdap-acceptance.mjs';

test('composite opaque identities survive the URI contract', () => {
  const id = '5d027261-d21f-4aa9-b7db-7fa1f56fb163-8777b240-c6f0-4469-9e98-a3205431b836';
  assert.equal(acceptanceUri('11111111-1111-1111-1111-111111111111', id), `gdap-acceptor://v1/accept/11111111-1111-1111-1111-111111111111/${id}`);
});
test('reject ambiguous or injected identities', () => {
  for (const id of ['../id', 'id?command=x', 'id#x', 'a%2fb', 'id\n', 'a'.repeat(257)]) {
    assert.throws(() => acceptanceUri('11111111-1111-1111-1111-111111111111', id));
  }
  assert.throws(() => acceptanceUri('00000000-0000-0000-0000-000000000000', 'id'));
});
test('completed attempts prove start; queued or unversioned data does not', () => {
  for (const status of ['running', 'succeeded', 'failed']) assert.equal(hasOnboardingStarted({ contractVersion: 1, status, onboardingStarted: true }), true);
  assert.equal(hasOnboardingStarted({ contractVersion: 1, status: 'queued', onboardingStarted: true }), false);
  assert.equal(hasOnboardingStarted({ status: 'running', onboardingStarted: true }), false);
});
test('launch fails closed on stale or incompatible readiness', () => {
  assert.equal(readinessAllowsLaunch({ contractVersion: 1, ready: true, reasons: [] }), true);
  for (const value of [null, {}, { ready: true }, { contractVersion: 2, ready: true, reasons: [] }, { contractVersion: 1, ready: true, reasons: ['stale'] }]) assert.equal(readinessAllowsLaunch(value), false);
});
