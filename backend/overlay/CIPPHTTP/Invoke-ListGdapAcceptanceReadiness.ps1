function Invoke-ListGdapAcceptanceReadiness {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    $Reasons = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-CippGdapSignedPayloadSupport)) { $Reasons.Add('hostRawBodyUnsupported') }
    $InstanceId = [guid]::Empty
    if (-not [guid]::TryParseExact([string]$env:GDAP_ACCEPTOR_INSTANCE_ID, 'D', [ref]$InstanceId) -or $InstanceId -eq [guid]::Empty) { $Reasons.Add('instanceNotConfigured') }
    if ($env:GDAP_ACCEPTOR_ENABLED -ne 'true') { $Reasons.Add('acceptorNotEnabled') }
    $ConfigTable = Get-CIPPTable -TableName Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq 'PartnerWebhookOnboarding'" -First 1
    if ($Config.Enabled -ne $true) { $Reasons.Add('automatedOnboardingDisabled') }
    try {
        $Registration = New-GraphGetRequest -uri 'https://api.partnercenter.microsoft.com/webhooks/v1/registration' -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
        $Hostname = Get-CIPPHostname -Headers $Request.Headers -PreferCustomDomain
        $ExpectedUrl = "https://$Hostname/api/PublicWebhooks?CIPPID=$($env:TenantID)&Type=PartnerCenter"
        if (-not $Hostname -or [string]$Registration.webhookUrl -cne $ExpectedUrl) { $Reasons.Add('webhookUrlMismatch') }
        foreach ($Event in @('test-created','granular-admin-relationship-approved')) {
            if ($Event -notin @($Registration.webhookEvents)) { $Reasons.Add("missingEvent:$Event") }
        }
        $Fingerprint = Get-CippGdapRegistrationFingerprint $Registration
        $Validation = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'Config' and RowKey eq 'GdapAcceptanceValidation'" -First 1
        $At = [datetimeoffset]::MinValue
        if ($Validation.Status -ne 'completed' -or $Validation.Fingerprint -cne $Fingerprint -or
            -not [datetimeoffset]::TryParse([string]$Validation.ValidatedAt, [ref]$At) -or
            $At -gt [datetimeoffset]::UtcNow -or $At -lt [datetimeoffset]::UtcNow.AddHours(-24)) {
            $Reasons.Add('webhookValidationRequired')
        }
    } catch { $Reasons.Add('webhookReadinessUnavailable') }
    return [HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body = @{ contractVersion = 1; ready = ($Reasons.Count -eq 0); reasons = @($Reasons)
            instanceId = $InstanceId.ToString(); partnerTenantId = [string]$env:TenantID
            validationScope = 'callbackDeliveryOnly'; repairPath = '/cipp/settings/partner-webhooks' }
    }
}
