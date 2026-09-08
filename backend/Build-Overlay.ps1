[CmdletBinding()]
param([Parameter(Mandatory)][string]$ApiRoot)
$ErrorActionPreference = 'Stop'
$Expected = @{
    CIPPHTTP = '45b460e48245b3d492c06936de933154b72d833c010f77e68f1e2abe35dbef01'
    CIPPCore = '1514a2ddb4cf368c5b1f13dc65f186d61eaf8abd8df96a11c0d7faee09d3e920'
}
foreach ($Module in $Expected.Keys) {
    $Path = Join-Path $ApiRoot "Modules/$Module/$Module.psm1"
    if ((Get-FileHash $Path -Algorithm SHA256).Hash -ine $Expected[$Module]) { throw "Unsupported base module: $Module. Review the overlay before changing its pinned hash." }
    $Source = [IO.File]::ReadAllText($Path)
    if ($Module -eq 'CIPPHTTP') {
        $Needle = 'function Invoke-ExecPartnerWebhook {'
        if (($Source.Split($Needle, [StringSplitOptions]::None)).Count -ne 2) { throw 'Expected exactly one webhook settings function.' }
        $Source = $Source.Replace($Needle, 'function Invoke-ExecPartnerWebhookUpstream {')
        $Needle = 'function Invoke-PublicWebhooks {'
        if (($Source.Split($Needle, [StringSplitOptions]::None)).Count -ne 2) { throw 'Expected exactly one public webhook function.' }
        $Source = $Source.Replace($Needle, 'function Invoke-PublicWebhooksUpstream {')
    } else {
        $Needle = 'function Invoke-CippPartnerWebhookProcessing {'
        if (($Source.Split($Needle, [StringSplitOptions]::None)).Count -ne 2) { throw 'Expected exactly one Partner Center processor.' }
        $Source = $Source.Replace($Needle, 'function Invoke-CippPartnerWebhookProcessingUpstream {')
    }
    $Names = @()
    foreach ($File in Get-ChildItem (Join-Path $PSScriptRoot "overlay/$Module") -Filter '*.ps1' | Sort-Object Name) {
        $Source += [Environment]::NewLine + [IO.File]::ReadAllText($File.FullName)
        $Names += $File.BaseName
    }
    $Tokens = $null; $Errors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($Source, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count) { throw "Invalid generated module $Module`: $($Errors.Message -join '; ')" }
    [IO.File]::WriteAllText($Path, $Source)
    $ManifestPath = Join-Path $ApiRoot "Modules/$Module/$Module.psd1"
    $Manifest = Import-PowerShellDataFile $ManifestPath
    $Exports = @($Manifest.FunctionsToExport) + $Names | Sort-Object -Unique
    $ManifestText = [IO.File]::ReadAllText($ManifestPath)
    $Pattern = '(?m)^\s*FunctionsToExport\s*=\s*@\([^\r\n]*\)\s*$'
    if ([regex]::Matches($ManifestText, $Pattern).Count -ne 1) { throw 'Unsupported manifest export layout.' }
    $ExportText = '    FunctionsToExport = @(' + (($Exports | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ',') + ')'
    $ManifestText = [regex]::Replace($ManifestText, $Pattern, [Text.RegularExpressions.MatchEvaluator]{ param($Match) $ExportText })
    [IO.File]::WriteAllText($ManifestPath, $ManifestText)
    $null = Import-PowerShellDataFile $ManifestPath
}
