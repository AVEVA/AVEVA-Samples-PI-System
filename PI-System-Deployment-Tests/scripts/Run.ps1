<#
.SYNOPSIS
    Runs the full work flow of OSIsoft PI System Deployment Tests

.DESCRIPTION
    The work flow consists of following steps:
        Load test configuration,
        Test the connection to servers,
        Create the target Wind Farm AF database if needed,
        Install build tools if missing, 
        Build test solution, 
        Execute the test suite,
        Optionally remove the Wind Farm PI database.

.PARAMETER Preliminary
    Switch to build and run the PreliminaryCheck tests

.PARAMETER Setup
    Switch to set up the target AF database

.PARAMETER Testing
    Switch to build and run all tests

.PARAMETER TestClass
    Name of the xUnit test class to run.  If set, the script will run all tests in the class. The Testing switch is optional.

.PARAMETER TestName
    Name of the xUnit test to run.  If set, only the single test will be run. The TestClass parameter is required.
    
.PARAMETER Cleanup
    Switch to remove the test environment

.PARAMETER Force
    Switch to suppress confirmation prompts

.EXAMPLE
.\run.ps1
Run the full work flow

.EXAMPLE
.\run.ps1 -f
Run the full work flow without confirmation prompts

.EXAMPLE
.\run.ps1 -p
Set up the target AF Database

.EXAMPLE
.\run.ps1 -s
Set up the target AF Database

.EXAMPLE
.\run.ps1 -s -f
Set up the target AF Database without confirmation prompts

.EXAMPLE
.\run.ps1 -t
Run xUnit tests 

.EXAMPLE
.\run.ps1 -t -f
Run xUnit tests without confirmation prompts

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass"
Run a specific xUnit test class

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass"
Run a specific xUnit test class

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass" -f
Run a specific xUnit test class without confirmation prompts

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass" -TestName "MyTest"
Run a specific xUnit test

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass" -TestName "MyTest" -f
Run a specific xUnit test without confirmation prompts

.EXAMPLE
.\run.ps1 -c
Clean up all test related PI/AF components

.EXAMPLE
.\run.ps1 -c -f
Clean up all test related PI/AF components without confirmation prompts
#>
#requires -version 4.0
[CmdletBinding()]
Param (
    [Alias('p')]
    [switch]$Preliminary,

    [Alias('s')]
    [switch]$Setup,
    
    [Alias('t')]
    [switch]$Testing,

    [String]$TestClass = '',

    [String]$TestName = '',

    [Alias('c')]
    [switch]$Cleanup,

    [Alias('f')]
    [switch]$Force
)

$MinimumOSIPSVersion = New-Object System.Version("2.2.2.0")
$OSIPSModule = Get-Module -ListAvailable -Name OSIsoft.PowerShell
$OSIPSVersion = (Get-Item $OSIPSModule.Path).VersionInfo.ProductVersion
if ((-not $OSIPSModule) -or ($OSIPSVersion -lt $MinimumOSIPSVersion)) {
    Write-Error -Message ("The script requires PI AF Client and PowerShell Tools for the PI System with a minimum " + 
        "version of 2018 SP3, please upgrade PI software and try again." + [environment]::NewLine) -ErrorAction Stop
}

. "$PSScriptRoot\common.ps1"

Add-InfoLog -Message "Start OSIsoft PI System Deployment Tests script."

Add-InfoLog -Message "Load PI System settings."
$config = Read-PISystemConfig -Force:$Force

Add-InfoLog -Message "Test connection to the specified PI Data Archive, $($config.PIDataArchive)."
$PIDAConfig = Get-PIDataArchiveConnectionConfiguration -Name $config.PIDataArchive
if (-not $PIDAConfig) {
    Add-ErrorLog -Message "Could not retrieve PI Data Archive connection information from $($config.PIDataArchive)" -Fatal
}

$PIDA = Connect-PIDataArchive -PIDataArchiveConnectionConfiguration $PIDAConfig -ErrorAction Stop

Add-InfoLog -Message "Test connection to the specified AF server, $($config.AFServer)."
$PISystems = New-Object OSIsoft.AF.PISystems
$PISystem = $PISystems[$config.AFServer]
if (-not $PISystem) {
    Add-ErrorLog -Message "Cannot find the specified AF Server, $($config.AFServer)." -Fatal
}

# If testing related parameters are specified, set runTests flag to true.
$runTests = ($Testing.IsPresent -or ($TestClass -ne '') -or ($TestName -ne '')) -and -not $Preliminary.IsPresent

# Three major steps in the work flow are Setup, Testing and Cleanup.  One may choose to run one or more steps.
# If no particular switch is specified, the script will run all steps.
$runAll = -not ($Preliminary -or $Setup -or $runTests -or $Cleanup)

# Run PreliminaryChecks xUnit tests
if ($Preliminary -or $runAll) {
    Add-InfoLog -Message "Build xUnit tests."
    Build-Tests

    Add-InfoLog -Message "Run PreliminaryChecks xUnit tests."
    Start-PrelimTesting
}

# Run setup steps
if ($Setup -or $runAll) {
    Add-InfoLog -Message "Set up the target AF database."
    $SetTargetDatabaseParams = @{
        PISystem = $PISystem
        Database = $config.AFDataBase
        PIDA     = $PIDA
        Force    = $Force
    }
    Set-TargetDatabase @SetTargetDatabaseParams
}

# Run xUnit tests
if ($runTests -or $runAll) {
    Add-InfoLog -Message "Test connection to the target AF database, $($config.AFDatabase), on $($config.AFServer)."
    $TargetDatabase = $PISystem.Databases[$config.AFDatabase]
    if (-not $TargetDatabase) {
        Add-ErrorLog -Message ("Cannot find the specified AF database, $($config.AFDatabase)," + 
            " on $($config.AFServer).") -Fatal
    }

    if (-not $runAll) {
        Add-InfoLog -Message "Build xUnit tests."
        Build-Tests
	}

    if ($TestName -ne '' -and $TestClass -ne '') {
        Add-InfoLog -Message "Run xUnit test '$TestName'."
        Start-Testing -TestClassName "$TestClass" -TestName "$TestName"
    }
    elseif ($TestName -eq '' -and $TestClass -ne '') {
        Add-InfoLog -Message "Run xUnit test class '$TestClass'."
        Start-Testing -TestClassName "$TestClass"
    }
    elseif ($TestName -eq '' -and $TestClass -eq '') {
        Add-InfoLog -Message "Run xUnit tests."
        Start-Testing
    }
    else {
        Add-ErrorLog -Message "Incorrect usage for test runs. Correct usage: '.\run.ps1 -t (Optional)-TestClass 'MyTestClass' (Optional, Requires TestClass)-TestName 'MyTest' (Optional)-f'" -Fatal
    }
}

# Run cleanup steps
if ($Cleanup -or $runAll) {
    Add-InfoLog -Message "Remove all test related components."
    $RemoveTargetDatabaseParams = @{
        PISystem = $PISystem
        Database = $config.AFDataBase
        PIDA     = $PIDA
        Force    = $Force
    }
    Remove-TargetDatabase @RemoveTargetDatabaseParams
}

Disconnect-PIDataArchive -Connection $PIDA > $null

Add-InfoLog -Message "OSIsoft PI System Deployment Tests script finished."