import { useRouter } from 'next/router';
import { useState } from 'react';
import { Alert, Button, CardContent, Stack, Typography } from '@mui/material';
import { Layout as DashboardLayout } from '../../../../layouts/index.js';
import CippPageCard from '../../../../components/CippCards/CippPageCard';
import { ApiGetCall } from '../../../../api/ApiCall';
import { acceptanceUri, readinessAllowsLaunch, validRelationshipId } from '../../../../utils/gdap-acceptance.mjs';

const Page = () => {
  const { query } = useRouter();
  const id = query.id;
  const [launched, setLaunched] = useState(false);
  const [error, setError] = useState('');
  const readiness = ApiGetCall({
    url: '/api/ListGdapAcceptanceReadiness', queryKey: 'GdapAcceptanceReadiness',
    waiting: validRelationshipId(id), retry: 0,
    data: { tenantFilter: 'AllTenants' }, staleTime: 0,
  });
  const ready = readinessAllowsLaunch(readiness.data);
  const launch = async () => {
    setError('');
    const current = await readiness.refetch();
    if (current.isError || !readinessAllowsLaunch(current.data)) {
      setError('Automated onboarding is not ready. Review the settings and run Test Webhook.');
      return;
    }
    try {
      window.location.assign(acceptanceUri(current.data.instanceId, id));
      setLaunched(true);
    } catch {
      setError('Unable to open GDAP Acceptor. Check the installation and trusted instance configuration.');
    }
  };
  return (
    <CippPageCard title="Accept and onboard" backButtonTitle="GDAP Invites">
      <CardContent><Stack spacing={2}>
        {!validRelationshipId(id) ? <Alert severity="error">Invalid invitation identifier.</Alert> : <>
          <Typography>Relationship: {id}</Typography>
          <Typography>GDAP Acceptor will ask for the expected customer tenant before sign-in, then show the partner and requested access for confirmation.</Typography>
          {(readiness.isError || error) && <Alert severity="error">{error || 'Readiness is unavailable. A compatible custom backend is required.'}</Alert>}
          {!ready && !readiness.isFetching && <Alert severity="warning">Automated onboarding is not ready: {readiness.data?.reasons?.join(', ') || 'readiness has not been verified'}.</Alert>}
          <Button href="/cipp/settings/partner-webhooks">Automated Onboarding settings and webhook test</Button>
          <Button variant="contained" onClick={launch} disabled={!ready || readiness.isFetching}>Open GDAP Acceptor</Button>
          {launched && <Alert severity="info">Launch requested. Your browser cannot reliably confirm that the app opened. If nothing happens, install or configure GDAP Acceptor, then try again.</Alert>}
          <Button href="https://github.com/acdxsec/GDAP-Acceptor/releases" target="_blank" rel="noopener noreferrer">Companion releases and installation</Button>
          <Button href={`/tenant/gdap-management/onboarding/status?id=${encodeURIComponent(id)}`}>Observe onboarding status</Button>
          <Button href={`https://admin.microsoft.com/AdminPortal/Home#/partners/invitation/granularAdminRelationships/${encodeURIComponent(id)}`} target="_blank" rel="noopener noreferrer">Open Microsoft invitation manually</Button>
        </>}
      </Stack></CardContent>
    </CippPageCard>
  );
};
Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>;
export default Page;
