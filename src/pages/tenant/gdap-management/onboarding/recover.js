import { useEffect, useState } from 'react';
import { useRouter } from 'next/router';
import { Alert, Button, CardContent, Checkbox, FormControlLabel, Stack, TextField, Typography } from '@mui/material';
import { Layout as DashboardLayout } from '../../../../layouts/index.js';
import CippPageCard from '../../../../components/CippCards/CippPageCard';
import { ApiPostCall } from '../../../../api/ApiCall';
import { validRelationshipId } from '../../../../utils/gdap-acceptance.mjs';

const Page = () => {
  const { query } = useRouter();
  const id = query.id;
  const [customer, setCustomer] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  useEffect(() => { setCustomer(''); setConfirmed(false); }, [id]);
  const recovery = ApiPostCall({});
  const validCustomer = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(customer) && customer !== '00000000-0000-0000-0000-000000000000';
  return <CippPageCard title="Recover missing onboarding dispatch" backButtonTitle="GDAP onboarding status">
    <CardContent><Stack spacing={2}>
      <Typography>Relationship: {validRelationshipId(id) ? id : 'Invalid identifier'}</Typography>
      <Alert severity="warning">This requests an initial onboarding dispatch only. It does not accept GDAP, reset an existing attempt, clear a reservation, or cancel a worker.</Alert>
      <Typography>CIPP will verify the active relationship and customer tenant in Microsoft Graph. Existing jobs are returned unchanged; uncertain dispatch reservations require operator review.</Typography>
      <TextField label="Expected customer tenant ID" value={customer} onChange={(event) => { setCustomer(event.target.value.trim()); setConfirmed(false); }} />
      <FormControlLabel control={<Checkbox checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} />} label="I have checked CIPP status and want to request the missing initial dispatch for this customer." />
      <Button variant="contained" disabled={!validRelationshipId(id) || !validCustomer || !confirmed || recovery.isPending || recovery.isSuccess}
        onClick={() => { setConfirmed(false); recovery.mutate({ url: '/api/ExecGdapAcceptanceRecovery', data: { id, expectedCustomerTenantId: customer, confirm: true } }); }}>
        Request initial dispatch
      </Button>
      {recovery.isSuccess && <Alert severity="info">The request returned successfully. Observe status to confirm that a worker actually starts.</Alert>}
      {recovery.isError && <Alert severity="error">Recovery was not confirmed. Inspect existing jobs, reservations and CIPP logs before another request.</Alert>}
      <Button href={`/tenant/gdap-management/onboarding/status?id=${encodeURIComponent(id || '')}`}>Observe status without starting work</Button>
    </Stack></CardContent>
  </CippPageCard>;
};
Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>;
export default Page;
