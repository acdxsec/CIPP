function Invoke-ListGdapAcceptanceStatus {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    $Id = [string]$Request.Query.id
    if ($Id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,255}$') {
        return [HttpResponseContext]@{ StatusCode = [System.Net.HttpStatusCode]::BadRequest; Body = @{ error = 'Invalid relationship identifier' } }
    }
    $Table = Get-CIPPTable -TableName TenantOnboarding
    $SafeId = ConvertTo-CIPPODataFilterValue -Value $Id -Type String
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Onboarding' and RowKey eq '$SafeId'" -First 1
    $Status = if ($Row) { [string]$Row.Status } else { 'awaitingOnboarding' }
    # A queued row alone is not proof of execution. Terminal states prove a start
    # happened, without claiming that all downstream onboarding steps succeeded.
    $Started = $Status -in @('running', 'succeeded', 'failed')
    $Claims = Get-CIPPTable -TableName GdapOnboardingClaims
    $Claim = Get-CIPPAzDataTableEntity @Claims -Filter "PartitionKey eq 'Dispatch' and RowKey eq '$SafeId'" -First 1
    if (-not $Row -and $Claim) { $Status = 'dispatchNeedsReview' }
    $Body = @{
        contractVersion = 1; relationshipId = $Id; status = $Status
        onboardingStarted = $Started; recordedAt = if ($Row) { $Row.Timestamp } else { $null }
    }
    return [HttpResponseContext]@{ StatusCode = [System.Net.HttpStatusCode]::OK; Body = $Body }
}
