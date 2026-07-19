param(
    [Parameter(Mandatory = $false)]
    [string]$BuildDir = "build/rcli-windows-release",

    [Parameter(Mandatory = $false)]
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$CliRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RepoRoot = (Resolve-Path (Join-Path $CliRoot "..\..")).Path
if (-not [IO.Path]::IsPathRooted($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot $BuildDir
}
$BuildDir = (Resolve-Path $BuildDir).Path

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = (Get-Content (Join-Path $RepoRoot "sdk\runanywhere-commons\VERSION") -Raw).Trim()
}
$Version = $Version.TrimStart("v")

$BinaryCandidates = @(
    (Join-Path $BuildDir "sdk\runanywhere-cli\rcli.exe"),
    (Join-Path $BuildDir "sdk\runanywhere-cli\Release\rcli.exe")
)
$Binary = $BinaryCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Binary) {
    $Binary = Get-ChildItem -Path $BuildDir -Filter "rcli.exe" -File -Recurse |
        Where-Object { $_.FullName -match "runanywhere-cli" } |
        Select-Object -ExpandProperty FullName -First 1
}
if (-not $Binary) {
    throw "rcli.exe was not found under $BuildDir"
}

$Platform = "windows-x86_64"
$DistDir = Join-Path $CliRoot "dist"
$StageRoot = Join-Path $DistDir "stage"
$Stage = Join-Path $StageRoot "rcli-$Platform"
$BinDir = Join-Path $Stage "bin"
$Zip = Join-Path $DistDir "rcli-$Platform-v$Version.zip"

Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item $BinDir -ItemType Directory -Force | Out-Null
Copy-Item $Binary (Join-Path $BinDir "rcli.exe")
Copy-Item (Join-Path $CliRoot "README.md") (Join-Path $Stage "README.md")

function Copy-RuntimeDlls([string]$Source, [string[]]$Exclude = @()) {
    if (-not (Test-Path $Source)) { return }
    Get-ChildItem -Path $Source -Filter "*.dll" -File | ForEach-Object {
        if (-not ($Exclude -contains $_.Name)) {
            $Destination = Join-Path $BinDir $_.Name
            if (-not (Test-Path $Destination)) {
                Copy-Item $_.FullName $Destination
            }
        }
    }
}

# The CLI links the pinned standalone ONNX Runtime. Sherpa's upstream bundle
# may carry an older onnxruntime.dll, so stage the repository pin first and
# deliberately exclude that duplicate while collecting Sherpa's other DLLs.
$OnnxDll = Get-ChildItem -Path $BuildDir -Filter "onnxruntime.dll" -File -Recurse |
    Where-Object { $_.FullName -match "onnxruntime-src[\\/]lib" } |
    Select-Object -ExpandProperty FullName -First 1
if (-not $OnnxDll) {
    throw "the pinned ONNX Runtime DLL was not found under $BuildDir"
}
Copy-Item $OnnxDll (Join-Path $BinDir "onnxruntime.dll")

# Sherpa ships sherpa-onnx-c-api.dll and its siblings in lib/ (bin/ holds only
# the example executables and a duplicate onnxruntime.dll).
$SherpaLib = Join-Path $RepoRoot "sdk\runanywhere-commons\third_party\sherpa-onnx-windows\lib"
Copy-RuntimeDlls $SherpaLib @("onnxruntime.dll")
if (-not (Test-Path (Join-Path $BinDir "sherpa-onnx-c-api.dll"))) {
    throw "sherpa-onnx-c-api.dll was not staged"
}

# Validate from the exact relocatable directory that users receive.
$OldPath = $env:PATH
try {
    $env:PATH = "$BinDir;$OldPath"
    & (Join-Path $BinDir "rcli.exe") version
    if ($LASTEXITCODE -ne 0) { throw "packaged rcli version smoke failed" }
    $Backends = (& (Join-Path $BinDir "rcli.exe") backends --json) -join "`n"
    Write-Host $Backends
    if ($LASTEXITCODE -ne 0) { throw "packaged rcli backends smoke failed" }
    if ($Backends -notmatch '"name":"llamacpp"') { throw "llama.cpp backend is missing" }
    if ($Backends -notmatch '"name":"sherpa"') { throw "Sherpa backend is missing" }
} finally {
    $env:PATH = $OldPath
}

Get-ChildItem -Path $BinDir -File | ForEach-Object {
    $Bytes = [IO.File]::ReadAllBytes($_.FullName)
    $Text = [Text.Encoding]::ASCII.GetString($Bytes)
    if ($Text.Contains($RepoRoot) -or $Text -match '[A-Za-z]:\\Users\\[^\\]+\\') {
        throw "packaged artifact embeds a developer checkout path: $($_.Name)"
    }
}

New-Item $DistDir -ItemType Directory -Force | Out-Null
Remove-Item $Zip, "$Zip.sha256" -Force -ErrorAction SilentlyContinue
Compress-Archive -Path $Stage -DestinationPath $Zip -CompressionLevel Optimal
$Hash = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$Hash  $([IO.Path]::GetFileName($Zip))" |
    Set-Content -Path "$Zip.sha256" -Encoding ascii -NoNewline

Write-Host "Packaged: $Zip"
Get-ChildItem -Path $Stage -Recurse -File | ForEach-Object {
    Write-Host $_.FullName.Substring($StageRoot.Length + 1)
}
