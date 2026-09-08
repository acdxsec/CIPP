function Test-CippGdapSignedPayloadSupport {
    # The pinned Craft 10.9.1 BuildRequestFromParts method exposes parsed Body,
    # not RawBody. This is a source-reviewed capability, not an admin toggle.
    # Change only after updating the pinned host and passing a signed HTTP test.
    return $false
}
