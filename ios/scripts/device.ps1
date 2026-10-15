param(
    [ValidateSet('Check', 'Install', 'Screenshot')][string]$Action = 'Check',
    [string]$Ipa,
    [string]$Output = 'artifacts\iphone-screen.png',
    [string]$DeviceTool = 'pymobiledevice3'
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command $DeviceTool -ErrorAction SilentlyContinue)) {
    throw 'pymobiledevice3 is not installed. Install the device tooling before connecting for a test.'
}
switch ($Action) {
    'Check' {
        Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue | Select-Object Name, Status
        & $DeviceTool usbmux list
    }
    'Install' {
        if (-not $Ipa -or -not (Test-Path -LiteralPath $Ipa -PathType Leaf)) { throw 'Pass an existing signed IPA with -Ipa.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Ipa).Path)
        try {
            $signed = @($archive.Entries | Where-Object FullName -Match '^Payload/[^/]+\.app/embedded\.mobileprovision$')
            if ($signed.Count -ne 1) { throw 'This IPA is unsigned or unsupported. It cannot be installed directly.' }
        } finally { $archive.Dispose() }
        & $DeviceTool apps install $Ipa
    }
    'Screenshot' {
        $parent = Split-Path -Parent $Output
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
        & $DeviceTool developer dvt screenshot $Output
    }
}
if ($LASTEXITCODE -ne 0) { throw "Device tool failed with exit code $LASTEXITCODE" }
