[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('Status', 'Diagnose', 'Restore', 'RebootAndWait')]
    [string]$Command,

    [string]$HostName = '192.168.137.2',
    [string]$UserName = 'exp',
    [string]$IdentityFile = "$HOME\.ssh\id_ed25519",
    [string]$Target,
    [string]$ConfirmSerial
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
    throw 'Windows OpenSSH client ssh.exe is not installed.'
}
if (-not (Test-Path -LiteralPath $IdentityFile -PathType Leaf)) {
    throw "SSH identity file does not exist: $IdentityFile"
}

$knownHosts = Join-Path $env:LOCALAPPDATA 'nixos-recovery-known_hosts'
$sshBase = @(
    '-i', $IdentityFile,
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=10',
    '-o', 'ServerAliveInterval=15',
    '-o', 'ServerAliveCountMax=2',
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', "UserKnownHostsFile=$knownHosts",
    "$UserName@$HostName"
)

function Invoke-RecoverySsh {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteCommand,
        [switch]$AllowDisconnect
    )

    & ssh.exe @sshBase $RemoteCommand
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowDisconnect) {
        throw "SSH command failed with exit code $exitCode."
    }
}

function Assert-Target {
    if ([string]::IsNullOrWhiteSpace($Target)) {
        throw '-Target is required.'
    }
    if ($Target -notmatch '^/dev/disk/by-id/[A-Za-z0-9._:+-]+$') {
        throw "Invalid target disk path: $Target"
    }
}

switch ($Command) {
    'Status' {
        Invoke-RecoverySsh 'sudo -n recovery-status'
    }

    'Diagnose' {
        Assert-Target
        Invoke-RecoverySsh "sudo -n recovery-ssd-diagnose --target '$Target'"
    }

    'Restore' {
        Assert-Target
        if ([string]::IsNullOrWhiteSpace($ConfirmSerial)) {
            throw '-ConfirmSerial is required for Restore.'
        }
        if ($ConfirmSerial -notmatch '^[A-Za-z0-9._:-]+$') {
            throw 'ConfirmSerial contains unsupported characters.'
        }
        Invoke-RecoverySsh "sudo -n recovery-restore-ssd --target '$Target' --confirm-serial '$ConfirmSerial' --destroy-target-ssd"
    }

    'RebootAndWait' {
        Invoke-RecoverySsh 'sudo -n systemctl reboot' -AllowDisconnect

        $deadline = [DateTimeOffset]::Now.AddMinutes(3)
        $observedOffline = $false
        while ([DateTimeOffset]::Now -lt $deadline) {
            $online = Test-NetConnection -ComputerName $HostName -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue
            if (-not $online) {
                $observedOffline = $true
            }
            elseif ($observedOffline) {
                Invoke-RecoverySsh 'sudo -n recovery-status'
                return
            }
            Start-Sleep -Seconds 3
        }
        throw 'The recovery host did not complete a verified SSH reboot cycle within 3 minutes.'
    }
}
