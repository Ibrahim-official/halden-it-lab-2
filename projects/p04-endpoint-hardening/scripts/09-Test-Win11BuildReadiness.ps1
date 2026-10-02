<#
.SYNOPSIS
  Guarded no-op used to verify the Windows 11 baseline against the current Microsoft release.
.DESCRIPTION
  Deliberately small. It records which Windows 11 release the lab is hardening against and checks
  that the client build is at or above it, so nobody hardens a stale image. It also prints where to
  confirm the current build number, supported CPU list and ASR rule list on Microsoft Learn.

  It changes nothing, which is why it is the safe first command on a new client.
.PARAMETER ComputerName
  Clients to report on. Default WS01.
.PARAMETER ExpectedBuild
  Build number the lab targets. Default 22631 (Windows 11 23H2). Update after checking the Microsoft
  Windows 11 release information page.
.PARAMETER Domain
  Lab domain DNS name. The script refuses to run outside it.
.EXAMPLE
  .\09-Test-Win11BuildReadiness.ps1 -ComputerName WS01 -WhatIf
.NOTES
  Read-only. ASR rule GUIDs and supported CPUs change between releases; verify each against
  Microsoft Learn before a phase runs, and record any change in DECISIONS.md.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$ComputerName = @('WS01'),
    [int]$ExpectedBuild = 22631,
    [string]$Domain = 'ad.halden.internal'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Get-ADDomain).DNSRoot -ne $Domain) { throw 'Not the Halden lab domain. Aborting.' }

Write-Host 'References to confirm before hardening (Microsoft Learn):'
Write-Host '  - Windows 11 release information / current build numbers'
Write-Host '  - Windows 11 supported Intel and AMD processors'
Write-Host '  - Attack surface reduction rules reference (rule GUIDs and applicability)'
Write-Host ''

foreach ($computer in $ComputerName) {
    if (-not $PSCmdlet.ShouldProcess($computer, 'Report Windows 11 build readiness (read-only)')) { continue }
    try {
        $info = Invoke-Command -ComputerName $computer -ScriptBlock {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem
            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                Caption      = $os.Caption
                Version      = $os.Version
                Build        = [int]$os.BuildNumber
            }
        }
        $meets = $info.Build -ge $ExpectedBuild
        Write-Host ("{0}: {1} build {2} - {3}" -f $info.ComputerName, $info.Caption, $info.Build,
            $(if ($meets) { 'meets the lab target' } else { "below the lab target ($ExpectedBuild)" }))
    }
    catch {
        Write-Warning ("Could not query {0}: {1}" -f $computer, $_.Exception.Message)
    }
}
