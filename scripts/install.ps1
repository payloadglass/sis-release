$ErrorActionPreference = "Stop"

$repo = $env:SIS_GITHUB_REPO
if ([string]::IsNullOrWhiteSpace($repo)) {
  $repo = "payloadglass/sis-release"
}

$installDir = $env:SIS_INSTALL_DIR
if ([string]::IsNullOrWhiteSpace($installDir)) {
  $installDir = Join-Path $env:LOCALAPPDATA "sis\bin"
}

$target = "x86_64-pc-windows-msvc"
$ext = "zip"

# Stable by default: /releases/latest returns the newest non-draft,
# non-prerelease release. The list includes prereleases (newest first), so it
# is used only when explicitly requested.
if ($env:SIS_INSTALL_PRERELEASE -eq "1") {
  Write-Host "Installing newest release including prereleases (SIS_INSTALL_PRERELEASE=1)"
  $apiUrl = "https://api.github.com/repos/$repo/releases?per_page=20"
} else {
  Write-Host "Installing latest stable release"
  $apiUrl = "https://api.github.com/repos/$repo/releases/latest"
}
$response = Invoke-RestMethod -Headers @{"User-Agent" = "sis-install"} -Uri $apiUrl
if ($response -is [System.Collections.IDictionary] -and $response.message) {
  throw "GitHub API error: $($response.message)"
}
# /releases/latest returns one object, the list returns an array; wrap so the
# loop below handles both.
$releases = @($response)
$suffix = "-$target.$ext"
$release = $null
$asset = $null
foreach ($entry in $releases) {
  if ($entry.draft) {
    continue
  }
  # Match the CLI asset (sis-<tag>-<target>.<ext>) and exclude the companion
  # sis-app-* artefact.
  $candidate = $entry.assets |
    Where-Object { $_.name -like "sis-*$suffix" -and $_.name -notlike "sis-app-*" -and $_.browser_download_url } |
    Select-Object -First 1
  if ($candidate) {
    $release = $entry
    $asset = $candidate
    break
  }
}
if (-not $asset) {
  throw "No release asset found for $target"
}

$tempDir = Join-Path $env:TEMP ("sis-install-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
try {
  $archivePath = Join-Path $tempDir $asset.name
  Invoke-WebRequest -Headers @{"User-Agent" = "sis-install"} -Uri $asset.browser_download_url -OutFile $archivePath
  # Verify against the release's SHA256SUMS BEFORE extracting. Fail closed: a missing manifest,
  # a missing entry or a mismatch aborts with nothing installed. This catches corruption and
  # tampering with a mirror or download path; it does not defend against a compromised
  # release, because SHA256SUMS comes from the same release.
  $sumsAsset = $release.assets | Where-Object { $_.name -eq "SHA256SUMS" } | Select-Object -First 1
  if (-not $sumsAsset) {
    throw "SHA256SUMS is not published with release $($release.tag_name); refusing to install an unverified archive."
  }
  $sumsPath = Join-Path $tempDir "SHA256SUMS"
  Invoke-WebRequest -Headers @{"User-Agent" = "sis-install"} -Uri $sumsAsset.browser_download_url -OutFile $sumsPath
  $expected = $null
  foreach ($line in Get-Content -LiteralPath $sumsPath) {
    $parts = $line.Trim() -split '\s+', 2
    if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $asset.name) {
      $expected = $parts[0]
      break
    }
  }
  if (-not $expected) {
    throw "SHA256SUMS has no entry for $($asset.name); refusing to install an unverified archive."
  }
  $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
  if ($actual -ne $expected) {
    throw "Checksum mismatch for $($asset.name): expected $expected, got $actual. Nothing was installed."
  }
  Write-Host "Verified $($asset.name) against SHA256SUMS"
  Expand-Archive -Path $archivePath -DestinationPath $tempDir -Force
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  Copy-Item (Join-Path $tempDir "sis.exe") (Join-Path $installDir "sis.exe") -Force
  # `sis sanitize release` looks for sis-cdr-worker.exe in the same directory as
  # sis.exe. Archives that predate it (e.g. v0.7.0-beta.1, v0.6.9) do not have it.
  # No per-file checksums are verified for sis.exe either; the worker comes from
  # the same downloaded archive.
  $workerSrc = Join-Path $tempDir "sis-cdr-worker.exe"
  if (Test-Path -LiteralPath $workerSrc) {
    Copy-Item $workerSrc (Join-Path $installDir "sis-cdr-worker.exe") -Force
    Write-Host "Installed sis-cdr-worker.exe to $installDir\sis-cdr-worker.exe"
  } else {
    Write-Host "note: this release has no sis-cdr-worker.exe; ``sis sanitize release`` is unavailable"
  }
  Write-Host "Installed sis $($release.tag_name) to $installDir\sis.exe"
  if (-not (Get-Command sis -ErrorAction SilentlyContinue)) {
    Write-Host "Add $installDir to your PATH to run sis"
  }
} finally {
  Remove-Item -Recurse -Force -Path $tempDir
}
