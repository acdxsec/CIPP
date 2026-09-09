function Test-CippPartnerWebhookSignature {
    [CmdletBinding()]
    param([byte[]]$Content, [string]$Signature, [Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    if (-not $Content -or -not $Certificate -or -not $Signature) { return $false }
    $Key = $null
    try {
        $Key = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Certificate)
        if (-not $Key) { return $false }
        return $Key.VerifyData($Content, [Convert]::FromBase64String($Signature), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    } catch { return $false } finally { if ($Key) { $Key.Dispose() } }
}
