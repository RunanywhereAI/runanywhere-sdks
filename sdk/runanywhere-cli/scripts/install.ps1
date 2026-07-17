param(
    [Parameter(Mandatory = $false)]
    [string]$Version = "",

    [Parameter(Mandatory = $false)]
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\rcli"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Repo = "RunanywhereAI/runanywhere-sdks"
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Latest = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    $Version = ([string]$Latest.tag_name).TrimStart("v")
}
$Version = $Version.TrimStart("v")

$Asset = "rcli-windows-x86_64-v$Version.zip"
$BaseUrl = "https://github.com/$Repo/releases/download/v$Version"
$TempDir = Join-Path ([IO.Path]::GetTempPath()) "rcli-install-$([Guid]::NewGuid())"
New-Item $TempDir -ItemType Directory -Force | Out-Null

try {
    $Zip = Join-Path $TempDir $Asset
    $Checksum = "$Zip.sha256"
    Invoke-WebRequest "$BaseUrl/$Asset" -OutFile $Zip
    Invoke-WebRequest "$BaseUrl/$Asset.sha256" -OutFile $Checksum

    $Expected = ((Get-Content $Checksum -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    $Actual = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected) {
        throw "SHA-256 verification failed for $Asset"
    }

    $Expanded = Join-Path $TempDir "expanded"
    Expand-Archive $Zip -DestinationPath $Expanded
    $Payload = Join-Path $Expanded "rcli-windows-x86_64"
    if (-not (Test-Path (Join-Path $Payload "bin\rcli.exe"))) {
        throw "release archive does not contain rcli-windows-x86_64/bin/rcli.exe"
    }

    $BinDir = Join-Path $InstallDir "bin"
    Remove-Item $BinDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item $BinDir -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $Payload "bin\*") $BinDir -Recurse
    Copy-Item (Join-Path $Payload "README.md") (Join-Path $InstallDir "README.md") -Force

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $Entries = @($UserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Entries -notcontains $BinDir) {
        $NewPath = (@($Entries) + $BinDir) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        Write-Host "Added $BinDir to your user PATH. Open a new terminal to use it."
    }
    $env:PATH = "$BinDir;$env:PATH"

    & (Join-Path $BinDir "rcli.exe") version
    if ($LASTEXITCODE -ne 0) { throw "installed rcli smoke test failed" }
    Write-Host "Installed rcli $Version to $BinDir"
    Write-Host "Try: rcli list --all; rcli run qwen3"
} finally {
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
