function Get-CippGdapOriginalWebhookBody {
    param($Request)
    # Never trust a raw-body header or reconstructed JSON. The native middleware
    # owns each handle, strips incoming handles and deletes buffers after dispatch.
    $Handle = [string]$Request.Headers.'x-cipp-gdap-body-handle'
    if ($Handle -cnotmatch '\A[A-F0-9]{64}\z') { throw 'Original webhook body unavailable.' }
    $Bytes = [Cipp.Gdap.Hosting.WebhookBodyBridge]::Take($Handle)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { throw 'Original webhook body unavailable.' }
    return ,$Bytes
}
