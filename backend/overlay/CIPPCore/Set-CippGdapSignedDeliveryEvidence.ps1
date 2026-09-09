function Set-CippGdapSignedDeliveryEvidence {
    param($VerifiedBody)
    # Called only after certificate and content-signature validation. Only the
    # documented validation-event URI is recognized; it is never fetched.
    if ($VerifiedBody.EventName -ne 'test-created') { return }
    if ([string]$VerifiedBody.ResourceUri -cnotmatch '\Ahttps?://api\.partnercenter\.microsoft\.com/webhooks/v1/registration/validationEvents/(?<id>[A-Za-z0-9_-]{1,128})\z') { return }
    $Id = $Matches.id
    $Table = Get-CIPPTable -TableName Config
    $null = Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey = 'GdapSignedDelivery'; RowKey = $Id
        ReceivedAt = [datetimeoffset]::UtcNow.ToString('o'); AdapterVersion = 1
    } -OperationType UpsertReplace
}
