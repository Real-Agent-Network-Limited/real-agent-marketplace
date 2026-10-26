# The first install of Real Agent on Windows, in one command. It is in Real Agent's public marketplace, beside
# install.sh for macOS.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1 <marketplace> --owner [--folder <folder>]
#   powershell -ExecutionPolicy Bypass -File install.ps1 <marketplace> --email <email> [okb setup's other options]
#
# <marketplace> is Real Agent's public marketplace, as `claude plugin marketplace add` takes it: a GitHub owner/repo,
# a git or https address, or a folder. Real Agent gives it with this script.
#
# It installs each program the okb plugin uses that is missing, with winget, and Node.js 26 with nodejs.org's
# installer. It downloads whisper.cpp's whisper-bin-x64.zip and its model, ggml-base.bin, to %LOCALAPPDATA%\okb\whisper.
# It prints one line for each: installed, already there, or failed with the command to run by hand. It refreshes its
# own PATH after each install. It then adds the marketplace, installs the okb plugin with whisper.cpp's paths in its
# settings, then the real-agent and business-analyst plugins, and runs the okb plugin's `okb.mjs setup` with the
# options given. okb setup makes the person's folder, %USERPROFILE%\real-agent unless --folder names another, signs in as
# --email, and runs okb sync, which installs the firm's own release of its plugins in place of the public copy.
#
# --owner is the firm's owner's first run, before the firm has a Supabase project. okb setup --owner makes the folder
# and names the business analyst, business-analyst:business-analyst, as its agent, and neither signs in nor runs
# okb sync. It ends: "Start a new Code session on <folder>, and type: Set up Real Agent".
#
# This script never asks for or keeps a password. okb setup's sign-in asks for the person's password at its own
# prompt. Windows asks once to approve the installs that need an administrator. A folder already signed in keeps its
# password: --new-password is left out for it. Run it again to carry on from where it stopped: each step already done
# says so. Each program's own output goes to the log, %TEMP%\okb-install.log.

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Usage = "Usage: powershell -ExecutionPolicy Bypass -File install.ps1 <marketplace> --owner [--folder <folder>]`n       powershell -ExecutionPolicy Bypass -File install.ps1 <marketplace> --email <email> [--folder <folder>] [--url <project URL> --key <publishable key>] [--agent <plugin>:<agent>] [--new-password | --join]"
if ($args.Count -lt 1 -or "$($args[0])" -eq '' -or "$($args[0])".StartsWith('-')) { Write-Host $Usage; exit 2 }
$Marketplace = "$($args[0])"
$Rest = @($args | Select-Object -Skip 1 | ForEach-Object { "$_" })

# okb setup's options, with the folder it sets up. --email, or --owner with no other option, is checked here, before
# any install.
$Folder = $null; $Email = $null; $Owner = $false
[string[]]$Options = @()
for ($i = 0; $i -lt $Rest.Count; $i++) {
  if ($Rest[$i] -eq '--folder') {
    if ($i + 1 -ge $Rest.Count) { Write-Host $Usage; exit 2 }
    $Folder = $Rest[++$i]
  } elseif ($Rest[$i] -eq '--email') {
    if ($i + 1 -ge $Rest.Count) { Write-Host $Usage; exit 2 }
    $Email = $Rest[++$i]; $Options += @('--email', $Email)
  } elseif ($Rest[$i] -eq '--owner') {
    $Owner = $true; $Options += '--owner'
  } else { $Options += $Rest[$i] }
}
if ($Owner) {
  if ($Options.Count -ne 1) { Write-Host '--owner takes only --folder: the firm has no project to sign in to yet.'; Write-Host $Usage; exit 2 }
} elseif ("$Email" -notmatch '.@.') {
  Write-Host '--email is needed: the work email your administrator gave you.'
  Write-Host "The firm's owner, before the firm has a project, gives --owner instead."
  Write-Host $Usage; exit 2
}
if (-not $Folder -or $Folder.StartsWith('-')) { $Folder = Join-Path $HOME 'real-agent' }

# The name of Real Agent's marketplace in Claude Code, which each plugin's id ends with.
$MarketplaceName = 'real-agent'
$Plugins = @('okb', 'real-agent', 'business-analyst')

# Each download, pinned, with its SHA-256. A test checks Node.js's line against the okb plugin's project.json.
$NodeVersion = '26.12.0'
$NodeMsi = @{
  x64   = @{ Url = "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-x64.msi"; Sha256 = 'dd72e3693abed70b7cb5c528dc6eaa46e628a25cd82319fb2c1ccb4462cce633' }
  arm64 = @{ Url = "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-arm64.msi"; Sha256 = 'bc13c50e9dd29645c3b5880ae8366c7c603fe97945ae32b4f846381fa15f5348' }
}
$WhisperUrl = 'https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-bin-x64.zip'
$WhisperSha256 = '6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb'
$ModelUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin'
$ModelSha256 = '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe'

$WhisperDir = Join-Path $env:LOCALAPPDATA 'okb\whisper'
$WhisperCli = Join-Path $WhisperDir 'Release\whisper-cli.exe'
$Model = Join-Path $WhisperDir 'ggml-base.bin'
$Log = Join-Path $env:TEMP 'okb-install.log'
Set-Content -Path $Log -Value '' -Encoding UTF8
$Failed = @()

function Write-Log($text) { Add-Content -Path $Log -Value $text -Encoding UTF8 }

# The PATH as a new terminal has it, and the folders the plugins also look in.
function Update-Path {
  $folders = @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'))
  $folders += Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
  $folders += Join-Path $env:ProgramFiles 'Tesseract-OCR'
  $folders += Get-ChildItem $env:ProgramFiles -Directory -Filter 'ImageMagick*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object FullName
  $env:Path = ($folders | Where-Object { $_ }) -join ';'
}

# A copy inside Git for Windows, such as its own pdftotext, is passed over: the plugins pass over it too.
function Find-Program($name) {
  $found = Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -notmatch '[\\/]Git[\\/](ucrt64|mingw64|mingw32|clang64|usr)[\\/]' } | Select-Object -First 1
  if ($found) { $found.Source } else { $null }
}

function Get-Sha256($file) { (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLowerInvariant() }

# Downloads url to file, unless file is already there with the checksum. Removes a file that fails it.
function Get-Checked($url, $file, $sha256) {
  if ((Test-Path $file) -and (Get-Sha256 $file) -eq $sha256) { return $true }
  New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
  $part = "$file.part"
  try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $part }
  catch { Write-Log "$url could not be downloaded: $_"; Remove-Item $part -ErrorAction SilentlyContinue; return $false }
  if ((Get-Sha256 $part) -ne $sha256) { Write-Log "$url does not match its checksum."; Remove-Item $part; return $false }
  Move-Item -Force $part $file
  $true
}

# One step: label, the test that it is done, the install, and the command a person runs by hand. Whether it was
# missing is read before any install, since one approval installs several.
function Install-Program($label, [scriptblock]$have, [scriptblock]$install, $byHand) {
  if (-not $Missing[$label]) { Write-Host "${label}: already there"; return }
  try { & $install *>&1 | ForEach-Object { Write-Log "$_" } } catch { Write-Log "$label failed: $_" }
  Update-Path
  if (& $have) { Write-Host "${label}: installed"; return }
  Write-Host "${label}: failed. Run it by hand: $byHand"
  $script:Failed += $label
}

function Install-Winget($id) {
  winget install --id $id --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --silent
}

# The installs that need an administrator. winget's own request for one, from this script, is cancelled with no
# prompt shown. So every one that is missing runs in one elevated PowerShell that Windows asks the person to approve,
# once. Its commands go in on its command line, never in a file. It copies the Node.js installer from this user's
# %TEMP% into a new folder only administrators can write to, checks the copy's SHA-256 and its signature by the
# OpenJS Foundation there, runs that copy, and removes the folder. It writes its output to a new file of a random
# name, which this script adds to the log. A standard user approves with an administrator's account, which may have no
# winget of its own, so winget is named by its full path: App Installer's own winget.exe, in Program Files'
# WindowsApps folder and signed by Microsoft, never one found on the PATH.
$AdminInstalls = [ordered]@{ 'Node.js 26' = $null; 'Git' = 'Git.Git'; 'Microsoft Edge' = 'Microsoft.Edge'; 'Tesseract' = 'UB-Mannheim.TesseractOCR'; 'ImageMagick' = 'ImageMagick.ImageMagick' }
$script:AdminRan = $false

function Get-Quoted($text) { "'" + ($text -replace "'", "''") + "'" }

# The elevated PowerShell's command: the steps, with all their output in a new file at out.
function Get-AdminCommand($steps, $out) {
  "& { $($steps -join '; ') } *>&1 | Out-File -LiteralPath $(Get-Quoted $out) -Encoding UTF8 -NoClobber"
}

# One install in the elevated command: Node.js from its checked installer, or a winget package by winget's full path.
function Get-AdminStep($label, $winget, $msi, $sha256) {
  if ($label -eq 'Node.js 26') {
    $step = @'
$nodeDir = $null
try {
  $nodeDir = Join-Path $env:SystemRoot ('Temp\okb-node-' + [guid]::NewGuid().ToString('N'))
  $acl = New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier $sid), 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
  }
  if (Test-Path -LiteralPath $nodeDir) { $nodeDir = $null; throw 'The folder for the Node.js installer was already there, so the installer was not run.' }
  $null = [IO.Directory]::CreateDirectory($nodeDir, $acl)
  if (Get-ChildItem -LiteralPath $nodeDir -Force) { throw 'The folder for the Node.js installer was not empty, so the installer was not run.' }
  $nodeCopy = Join-Path $nodeDir 'node.msi'
  Copy-Item -LiteralPath {msi} -Destination $nodeCopy -ErrorAction Stop
  if ((Get-FileHash -LiteralPath $nodeCopy -Algorithm SHA256).Hash -ne '{sha256}') { throw 'The Node.js installer changed after its check, and was not run.' }
  $signature = Get-AuthenticodeSignature -LiteralPath $nodeCopy
  if ($signature.Status -ne 'Valid' -or "$($signature.SignerCertificate.Subject)" -notmatch '^CN="?OpenJS Foundation"?,') { throw "The Node.js installer is not signed by the OpenJS Foundation ($($signature.Status): $($signature.SignerCertificate.Subject)), and was not run." }
  (Start-Process msiexec.exe -ArgumentList '/i', ('"' + $nodeCopy + '"'), '/passive', '/norestart' -Wait -PassThru).ExitCode
} catch { "$_" } finally {
  if ($nodeDir) { Remove-Item -LiteralPath $nodeDir -Recurse -Force -ErrorAction SilentlyContinue }
}
'@
    return $step.Replace('{msi}', (Get-Quoted $msi)).Replace('{sha256}', $sha256)
  }
  if (-not $winget) { throw "winget's full path is needed for $label." }
  "& $(Get-Quoted $winget) install --id $($AdminInstalls[$label]) --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --silent"
}

# App Installer's own winget.exe, in Program Files' WindowsApps folder, signed by Microsoft with a certificate from a
# Microsoft root. $null when there is none: winget is never taken from the PATH for the administrator's installs.
function Find-WingetPath {
  $apps = (Join-Path $env:ProgramFiles 'WindowsApps') + '\'
  foreach ($package in @(Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)) {
    $location = "$($package.InstallLocation)"
    if (-not $location.StartsWith($apps, [StringComparison]::OrdinalIgnoreCase) -or $location.Contains('..')) { continue }
    $exe = Join-Path $location 'winget.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
    $signature = Get-AuthenticodeSignature -LiteralPath $exe
    if ($signature.Status -ne 'Valid' -or "$($signature.SignerCertificate.Subject)" -notmatch '^CN=Microsoft Corporation,') { continue }
    $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
    # A network that blocks the certificate revocation lists fails an online check. The path and signature pin the file.
    $chain.ChainPolicy.RevocationMode = 'NoCheck'
    if (-not $chain.Build($signature.SignerCertificate)) { continue }
    $root = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Subject
    if ($root -match '^CN=Microsoft Root Certificate Authority') { return $exe }
  }
  $null
}

function Install-AsAdministrator {
  if ($script:AdminRan) { return }
  $script:AdminRan = $true
  $out = Join-Path $env:TEMP ("okb-install-admin-{0}.log" -f [guid]::NewGuid().ToString('N'))
  $winget = Find-WingetPath
  $steps = @(); $labels = @(); $noWinget = @()
  foreach ($label in $AdminInstalls.Keys) {
    if (-not $Missing[$label]) { continue }
    if ($label -ne 'Node.js 26' -and -not $winget) { $noWinget += $label; continue }
    if ($label -eq 'Node.js 26') {
      $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
      $msi = Join-Path $env:TEMP "node-v$NodeVersion-$arch.msi"
      if (-not (Get-Checked $NodeMsi[$arch].Url $msi $NodeMsi[$arch].Sha256)) { Write-Log 'The Node.js installer did not download whole.'; continue }
      $steps += Get-AdminStep $label $winget $msi $NodeMsi[$arch].Sha256
    } else {
      $steps += Get-AdminStep $label $winget
    }
    $labels += $label
  }
  if ($noWinget) {
    Write-Log "No winget.exe signed by Microsoft was found in $(Join-Path $env:ProgramFiles 'WindowsApps')."
    [Console]::Out.WriteLine("Windows' own winget, from App Installer, was not found, so $($noWinget -join ', ') cannot be installed as an administrator. Update App Installer from the Microsoft Store, then run this again.")
  }
  if (-not $steps) { return }
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-AdminCommand $steps $out)))
  # Written to the console itself: this runs inside a program's install, whose own output goes to the log.
  [Console]::Out.WriteLine("Windows asks once to approve the installs that need an administrator: $($labels -join ', ').")
  try {
    $run = Start-Process powershell.exe -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded -Verb RunAs -Wait -PassThru -WindowStyle Hidden
  } catch {
    Write-Log "The approval was not given: $_"
    [Console]::Out.WriteLine('The approval was declined. Run this again to be asked once more.')
    return
  }
  if (Test-Path $out) { Get-Content $out | ForEach-Object { Write-Log $_ }; Remove-Item $out -ErrorAction SilentlyContinue }
  Write-Log "The administrator's installs ended with $($run.ExitCode)."
}

function Find-Node26 {
  foreach ($node in @((Find-Program 'node'), (Join-Path $env:ProgramFiles 'nodejs\node.exe'))) {
    if ($node -and (Test-Path $node) -and ((& $node -v 2>$null) -match '^v26\.')) { return $node }
  }
  $null
}

function Test-Python {
  foreach ($try in @(@('py', '-3'), @('python'))) {
    $exe = Find-Program $try[0]
    if (-not $exe -or $exe -like '*\WindowsApps\*') { continue }
    $version = & $exe @($try | Select-Object -Skip 1) --version 2>&1
    if ("$version" -match '^Python 3') { return $true }
  }
  $false
}

# The marketplace's folder on this computer, from Claude Code's list of marketplaces, or $null.
function Find-MarketplaceFolder {
  try { $listed = (& claude plugin marketplace list --json 2>$null) -join "`n" | ConvertFrom-Json } catch { return $null }
  $found = @($listed) | Where-Object { $_.name -eq $MarketplaceName } | Select-Object -First 1
  if ($found -and $found.installLocation) { $found.installLocation } else { $null }
}

# True when <plugin>@real-agent is installed, from Claude Code's list of plugins.
function Test-Plugin($plugin) {
  try { $listed = (& claude plugin list --json 2>$null) -join "`n" | ConvertFrom-Json } catch { return $false }
  [bool](@($listed) | Where-Object { $_.id -eq "$plugin@$MarketplaceName" })
}

$Browsers = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
)

Update-Path
if (-not (Find-Program 'winget')) {
  Write-Host "winget: missing. Install App Installer from the Microsoft Store, then run this again."
  exit 1
}

$Programs = @(
  @{ Label = "Claude Code's command-line tool"; Have = { [bool](Find-Program 'claude') }; Install = { Install-Winget 'Anthropic.ClaudeCode' }; ByHand = 'winget install Anthropic.ClaudeCode' },
  @{ Label = 'Node.js 26'; Have = { [bool](Find-Node26) }; Install = { Install-AsAdministrator }; ByHand = 'winget install OpenJS.NodeJS' },
  @{ Label = 'Git'; Have = { [bool](Find-Program 'git') }; Install = { Install-AsAdministrator }; ByHand = 'winget install Git.Git' },
  @{ Label = 'Python 3'; Have = { Test-Python }; Install = { Install-Winget 'Python.Python.3.13' }; ByHand = 'winget install Python.Python.3.13' },
  @{ Label = 'Microsoft Edge'; Have = { [bool]($Browsers | Where-Object { Test-Path $_ }) }; Install = { Install-AsAdministrator }; ByHand = 'winget install Microsoft.Edge' },
  @{ Label = 'Poppler'; Have = { [bool](Find-Program 'pdftoppm') }; Install = { Install-Winget 'oschwartz10612.Poppler' }; ByHand = 'winget install oschwartz10612.Poppler' },
  @{ Label = 'Tesseract'; Have = { [bool](Find-Program 'tesseract') }; Install = { Install-AsAdministrator }; ByHand = 'winget install UB-Mannheim.TesseractOCR' },
  @{ Label = 'FFmpeg'; Have = { [bool](Find-Program 'ffmpeg') }; Install = { Install-Winget 'Gyan.FFmpeg' }; ByHand = 'winget install Gyan.FFmpeg' },
  @{ Label = 'ImageMagick'; Have = { [bool](Find-Program 'magick') }; Install = { Install-AsAdministrator }; ByHand = 'winget install ImageMagick.ImageMagick' }
)
$Missing = @{}
foreach ($p in $Programs) { $Missing[$p.Label] = -not (& $p.Have) }
$Missing['whisper.cpp'] = -not (Test-Path $WhisperCli)
$Missing["whisper.cpp's model"] = -not ((Test-Path $Model) -and (Get-Sha256 $Model) -eq $ModelSha256)
foreach ($p in $Programs) { Install-Program $p.Label $p.Have $p.Install $p.ByHand }
Install-Program 'whisper.cpp' { Test-Path $WhisperCli } {
  $zip = Join-Path $env:TEMP 'whisper-bin-x64.zip'
  if (-not (Get-Checked $WhisperUrl $zip $WhisperSha256)) { throw "whisper-bin-x64.zip did not download whole." }
  # Unpacked beside the folder first, so a stopped run leaves no half folder.
  $unpacked = "$WhisperDir.unpacking"
  Remove-Item -Recurse -Force $unpacked -ErrorAction SilentlyContinue
  Expand-Archive -Path $zip -DestinationPath $unpacked -Force
  New-Item -ItemType Directory -Force -Path $WhisperDir | Out-Null
  Remove-Item -Recurse -Force (Join-Path $WhisperDir 'Release') -ErrorAction SilentlyContinue
  Move-Item (Join-Path $unpacked 'Release') (Join-Path $WhisperDir 'Release')
  Remove-Item -Recurse -Force $unpacked
} "Download $WhisperUrl and unzip it into $WhisperDir"
Install-Program "whisper.cpp's model" { (Test-Path $Model) -and (Get-Sha256 $Model) -eq $ModelSha256 } {
  if (-not (Get-Checked $ModelUrl $Model $ModelSha256)) { throw "ggml-base.bin did not download whole." }
} "Invoke-WebRequest $ModelUrl -OutFile $Model"

if ($Failed | Where-Object { $_ -in @("Claude Code's command-line tool", 'Node.js 26', 'Git') }) {
  Write-Host "The first install needs Claude Code's command-line tool, Node.js 26 and Git. Install each that failed, then run this again. The log is $Log."
  exit 1
}
if ($Failed) { Write-Host "Install each program that failed with its command, later. The log is $Log." }

$Missing["Real Agent's marketplace"] = -not (Find-MarketplaceFolder)
Install-Program "Real Agent's marketplace" { [bool](Find-MarketplaceFolder) } { & claude plugin marketplace add $Marketplace } "claude plugin marketplace add $Marketplace"
if ($Failed -contains "Real Agent's marketplace") {
  Write-Host "The plugins come from Real Agent's marketplace. Check its address with Real Agent, then run this again. The log is $Log."
  exit 1
}

# The okb plugin finds whisper.cpp on Windows only by its settings, so they name this script's copy.
if ((Test-Path $WhisperCli) -and (Test-Path $Model)) {
  & claude plugin install "okb@$MarketplaceName" --config "whisper_cli=$WhisperCli" --config "whisper_model=$Model" *>&1 | ForEach-Object { Write-Log "$_" }
}
foreach ($plugin in $Plugins) {
  $label = "The $plugin plugin"
  $Missing[$label] = -not (Test-Plugin $plugin)
  Install-Program $label ([scriptblock]::Create("Test-Plugin '$plugin'")) ([scriptblock]::Create("& claude plugin install '$plugin@$MarketplaceName'")) "claude plugin install $plugin@$MarketplaceName"
}
if ($Failed | Where-Object { $_ -like 'The * plugin' }) {
  Write-Host "Install each plugin that failed with its command, then run this again. The log is $Log."
  exit 1
}

$Okb = Join-Path (Find-MarketplaceFolder) 'plugins\okb\cli\okb.mjs'
if (-not (Test-Path $Okb)) {
  Write-Host "Real Agent's marketplace holds no okb.mjs at $Okb. Check its address with Real Agent. The log is $Log."
  exit 1
}

# A folder already signed in keeps its password.
[string[]]$Setup = @()
foreach ($option in $Options) {
  if ($option -eq '--new-password' -and (Test-Path (Join-Path $Folder '.okb-actor.json'))) {
    Write-Host "$Folder is already signed in, so your password stays as it is."
  } else { $Setup += $option }
}
$node = Find-Node26
Write-Host 'Setting up your folder with okb setup.'
& $node $Okb setup --folder $Folder @Setup
exit $LASTEXITCODE
