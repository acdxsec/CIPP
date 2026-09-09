function Invoke-ExecOnboardTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    if ($env:GDAP_ACCEPTOR_ENABLED -ne 'true') { return Invoke-ExecOnboardTenantUpstream -Request $Request -TriggerMetadata $TriggerMetadata }
    $Id = [string]$Request.Body.id
    if ($Id -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9_-]{0,255}\z') {
        return [HttpResponseContext]@{ StatusCode=400; Body=@{ error='Invalid relationship identifier.' } }
    }
    try {
        if ($Request.Body.Retry -eq $true -or $Request.Body.Cancel -eq $true) {
            $Table = Get-CIPPTable -TableName TenantOnboarding
            $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Onboarding' and RowKey eq '$Id'" -First 1
            # Once execution has started, downstream retries/cancellation remain
            # CIPP's responsibility. Do not pretend deleting a queued row stops a worker.
            if ($Row.Status -in @('running', 'succeeded', 'failed')) {
                return Invoke-ExecOnboardTenantUpstream -Request $Request -TriggerMetadata $TriggerMetadata
            }
            return [HttpResponseContext]@{ StatusCode=409; Body=@{ error='Execution has not been confirmed. Inspect queued work and dispatch reservations; retry/cancel cannot safely reset this attempt.' } }
        }
        $Gate = Invoke-CippGdapDispatchOnce -Id $Id -Dispatch {
            Invoke-ExecOnboardTenantUpstream -Request $Request -TriggerMetadata $TriggerMetadata
        }
        switch ($Gate.Disposition) {
            'dispatched' { return $Gate.Result }
            'existingJob' { return [HttpResponseContext]@{ StatusCode=200; Body=(ConvertTo-CippGdapOnboardingView $Gate.Job) } }
            default { return [HttpResponseContext]@{ StatusCode=409; Body=@{ error='A dispatch reservation exists. No duplicate job was started; operator review is required.' } } }
        }
    } catch {
        return [HttpResponseContext]@{ StatusCode=503; Body=@{ error='Onboarding dispatch could not be confirmed. Inspect existing work before retrying.' } }
    }
}
