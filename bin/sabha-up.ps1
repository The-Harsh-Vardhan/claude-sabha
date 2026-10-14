# Opens one maximised Windows Terminal window split 4x2 and starts the eight sabha tabs; the relay
# (first role) is started by hand from the user's own editor.
#   sabha-up.ps1                 open the grid
#   sabha-up.ps1 <Name>          start one role in the current terminal (each pane runs this)
#   sabha-up.ps1 -Print <Name>   print that role's one-line restart command and exit
# Run it from a plain terminal, never from inside a Claude session.
# Paths and names come from sabha.conf ($env:SABHA_CONF, else ..\sabha.conf beside this script);
# -Workspace overrides SABHA_WS.
param(
  [string]$Name,
  [string]$Workspace,
  [switch]$Print
)
$ErrorActionPreference = 'Stop'

# KEY=value lines, as in sabha-up.sh: quotes stripped, ~ and $VAR (earlier keys, then the environment) expanded
$Conf = if ($env:SABHA_CONF) { $env:SABHA_CONF } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'sabha.conf' }
if (-not (Test-Path $Conf)) { Write-Error "no config at $Conf (copy sabha.conf.example to sabha.conf)" }
$cfg = @{}
foreach ($line in Get-Content $Conf) {
  if ($line -match '^\s*([A-Z_][A-Z0-9_]*)=(.*)$') {
    $v = $Matches[2].Trim().Trim('"').Trim("'")
    if ($v.StartsWith('~')) { $v = $HOME + $v.Substring(1) }
    $v = [regex]::Replace($v, '\$([A-Z_][A-Z0-9_]*)', { param($m)
      if ($cfg.ContainsKey($m.Groups[1].Value)) { $cfg[$m.Groups[1].Value] } else { [Environment]::GetEnvironmentVariable($m.Groups[1].Value) } })
    $cfg[$Matches[1]] = $v
    # set here, not after the loop, so a later SABHA_IMPL=$SABHA_WS/... follows the override
    if ($Matches[1] -eq 'SABHA_WS' -and $Workspace) { $cfg.SABHA_WS = $Workspace }
  }
}
foreach ($k in 'SABHA_WS', 'SABHA_IMPL') { if (-not $cfg[$k]) { Write-Error "$k missing from $Conf" } }
# a trailing backslash would escape the closing quote when wt rebuilds the pane command line
$Workspace = $cfg.SABHA_WS.TrimEnd('\', '/')
$Impl = $cfg.SABHA_IMPL.TrimEnd('\', '/')
$Project = if ($cfg.SABHA_PROJECT) { $cfg.SABHA_PROJECT } else { 'this project' }
$Owner = if ($cfg.SABHA_USER) { $cfg.SABHA_USER } else { 'the user' }
$Protocol = Join-Path $Impl 'PROTOCOL.md'
$Icons = Join-Path (Split-Path $PSScriptRoot -Parent) 'icons'

# name, model, effort - the relay first, then the dispatcher, then grid order: top row left->right, then bottom row.
# SABHA_ROSTER (Name:model[:effort]) replaces this default list.
$Roles = @(
  @('Vidur', 'opus', 'medium'),
  @('Yudhishthira', 'opus', 'medium'),
  @('Bhishma', 'fable', 'medium'),
  @('Bhima', 'opus', 'high'),
  @('Arjun', 'opus', 'medium'),
  @('Sahadev', 'sonnet', 'high'),
  @('Nakul', 'sonnet', 'medium'),
  @('Sanjaya', 'haiku', 'high'),
  @('Abhimanyu', 'haiku', 'medium')
)

if ($cfg.SABHA_ROSTER) {
  $Roles = @(foreach ($e in -split $cfg.SABHA_ROSTER) {
      $f = $e.Split(':')
      ,@($f[0], $f[1], $(if ($f.Count -gt 2 -and $f[2]) { $f[2] } else { 'medium' })) })
}
$Relay = $Roles[0][0]
$Dispatcher = $Roles[1][0]
# a loop, not Where-Object: the pipeline would unroll the matched inner array
$r = $null
if ($Name) {
  foreach ($x in $Roles) { if ($x[0] -eq $Name) { $r = $x } }
  if (-not $r) { Write-Error "unknown role: $Name" }
  $to = if ($r[0] -eq $Relay) { $Owner } elseif ($r[0] -eq $Dispatcher) { $Relay } else { $Dispatcher }
  $lower = $r[0].ToLower()
  # same text as sabha-up.sh; keep the two identical
  $prompt = "You are $($r[0]) in $Project session setup. First run ListAgents: if another live row has the name $($r[0]), append a restart item to $Impl\for-me.items and stop. Then read $Protocol, then status/$lower.md, then inbox/$($r[0])/ (ack any brief without an ack; resume any brief with an ack and no done), and continue from the status file's Next line. Report to $to."
  if ($Print) {
    "cd `"$Workspace`"; claude -n $($r[0]) --model $($r[1]) --effort $($r[2]) `"$prompt`""
    exit 0
  }
  Set-Location $Workspace
  & claude -n $r[0] --model $r[1] --effort $r[2] $prompt
  exit $LASTEXITCODE
}

if ($Roles.Count -ne 9) { Write-Error "the grid needs 9 roles (the relay plus 8 panes), the roster has $($Roles.Count)" }

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
  Write-Error 'wt.exe not found on PATH: install Windows Terminal, or run sabha-up.ps1 <Name> in eight terminals'
}

# wt has no per-pane icon flag, so each role gets a profile in a user-scope fragment; the icon key is
# written only when the .ico exists. A Terminal already running picks up a new fragment after a restart.
$fragDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\claude-sabha'
New-Item -ItemType Directory -Force -Path $fragDir | Out-Null
$profiles = foreach ($r in $Roles[1..8]) {
  $p = [ordered]@{ name = "Sabha $($r[0])" }
  $ico = Join-Path $Icons "$($r[0].ToLower()).ico"
  if (-not (Test-Path $ico)) { $ico = Join-Path $Icons 'sabha.ico' }
  if (Test-Path $ico) { $p.icon = $ico }
  $p
}
# UTF-8 without BOM in both 5.1 and 7 (5.1's -Encoding utf8 writes a BOM)
[IO.File]::WriteAllText((Join-Path $fragDir 'sabha.json'), (@{ profiles = @($profiles) } | ConvertTo-Json -Depth 4),
  (New-Object Text.UTF8Encoding $false))

$hostExe = (Get-Process -Id $PID).Path
function Pane([int]$i) {
  $n = $Roles[$i + 1][0]
  @('-p', "Sabha $n", '--title', $n, '-d', $Workspace, $hostExe, '-NoLogo', '-NoExit', '-ExecutionPolicy', 'Bypass',
    '-File', $PSCommandPath, $n, '-Workspace', $Workspace)
}

# four equal columns (each split takes the right share of what is left), then split each column
# from right to left; move-focus left from a bottom pane lands on the next column's single pane
$wtArgs = @('--maximized', 'new-tab') + (Pane 0) +
  @(';', 'split-pane', '-V', '-s', '0.75') + (Pane 1) +
  @(';', 'split-pane', '-V', '-s', '0.6667') + (Pane 2) +
  @(';', 'split-pane', '-V', '-s', '0.5') + (Pane 3) +
  @(';', 'split-pane', '-H') + (Pane 7) +
  @(';', 'move-focus', 'left', ';', 'split-pane', '-H') + (Pane 6) +
  @(';', 'move-focus', 'left', ';', 'split-pane', '-H') + (Pane 5) +
  @(';', 'move-focus', 'left', ';', 'split-pane', '-H') + (Pane 4)
& wt.exe @wtArgs
