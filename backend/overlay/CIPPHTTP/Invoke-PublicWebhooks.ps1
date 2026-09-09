function Invoke-PublicWebhooks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
    #>
    param($Request, $TriggerMetadata)
    if ($Request.Query.Type -ne 'PartnerCenter') { return Invoke-PublicWebhooksUpstream -Request $Request -TriggerMetadata $TriggerMetadata }
    # Explicitly disabled retains legacy behavior. Enabled with a broken/missing
    # extension must reject callbacks, never silently bypass signature validation.
    if ($env:GDAP_ACCEPTOR_ENABLED -ne 'true') {
        return Invoke-PublicWebhooksUpstream -Request $Request -TriggerMetadata $TriggerMetadata
    }
    $Certificate = $null; $Chain = $null
    try {
        if (-not (Test-CippGdapSignedPayloadSupport)) { throw 'Original request capture is not installed.' }
        $Bytes = Get-CippGdapOriginalWebhookBody -Request $Request
        if ($Bytes.Length -eq 0 -or $Bytes.Length -gt 1048576) { throw 'Invalid request size.' }
        $Headers = $Request.Headers
        if ($Headers.'x-ms-signature-algorithm' -ne 'rsa-sha256') { throw 'Unsupported signature algorithm.' }
        $Signature = [string]$Headers.'x-ms-signature'
        if (-not $Signature) {
            if ([string]$Headers.Authorization -notmatch '^Signature ([A-Za-z0-9+/=]+)$') { throw 'Missing signature.' }
            $Signature = $Matches[1]
        }
        $Uri = $null
        if (-not [uri]::TryCreate([string]$Headers.'x-ms-certificate-url', [UriKind]::Absolute, [ref]$Uri) -or
            $Uri.Scheme -ne 'https' -or $Uri.Host -ne '3psostorageacct.blob.core.windows.net' -or
            -not $Uri.IsDefaultPort -or $Uri.UserInfo -or $Uri.Query -or $Uri.Fragment -or
            $Uri.AbsolutePath -notmatch '^/cert/[A-Za-z0-9._-]+\.cer$') { throw 'Untrusted certificate location.' }
        $Response = Invoke-WebRequest -Uri $Uri.AbsoluteUri -MaximumRedirection 0 -TimeoutSec 15 -ErrorAction Stop
        $Certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new([byte[]]$Response.Content)
        if ($Certificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { throw 'Unexpected certificate organization.' }
        $Chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
        $Chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::Online
        $Chain.ChainPolicy.UrlRetrievalTimeout = [timespan]::FromSeconds(10)
        if (-not $Chain.Build($Certificate)) { throw 'Untrusted certificate chain.' }
        $Root = $Chain.ChainElements[$Chain.ChainElements.Count - 1].Certificate
        if ($Root.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { throw 'Unexpected certificate root.' }
        if (-not (Test-CippPartnerWebhookSignature -Content $Bytes -Signature $Signature -Certificate $Certificate)) { throw 'Invalid signature.' }
        # Pass only the verified payload to downstream processing.
        $Request.Body = [Text.Encoding]::UTF8.GetString($Bytes) | ConvertFrom-Json -ErrorAction Stop
        Set-CippGdapSignedDeliveryEvidence -VerifiedBody $Request.Body
        return Invoke-PublicWebhooksUpstream -Request $Request -TriggerMetadata $TriggerMetadata
    } catch {
        Write-LogMessage -API 'Webhooks' -message 'Partner Center callback rejected: signature or original payload validation failed.' -Sev 'Alert'
        return [HttpResponseContext]@{ StatusCode = [System.Net.HttpStatusCode]::Forbidden; Body = 'Webhook validation failed.' }
    } finally {
        if ($Chain) { $Chain.Dispose() }; if ($Certificate) { $Certificate.Dispose() }
    }
}
