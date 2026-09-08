function Get-CippGdapRegistrationFingerprint {
    param([Parameter(Mandatory)]$Registration)
    $Value = [string]$Registration.webhookUrl + '|' + ((@($Registration.webhookEvents) | Sort-Object -Unique) -join ',')
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value)))
}
