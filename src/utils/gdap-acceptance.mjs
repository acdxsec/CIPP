const identifier = /^[A-Za-z0-9][A-Za-z0-9_-]{0,255}$/;
const guid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function validRelationshipId(value) {
  return typeof value === 'string' && identifier.test(value);
}

export function acceptanceUri(instanceId, relationshipId) {
  if (!guid.test(instanceId) || /^0{8}-0{4}-0{4}-0{4}-0{12}$/.test(instanceId)) {
    throw new Error('Invalid CIPP instance identity');
  }
  if (!validRelationshipId(relationshipId)) throw new Error('Invalid relationship identity');
  return `gdap-acceptor://v1/accept/${instanceId.toLowerCase()}/${encodeURIComponent(relationshipId)}`;
}

export function hasOnboardingStarted(result) {
  return result?.contractVersion === 1 && result?.onboardingStarted === true &&
    ['running', 'succeeded', 'failed'].includes(result.status);
}

export function readinessAllowsLaunch(result) {
  return result?.contractVersion === 1 && result?.ready === true &&
    Array.isArray(result.reasons) && result.reasons.length === 0;
}
