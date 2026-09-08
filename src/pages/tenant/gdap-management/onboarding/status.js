import { useEffect, useState } from 'react';
import { useRouter } from 'next/router';
import { Alert, Button, CardContent, Stack, Typography } from '@mui/material';
import { Layout as DashboardLayout } from '../../../../layouts/index.js';
import CippPageCard from '../../../../components/CippCards/CippPageCard';
import { ApiGetCall } from '../../../../api/ApiCall';
import { hasOnboardingStarted, validRelationshipId } from '../../../../utils/gdap-acceptance.mjs';

const Page = () => {
  const { query } = useRouter();
  const id = query.id;
  const [expired, setExpired] = useState(false);
  const status = ApiGetCall({
    url: '/api/ListGdapAcceptanceStatus', queryKey: `GdapAcceptanceStatus-${id}`,
    data: { id, tenantFilter: 'AllTenants' }, waiting: validRelationshipId(id), retry: 0,
    staleTime: 0,
  });
  const started = !status.isError && hasOnboardingStarted(status.data);
  useEffect(() => {
    setExpired(false);
    if (!validRelationshipId(id) || started) return;
    const poll = setInterval(() => { status.refetch(); }, 5000);
    const limit = setTimeout(() => { clearInterval(poll); setExpired(true); }, 180000);
    return () => { clearInterval(poll); clearTimeout(limit); };
  }, [id, started, status.refetch]);
  return (
    <CippPageCard title="GDAP onboarding status" backButtonTitle="Tenant Onboarding">
      <CardContent><Stack spacing={2}>
        {!validRelationshipId(id) ? <Alert severity="error">Invalid relationship identifier.</Alert> : <>
          <Typography>Relationship: {id}</Typography>
          <Typography>Status: {status.data?.status || 'Checking'}</Typography>
          {started && <Alert severity="success">CIPP has started onboarding. Subsequent results and failures are available in CIPP's existing task and log views.</Alert>}
          {status.isError && <Alert severity="error">Status could not be read. No onboarding action was requested.</Alert>}
          {status.data?.status === 'dispatchNeedsReview' && <Alert severity="warning">A dispatch reservation exists without a job. An administrator must inspect the worker and reservation before recovery.</Alert>}
          {expired && !started && <Alert severity="warning">Onboarding start has not been confirmed. Check webhook delivery and CIPP logs before requesting recovery.</Alert>}
          <Button onClick={() => status.refetch()}>Refresh status</Button>
          <Button href={`/tenant/gdap-management/onboarding/start?id=${encodeURIComponent(id)}`}>Existing onboarding details and administrative controls</Button>
        </>}
      </Stack></CardContent>
    </CippPageCard>
  );
};
Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>;
export default Page;
