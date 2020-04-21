param (
    # force P to fail when I leave `dt` in the tests
    [switch]$CI,
    [switch]$SkipPTests,
    [switch]$NoBuild,
    [string[]] $File
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# assigning error view explicitly to change it from the default on powershell 7 (travis ci macOS right now)
$ErrorView = "NormalView"
"Using PS $($PsVersionTable.PSVersion)"

if (-not $NoBuild) {
    & "$PSScriptRoot/build.ps1"
}

# remove pester because we will be reimporting it in multiple other places
Get-Module Pester | Remove-Module

if (-not $SkipPTests) {
    $result = @(Get-ChildItem $PSScriptRoot/tst/*.ts.ps1 -Recurse |
        foreach {
            $r = & $_.FullName -PassThru
            if ($r.Failed -gt 0) {
                [PSCustomObject]@{
                    FullName = $_.FullName
                    Count = $r.Failed
                }
            }
        })


    if (0 -lt $result.Count) {
        Write-Host -ForegroundColor Red "P tests failed!"
        foreach ($r in $result) {
            Write-Host -ForegroundColor Red "$($r.Count) tests failed in '$($r.FullName)'."
        }

        if ($CI) {
            exit 1
        }
        else {
            return
        }
    }
    else {
        Write-Host -ForegroundColor Green "P tests passed!"
    }
}

# reset pester and all preferences
$PesterPreference = [PesterConfiguration]::Default
Get-Module Pester | Remove-Module

Import-Module $PSScriptRoot/bin/Pester.psd1 -ErrorAction Stop

# add our own in module scope because the implementation
# pester relies on being in different sesstion state than
# the module scope target
Get-Module TestHelpers | Remove-Module
New-Module -Name TestHelpers -ScriptBlock {
    function InPesterModuleScope {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [scriptblock]
            $ScriptBlock
        )

        $module = Get-Module -Name Pester -ErrorAction Stop
        . $module $ScriptBlock
    }
} | Out-Null


$configuration = [PesterConfiguration]::Default

$configuration.Debug.WriteDebugMessages = $false
# $configuration.Debug.WriteDebugMessagesFrom = 'CodeCoverage'

$configuration.Debug.ShowFullErrors = $true
$configuration.Debug.ShowNavigationMarkers = $true

if ($null -ne $File -and 0 -lt @($File).Count) {
    $configuration.Run.Path = $File
}
else
{
    $configuration.Run.Path = "$PSScriptRoot/tst"
}
$configuration.Run.ExcludePath = '*/demo/*', '*/examples/*', '*/testProjects/*'
$configuration.Run.PassThru = $true

$configuration.Filter.ExcludeTag = 'VersionChecks', 'StyleRules', 'Help'

$configuration.Output.Verbosity = 'Minimal'

if ($CI) {
    $configuration.Run.Exit = $true

    # skipping cc and tr because I don't need them right now and cc is extremely slow
    # $configuration.CodeCoverage.Enabled = $true
    # $configuration.CodeCoverage.Path = "$PSScriptRoot/src/*"

    # $configuration.TestResult.Enabled = $true
}

$r = Invoke-Pester -Configuration $configuration
if ("Failed" -eq $r.Result) {
    throw "Run failed!"
}