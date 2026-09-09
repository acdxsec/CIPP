$ErrorActionPreference = 'Stop'
class HttpResponseContext { [System.Net.HttpStatusCode]$StatusCode; [object]$Body }
foreach ($File in Get-ChildItem "$PSScriptRoot/overlay" -Recurse -Filter '*.ps1') { . $File.FullName }
function Assert($Value, $Message) { if (-not $Value) { throw $Message } }
$script:Store = @{}; $script:Writes = 0; $script:Dispatches = 0
function Get-CIPPTable { param($TableName) @{ Context = $TableName } }
function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value.Replace("'", "''") }
function Get-CIPPAzDataTableEntity {
    param($Context, $Filter, $First)
    foreach ($Row in $script:Store.Values) {
        if ($Row.Table -eq $Context -and $Filter.Contains("RowKey eq '$($Row.RowKey)'")) {
            if ($Filter -notmatch 'PartitionKey eq' -or $Filter.Contains("PartitionKey eq '$($Row.PartitionKey)'")) { return $Row }
        }
    }
}
function Add-CIPPAzDataTableEntity {
    [CmdletBinding()]param($Context, $Entity, $OperationType)
    $script:Writes++
    $Key = "$Context|$($Entity.PartitionKey)|$($Entity.RowKey)"
    if ($OperationType -eq 'Add' -and $script:Store.ContainsKey($Key)) { throw '409 Conflict' }
    $script:Store[$Key] = @{} + $Entity + @{ Table = $Context }
}
function Write-LogMessage { param($API, $message, $Sev) }
Assert (-not (Test-CippGdapSignedPayloadSupport)) 'Unsupported pinned host reported signature support'
function Invoke-PublicWebhooksUpstream { param($Request, $TriggerMetadata) [HttpResponseContext]@{ StatusCode=202; Body='upstream-test' } }
$env:GDAP_ACCEPTOR_ENABLED = 'false'
$response = Invoke-PublicWebhooks -Request @{ Query=@{ Type='PartnerCenter' }; Headers=@{}; Body=@{} }
Assert ($response.StatusCode -eq 202) 'Development overlay broke existing webhook behavior'
$env:GDAP_ACCEPTOR_ENABLED = 'true'
$response = Invoke-PublicWebhooks -Request @{ Query=@{ Type='PartnerCenter' }; Headers=@{}; Body=@{} }
Assert ($response.StatusCode -eq 403) 'Enabled feature bypassed validation on missing host extension'
# Remaining checks exercise the contract of a future, verified compatible host.
function Test-CippGdapSignedPayloadSupport { $true }
$id = '5d027261-d21f-4aa9-b7db-7fa1f56fb163-8777b240-c6f0-4469-9e98-a3205431b836'
$request = @{ Query = @{ id = $id }; Headers = @{} }
$response = Invoke-ListGdapAcceptanceStatus -Request $request
Assert ($response.Body.status -eq 'awaitingOnboarding' -and $script:Writes -eq 0) 'Status read created work'
foreach ($status in @('queued', 'running', 'succeeded', 'failed')) {
    $script:Store['job'] = @{ Table = 'TenantOnboarding'; PartitionKey='Onboarding'; RowKey=$id; Status=$status; Timestamp='2026-01-01' }
    $response = Invoke-ListGdapAcceptanceStatus -Request $request
    Assert ($response.Body.onboardingStarted -eq ($status -ne 'queued')) "Start evidence wrong for $status"
}
Assert ($script:Writes -eq 0) 'Status endpoint mutated rows'
$script:Store.Clear()
Invoke-CippGdapDispatchOnce -Id $id -Dispatch { $script:Dispatches++ }
Invoke-CippGdapDispatchOnce -Id $id -Dispatch { $script:Dispatches++ }
Assert ($script:Dispatches -eq 1) 'Duplicate event dispatched again'
$response = Invoke-ListGdapAcceptanceStatus -Request $request
Assert ($response.Body.status -eq 'dispatchNeedsReview') 'Orphan claim hidden'
$script:Store.Clear()
$env:TenantID = '11111111-1111-1111-1111-111111111111'
$env:GDAP_ACCEPTOR_INSTANCE_ID = '22222222-2222-2222-2222-222222222222'
$env:GDAP_ACCEPTOR_ENABLED = 'true'
$script:Registration = @{ webhookUrl="https://cipp.example/api/PublicWebhooks?CIPPID=$($env:TenantID)&Type=PartnerCenter"; webhookEvents=@('test-created','granular-admin-relationship-approved') }
function Get-CIPPHostname { param($Headers, [switch]$PreferCustomDomain) 'cipp.example' }
function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, $scope) $script:Registration }
$script:Store['config'] = @{ Table='Config'; PartitionKey='Config'; RowKey='PartnerWebhookOnboarding'; Enabled=$true }
$script:Store['validation'] = @{ Table='Config'; PartitionKey='Config'; RowKey='GdapAcceptanceValidation'; Status='completed'; SignedDelivery=$true; ValidatedAt=[datetimeoffset]::UtcNow.AddMinutes(-1).ToString('o'); Fingerprint=(Get-CippGdapRegistrationFingerprint $script:Registration) }
$response = Invoke-ListGdapAcceptanceReadiness -Request $request
Assert ($response.Body.ready -eq $true) 'Valid readiness rejected'
$script:Store['validation'].SignedDelivery = $false
$response = Invoke-ListGdapAcceptanceReadiness -Request $request
Assert (-not $response.Body.ready) 'Legacy delivery evidence was accepted as signature proof'
$script:Store['validation'].SignedDelivery = $true
$script:Registration.webhookEvents = @('test-created')
$response = Invoke-ListGdapAcceptanceReadiness -Request $request
Assert (-not $response.Body.ready) 'Changed registration remained ready'
$script:Registration.webhookEvents = @('test-created','granular-admin-relationship-approved')
$script:Store['validation'].ValidatedAt = [datetimeoffset]::UtcNow.AddDays(-2).ToString('o')
$response = Invoke-ListGdapAcceptanceReadiness -Request $request
Assert (-not $response.Body.ready) 'Stale readiness accepted'
$key = [Security.Cryptography.RSA]::Create(2048)
$csr = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=synthetic-test', $key, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
$cert = $csr.CreateSelfSigned([datetimeoffset]::UtcNow.AddMinutes(-1), [datetimeoffset]::UtcNow.AddDays(1))
try {
    $bytes = [Text.Encoding]::UTF8.GetBytes('{"EventName":"test-created"}')
    $sig = [Convert]::ToBase64String($key.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1))
    Assert (Test-CippPartnerWebhookSignature $bytes $sig $cert) 'Valid signature rejected'
    $bytes[0] = 0
    Assert (-not (Test-CippPartnerWebhookSignature $bytes $sig $cert)) 'Tampered payload accepted'
} finally { $cert.Dispose(); $key.Dispose() }
$response = Invoke-PublicWebhooks -Request @{ Query=@{ Type='PartnerCenter' }; Headers=@{}; Body=@{} }
Assert ($response.StatusCode -eq 403) 'Missing original signed bytes accepted'
function Invoke-ExecPartnerWebhookUpstream {
    param($Request, $TriggerMetadata)
    if ($Request.Query.Action -eq 'SendTest') { return [HttpResponseContext]@{ StatusCode=200; Body=@{ Results=@{ correlationId='validation-1' } } } }
    [HttpResponseContext]@{ StatusCode=200; Body=@{ Results=@{ status='completed'; results=@(@{ responseCode=200 }) } } }
}
$script:Store.Clear()
$null = Invoke-ExecPartnerWebhook -Request @{ Query=@{ Action='SendTest' } }
$validate = @{ Query=@{ Action='ValidateTest'; CorrelationId='validation-1' } }
$null = Invoke-ExecPartnerWebhook -Request $validate
Assert (-not $script:Store['Config|Config|GdapAcceptanceValidation'].SignedDelivery) 'Unsigned delivery acquired signed proof'
Set-CippGdapSignedDeliveryEvidence -VerifiedBody @{ EventName='test-created'; ResourceUri='https://api.partnercenter.microsoft.com/webhooks/v1/registration/validationEvents/validation-1' }
$null = Invoke-ExecPartnerWebhook -Request $validate
Assert ($script:Store['Config|Config|GdapAcceptanceValidation'].SignedDelivery) 'Matching signed delivery was not correlated'
$script:Store['Config|GdapSignedDelivery|validation-1'].ReceivedAt = [datetimeoffset]::UtcNow.AddDays(-1).ToString('o')
$null = Invoke-ExecPartnerWebhook -Request $validate
Assert (-not $script:Store['Config|Config|GdapAcceptanceValidation'].SignedDelivery) 'Old signed delivery satisfied a newer test'
Write-Output 'PASS: read-only status, completed-start evidence, duplicate dispatch, orphan claim, readiness, and signature checks'
