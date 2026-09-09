function Invoke-CippPartnerWebhookProcessing {
    [CmdletBinding()]
    param($Data)
    if ($env:GDAP_ACCEPTOR_ENABLED -ne 'true' -or $Data.EventName -ne 'granular-admin-relationship-approved') {
        return Invoke-CippPartnerWebhookProcessingUpstream -Data $Data
    }
    $Uri = $null
    if (-not [uri]::TryCreate([string]$Data.AuditUri, [UriKind]::Absolute, [ref]$Uri) -or
        $Uri.Scheme -ne 'https' -or $Uri.Host -ne 'api.partnercenter.microsoft.com' -or $Uri.UserInfo -or -not $Uri.IsDefaultPort) {
        throw 'Invalid Partner Center audit URL.'
    }
    $Table = Get-CIPPTable -TableName Config
    $Config = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'PartnerWebhookOnboarding'" -First 1
    if ($Config.Enabled -ne $true) { return }
    $Audit = New-GraphGetRequest -uri $Uri.AbsoluteUri -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
    if (-not $Audit.resourceNewValue) { throw 'Approval audit evidence is unavailable.' }
    $Relationship = $Audit.resourceNewValue | ConvertFrom-Json -ErrorAction Stop
    $null = Invoke-CippGdapDispatchOnce -Id ([string]$Relationship.id) -Dispatch {
        Invoke-CippPartnerWebhookProcessingUpstream -Data $Data
    }
}
