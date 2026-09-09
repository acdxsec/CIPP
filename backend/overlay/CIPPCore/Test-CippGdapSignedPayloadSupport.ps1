function Test-CippGdapSignedPayloadSupport {
    # An environment flag alone is insufficient: the native filter must actually
    # be installed in this process. Missing/disabled startup extensions fail closed.
    try { return [Cipp.Gdap.Hosting.WebhookBodyBridge]::Installed }
    catch { return $false }
}
