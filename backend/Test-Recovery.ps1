$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Test-Overlay.ps1"
$script:Store.Clear(); $script:Dispatches = 0
$env:GDAP_ACCEPTOR_ENABLED = 'true'
function Invoke-ExecOnboardTenantUpstream {
    param($Request, $TriggerMetadata)
    $script:Dispatches++
    [HttpResponseContext]@{ StatusCode=200; Body=@{ Status='queued' } }
}
$manual = @{ Method='POST'; Body=@{ id=$id }; Headers=@{}; Params=@{} }
$response = Invoke-ExecOnboardTenant -Request $manual
Assert ($response.StatusCode -eq 200 -and $script:Dispatches -eq 1) 'First manual dispatch failed'
$response = Invoke-ExecOnboardTenant -Request $manual
Assert ($response.StatusCode -eq 409 -and $script:Dispatches -eq 1) 'Manual request duplicated an uncertain dispatch'
$null = Invoke-CippGdapDispatchOnce -Id $id -Dispatch { $script:Dispatches++ }
Assert ($script:Dispatches -eq 1) 'Webhook duplicated a manual dispatch'
$script:Store.Clear(); $script:Dispatches = 0
$null = Invoke-CippGdapDispatchOnce -Id $id -Dispatch {
    # Interleave the manual path after the webhook owns the atomic reservation.
    $competing = Invoke-ExecOnboardTenant -Request $manual
    Assert ($competing.StatusCode -eq 409) 'Manual/webhook interleaving bypassed the reservation'
    $script:Dispatches++
}
Assert ($script:Dispatches -eq 1) 'Competing dispatch executed twice'
$script:Store['job'] = @{ Table='TenantOnboarding'; PartitionKey='Onboarding'; RowKey=$id; Status='queued'; Timestamp='2000-01-01'; OnboardingSteps='{"Step1":{"Status":"pending"}}'; Relationship=''; Logs='' }
$response = Invoke-ExecOnboardTenant -Request $manual
Assert ($response.StatusCode -eq 200 -and $response.Body.Status -eq 'queued' -and $script:Dispatches -eq 1) 'Old queued row was restarted by polling'
Assert ($script:Store['job'].OnboardingSteps -is [string]) 'Observation mutated storage'
foreach ($operation in @('Retry','Cancel')) {
    $manual.Body[$operation] = $true
    $response = Invoke-ExecOnboardTenant -Request $manual
    Assert ($response.StatusCode -eq 409 -and $script:Dispatches -eq 1) 'Unstarted job was reset by an administrative action'
    $manual.Body.Remove($operation)
}
$script:Store.Clear(); $script:Dispatches = 0
$script:Store['config'] = @{ Table='Config'; PartitionKey='Config'; RowKey='PartnerWebhookOnboarding'; Enabled=$true }
$customer = '33333333-3333-3333-3333-333333333333'
$script:LiveRelationship = @{ id=$id; status='active'; customer=@{ tenantId=$customer } }
function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck) $script:LiveRelationship }
function Write-LogMessage { param($headers, $API, $message, $Sev) }
$request = @{ Method='POST'; Body=@{ id=$id; expectedCustomerTenantId=$customer; confirm=$false }; Headers=@{} }
$response = Invoke-ExecGdapAcceptanceRecovery -Request $request
Assert ($response.StatusCode -eq 400 -and $script:Dispatches -eq 0) 'Unconfirmed recovery dispatched'
$request.Body.confirm = $true
$request.Method = 'GET'
$response = Invoke-ExecGdapAcceptanceRecovery -Request $request
Assert ($response.StatusCode -eq 400 -and $script:Dispatches -eq 0) 'GET recovery dispatched'
$request.Method = 'POST'
$request.Body.confirm = 'true'
$response = Invoke-ExecGdapAcceptanceRecovery -Request $request
Assert ($response.StatusCode -eq 400 -and $script:Dispatches -eq 0) 'Non-boolean confirmation dispatched'
$request.Body.confirm = $true
$script:LiveRelationship.status = 'activating'
$response = Invoke-ExecGdapAcceptanceRecovery -Request $request
Assert ($response.StatusCode -eq 409 -and $script:Dispatches -eq 0) 'Inactive relationship recovery dispatched'
$script:LiveRelationship.status = 'active'
$request.Body.expectedCustomerTenantId = '44444444-4444-4444-4444-444444444444'
$response = Invoke-ExecGdapAcceptanceRecovery -Request $request
Assert ($response.StatusCode -eq 409 -and $script:Dispatches -eq 0) 'Wrong-customer recovery dispatched'
$request.Body.expectedCustomerTenantId = $customer
$response = Invoke-ExecGdapAcceptanceRecovery -Request $request
Assert ($response.StatusCode -eq 200 -and $script:Dispatches -eq 1) 'Valid missing-event recovery failed'
$response = Invoke-ExecGdapAcceptanceRecovery -Request $request
Assert ($response.StatusCode -eq 409 -and $script:Dispatches -eq 1) 'Recovery duplicated an uncertain request'
Write-Output 'PASS: shared initial-dispatch gate, interleaved callers, read-only legacy polling, uncertain reset rejection and identity-bound recovery'
