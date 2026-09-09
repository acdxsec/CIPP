[CmdletBinding()]
param(
    [ValidateSet('docker','podman')][string]$Engine = 'docker',
    [Parameter(Mandatory)][string]$Image,
    [string]$ClientImage = 'mcr.microsoft.com/dotnet/sdk:8.0'
)
$ErrorActionPreference = 'Stop'
$Name = 'gdap-host-smoke-' + [guid]::NewGuid().ToString('N')
$Created = $false
try {
    $null = & $Engine run -d --pull never --name $Name --network none -e CRAFT_SERVE_FRONTEND=true -e GDAP_ACCEPTOR_ENABLED=true $Image
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the isolated host test.' }
    $Created = $true
    $Deadline = [datetime]::UtcNow.AddSeconds(45)
    do {
        $Code = & $Engine run --rm --network "container:$Name" --entrypoint curl $ClientImage --silent --max-time 2 --output /dev/null --write-out '%{http_code}' --request POST --data '' 'http://127.0.0.1:8080/api/PublicWebhooks?Type=PartnerCenter'
        if ($LASTEXITCODE -eq 0 -and $Code -eq '400') { break }
        Start-Sleep -Milliseconds 500
    } while ([datetime]::UtcNow -lt $Deadline)
    if ($Code -ne '400') { throw 'Actual Craft host did not install the original-body capture filter.' }
    $Code = & $Engine run --rm --network "container:$Name" --entrypoint curl $ClientImage --silent --max-time 5 --output /dev/null --write-out '%{http_code}' --request POST --header 'Content-Encoding: gzip' --data '{}' 'http://127.0.0.1:8080/api/PublicWebhooks?Type=PartnerCenter'
    if ($LASTEXITCODE -ne 0 -or $Code -ne '415') { throw 'Actual host bypassed the encoding guard.' }
    Write-Output 'PASS: real Craft entrypoint loads the extension and guards callbacks, network-isolated without Azure credentials'
} finally {
    if ($Created) {
        $null = & $Engine stop --time 5 $Name
        $null = & $Engine rm $Name
    }
}
