function Invoke-CippGdapDispatchOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][scriptblock]$Dispatch)
    if ($Id -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9_-]{0,255}\z') { throw 'Invalid relationship identifier.' }
    $SafeId = ConvertTo-CIPPODataFilterValue -Value $Id -Type String
    $Onboarding = Get-CIPPTable -TableName TenantOnboarding
    $Existing = Get-CIPPAzDataTableEntity @Onboarding -Filter "PartitionKey eq 'Onboarding' and RowKey eq '$SafeId'" -First 1
    if ($Existing) { return @{ Disposition = 'existingJob'; Job = $Existing } }
    $Claims = Get-CIPPTable -TableName GdapOnboardingClaims
    $Claim = @{ PartitionKey = 'Dispatch'; RowKey = $Id; ClaimedAt = [datetimeoffset]::UtcNow.ToString('o') }
    try {
        # Azure Table Add is atomic. Do not replace this with upsert or Force.
        $null = Add-CIPPAzDataTableEntity @Claims -Entity $Claim -OperationType Add -ErrorAction Stop
    } catch {
        if (Get-CIPPAzDataTableEntity @Claims -Filter "PartitionKey eq 'Dispatch' and RowKey eq '$SafeId'" -First 1) { return @{ Disposition = 'dispatchNeedsReview' } }
        throw
    }
    # A crash between reservation and dispatch requires an operator to inspect the
    # row and worker before recovery. Expiring a claim could start concurrent work.
    $Result = & $Dispatch
    return @{ Disposition = 'dispatched'; Result = $Result }
}
