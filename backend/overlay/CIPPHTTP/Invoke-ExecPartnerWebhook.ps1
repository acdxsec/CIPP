function Invoke-ExecPartnerWebhook {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    $RegistrationBeforeTest = $null
    $RequestedAt = [datetimeoffset]::UtcNow.ToString('o')
    if ($Request.Query.Action -eq 'SendTest') {
        $RegistrationBeforeTest = New-GraphGetRequest -uri 'https://api.partnercenter.microsoft.com/webhooks/v1/registration' -tenantid $env:TenantID -NoAuthCheck $true -scope 'https://api.partnercenter.microsoft.com/.default'
    }
    $Response = Invoke-ExecPartnerWebhookUpstream -Request $Request -TriggerMetadata $TriggerMetadata
    if ($Request.Query.Action -eq 'SendTest') {
        $CorrelationId = [string]$Response.Body.Results.correlationId
        if ($CorrelationId -match '^[A-Za-z0-9_-]{1,128}$') {
            $Table = Get-CIPPTable -TableName Config
            $null = Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = 'GdapValidation'; RowKey = $CorrelationId
                Fingerprint = Get-CippGdapRegistrationFingerprint $RegistrationBeforeTest
                RequestedAt = $RequestedAt
            } -OperationType Add
        }
    }
    if ($Request.Query.Action -eq 'ValidateTest') {
        $Result = $Response.Body.Results
        # Delivery evidence is bound to the current registration. It does not
        # certify the audit lookup or the onboarding worker's downstream steps.
        $Deliveries = @($Result.results)
        if ($Result.status -in @('completed', 'failed')) {
            $CorrelationId = [string]$Request.Query.CorrelationId
            if ($CorrelationId -notmatch '^[A-Za-z0-9_-]{1,128}$') { return $Response }
            $Table = Get-CIPPTable -TableName Config
            $Pending = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GdapValidation' and RowKey eq '$CorrelationId'" -First 1
            if (-not $Pending) { return $Response }
            $Receipt = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GdapSignedDelivery' and RowKey eq '$CorrelationId'" -First 1
            $Received = [datetimeoffset]::MinValue; $Requested = [datetimeoffset]::MaxValue
            $SignedDelivery = $Receipt.AdapterVersion -eq 1 -and
                [datetimeoffset]::TryParse([string]$Receipt.ReceivedAt, [ref]$Received) -and
                [datetimeoffset]::TryParse([string]$Pending.RequestedAt, [ref]$Requested) -and
                $Received -ge $Requested -and $Received -le [datetimeoffset]::UtcNow
            $Successful = $Result.status -eq 'completed' -and @($Deliveries | Where-Object { $_.responseCode -ge 200 -and $_.responseCode -lt 300 }).Count -gt 0
            $Table = Get-CIPPTable -TableName Config
            $Entity = @{ PartitionKey = 'Config'; RowKey = 'GdapAcceptanceValidation'
                Status = if ($Successful) { 'completed' } else { 'failed' }
                ValidatedAt = [string]$Pending.RequestedAt
                SignedDelivery = [bool]$SignedDelivery
                Fingerprint = [string]$Pending.Fingerprint }
            $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -OperationType UpsertReplace
        }
    }
    return $Response
}
