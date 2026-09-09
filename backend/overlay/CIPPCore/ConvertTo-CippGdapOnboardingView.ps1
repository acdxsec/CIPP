function ConvertTo-CippGdapOnboardingView {
    param($Row)
    # Preserve the existing UI response shape without modifying the stored row.
    $View = $Row | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $Steps = try { $View.OnboardingSteps | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    $View | Add-Member -NotePropertyName OnboardingSteps -NotePropertyValue @($Steps.PSObject.Properties.Value) -Force
    foreach ($Name in @('Relationship', 'Logs')) {
        $Value = try { $View.$Name | ConvertFrom-Json -ErrorAction Stop } catch { @{} }
        $View | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    return $View
}
