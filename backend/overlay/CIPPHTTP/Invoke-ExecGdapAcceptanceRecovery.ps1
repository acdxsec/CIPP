function Invoke-ExecGdapAcceptanceRecovery {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    $Id = [string]$Request.Body.id
    $Customer = [guid]::Empty
    if ($Request.Method -ne 'POST' -or $Request.Body.confirm -isnot [bool] -or $Request.Body.confirm -ne $true -or
        $Id -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9_-]{0,255}\z' -or
        -not [guid]::TryParseExact([string]$Request.Body.expectedCustomerTenantId, 'D', [ref]$Customer) -or $Customer -eq [guid]::Empty) {
        return [HttpResponseContext]@{ StatusCode=400; Body=@{ error='POST, explicit confirmation, relationship ID and expected customer tenant UUID are required.' } }
    }
    try {
        $Table = Get-CIPPTable -TableName Config
        $Config = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Config' and RowKey eq 'PartnerWebhookOnboarding'" -First 1
        if ($env:GDAP_ACCEPTOR_ENABLED -ne 'true' -or $Config.Enabled -ne $true) {
            return [HttpResponseContext]@{ StatusCode=409; Body=@{ error='Automated onboarding is disabled.' } }
        }
        # Fresh partner-scoped Graph read; never trust URI parameters or portal
        # client claims about activation/customer binding. This does not approve GDAP.
        $Relationship = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships/$Id" -tenantid $env:TenantID -NoAuthCheck $true
        if ($Relationship.id -cne $Id -or $Relationship.status -ne 'active' -or
            [string]$Relationship.customer.tenantId -ine $Customer.ToString()) {
            return [HttpResponseContext]@{ StatusCode=409; Body=@{ error='Active relationship and expected customer identity could not be verified.' } }
        }
        Write-LogMessage -headers $Request.Headers -API 'ExecGdapAcceptanceRecovery' -message "Explicit onboarding recovery requested for relationship $Id and customer $Customer." -Sev Info
        $Forward = @{
            Body=@{ id=$Id; standardsExcludeAllTenants=($Config.StandardsExcludeAllTenants -eq $true) }
            Headers=$Request.Headers; Params=@{ CIPPEndpoint='ExecGdapAcceptanceRecovery' }; Method='POST'
        }
        return Invoke-ExecOnboardTenant -Request $Forward -TriggerMetadata $TriggerMetadata
    } catch {
        return [HttpResponseContext]@{ StatusCode=503; Body=@{ error='Recovery was not confirmed. Inspect relationship and existing work before retrying.' } }
    }
}
