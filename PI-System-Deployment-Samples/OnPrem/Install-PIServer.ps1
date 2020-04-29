<#
.SYNOPSIS
	Installs the PI Server on Windows Server 2016 or Windows 10, 64-bit architecture only.
	
.DESCRIPTION
	Installs SQL Server Express, PI Server, and optional PI Connector and performs configuration tasks.	
	Only components whose installers are passed as parameters are installed.

.PARAMETERS

.PARAMETER sql
    Path to Microsoft SQL Server Express installer. Installs only if specified.

.PARAMETER piserver
    Path to PI Server installer. Installs only if specified.

.PARAMETER pilicdir
    Specifies the directory containing the pilicense.dat file. Defaults to the local directory.
    
.PARAMETER pidrive
    Specifies the drive letter to use for PI Archive/Queue files. Defaults to D:\, or C:\ if no D:\ is found.

.PARAMETER afdatabase
	Specifies a PI AF Database to create after PI Server install. Creates only if specified.

.PARAMETER pibundle
    Specifies a self-extracting PI install kit. Installs only if specified.
    This parameter can be used to install most PI software other than the PI Server kit.

.PARAMETER silentini
    Specifies a silent.ini to use with the self-extracting PI install kit. If not specified, will use the default silent.ini.

.PARAMETER dryRun
    Specifies to run the script in Dry-Run mode. Logs will be written, but no install/configuration actions will occur.

.PARAMETER remote
    Specifies script is being run by remote PowerShell session. This flag is used by the test pipeline.

.EXAMPLES

.EXAMPLE
	> .\Install-PIServer.ps1 -sql C:\Kits\SQL\Setup.exe -piserver C:\Kits\PI\PI-Server.exe -pibundle C:\Kits\PI\PIProcessBook.exe
	
    Installs Microsoft SQL Server Express, installs PI Server 'typical' components (including PI Data Archive and PI AF Server),
    and installs PI ProcessBook using its self-extracting install kit.

.EXAMPLE
	> .\Install-PIServer.ps1 -sql C:\Kits\SQL\Setup.exe
	
	Installs Microsoft SQL Server Express only.

.NOTES
  This is a sample script and is not signed. It may be necessary to disable the restrictions on
  ExecutionPolicy: Set-ExecutionPolicy Unrestricted
#>

#region Parameters
param(
    # TODO: Investigate Powershell 'ini' or config file
    [string]$sql, # Path to SQL Server Express install kit
    [string]$piserver, # Path to PI Server install kit
    [string]$pilicdir, # Directory containing pilicense file to use
    [string]$pidrive, # Drive letter to use for PI Data Archive
    [string]$afdatabase, # Optional PI AF Database to create after install
    [string]$pibundle, # Path to self-extracting PI install kit
    [string]$silentini, # Path to silent.ini for self-extracting PI install kit
    [switch]$dryRun, # Dry run, log but do not install
    [switch]$remote # Remote PowerShell
)
#endregion

#region Startup
# Start stopwatch as soon as possible!
$StartTime = Get-Date -f "yyyy-MM-ddTHH-mm-ss"
$Time = [System.Diagnostics.Stopwatch]::StartNew()
$LogFile = ".\Install-PIServer $StartTime.log"
$PiServerLogFile = ".\Install-PIServer $StartTime.piserver.log"
$SqlInstance = "SQLExpress"
$ErrorActionPreference = "Stop"
Write-Output "Using log file: $LogFile"
#endregion

#region Helper Functions
function Write-Log([string]$outputText) {
    Write-Output $outputText | Out-File -Force -FilePath $LogFile -Append
}

function Write-LogError([string]$outputText) {
    Write-Log $outputText
    throw $outputText
}

function Write-LogFunction([string]$functionName, [string]$outputText) {
    Write-Log "${functionName}: $outputText"
}

function Write-LogFunctionError([string]$functionName, [string]$outputText) {
    Write-LogError "${functionName}: $outputText"
}

function Write-LogFunctionEnter([string]$functionName) {
    Write-Log "${functionName}: Entering Function"
}

function Write-LogFunctionExit([string]$functionName, [string]$elapsedTime) {
    if ($elapsedTime -ne "") {
        Write-Log "${functionName}: Exiting Function, Elapsed time: $elapsedTime"
    }
    else {
        Write-Log "${functionName}: Exiting Function"
    }
}
#endregion

#region Script Functions
function Confirm-System() {
    $func = "Confirm-System"
    Write-LogFunctionEnter $func

    Write-LogFunction $func "Checking System Compatibility..."

    # Check that this is a 64-bit system
    $bitness = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
    if ($bitness -NotLike "*64*") {
        Write-LogFunctionError $func "Operating System not supported. This script is intended for 64 bit systems only."
    }

    # Check that this is Windows major version 10
    $osVersion = (Get-WmiObject Win32_OperatingSystem).Version
    if (-not ($osVersion -like "10.0*")) {
        Write-LogFunctionError $func "Operating system not supported. This script is intended for Windows Server 2016 or Windows 10 systems only."
    }

    Write-LogFunction $func "System compatibility checked"
    Write-LogFunctionExit $func
}

function Confirm-Params() {
    $func = "Confirm-Params"
    Write-LogFunctionEnter $func

    Write-LogFunction $func "Checking Script Parameters..."

    # Checks for SQL Server Express
    if ($sql -ne "") {
        # Installing SQL Server Express
        if (Test-Path $sql -type leaf) {
            Write-LogFunction $func "Found SQL Server Express install kit at: '$sql'"
        }
        else {
            Write-LogFunctionError $func "Failed to find SQL Server Express install kit at: '$sql'"
        }
    }

    # Checks for PI Server
    if ($piserver -ne "") {
        # Installing PI Server
        if (Test-Path $piserver -type leaf) {
            Write-LogFunction $func "Found PI Server install kit at: '$piserver'"
        }
        else {
            Write-LogFunctionError $func "Failed to find PI Server install kit at: '$piserver'"
        }

        # Check that PI drive can be found
        if ($pidrive -ne "") {
            # Specified drive as parameter, check it exists
            $testDrive = "${pidrive}:"
            if ((Test-Path $testDrive) -and (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$testDrive'").DriveType -eq [int]3) {
                $PiDirectory = "$testDrive\PI"
            }
            else {
                Write-LogFunctionError $func "PI Drive specified '$pidrive' was not found."
            }
        }
        else {
            # No specified drive, try D: or C:
            if ((Test-Path D:) -and (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='D:'").DriveType -eq [int]3) {
                $PiDirectory = "D:\PI"
            }
            elseif ((Test-Path C:) -and (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'").DriveType -eq [int]3) {
                $PiDirectory = "C:\PI"
            }
            else {
                Write-LogFunctionError $func "Failed to find local D: or C: drive for PI Data Archive directory. Please specify a drive using the -pidrive parameter."
            }
        }

        Set-Variable PiDirectory "$PiDirectory" -Scope Script
        Write-LogFunction $func "Will use '$PiDirectory' as PI Data Archive directory"

        # Check that pilicense.dat can be found
        if ($pilicdir -ne "") {
            # Specified pilicdir as parameter, check pilicense.dat exists
            if (-not(Test-Path "$pilicdir\pilicense.dat" -type leaf)) {
                Write-LogFunctionError $func "Failed to find pilicense in folder: '$pilicdir'"
            }
        }
        else {
            # No specified pilicense, try .\pilicense.dat
            $pilicdir = "."
            if (-not (Test-Path "$pilicdir\pilicense.dat" -type leaf)) {
                Write-LogFunctionError $func "Failed to find local pilicense.dat. Please specify a pilicense using the -pilicense parameter."
            }
        }

        $resolvedPath = Resolve-Path $pilicdir
        if ($pilicdir -ne $resolvedPath.Path) {
            Write-LogFunction $func "Specified pilicdir '$pilicdir' appears to be a relative path, kit requires absolute path"
            Write-LogFunction $func "Resolved pilicdir '$pilicdir' to '$($resolvedPath.Path)'"
            $pilicdir = $resolvedPath.Path
        }

        Set-Variable pilicdir "$pilicdir" -Scope Script
        Write-LogFunction $func "Found pilicense.dat in folder: '$pilicdir'"
    }

    # Checks for PI Bundle
    if ($pibundle -ne "") {
        # Installing PI Bundle
        if (Test-Path $pibundle -type leaf) {
            Write-LogFunction $func "Found self-extracting PI install kit at: '$pibundle'"
        }
        else {
            Write-LogFunctionError $func "Failed to find self-extracting PI install kit at: '$pibundle'"
        }

        # Check that 7zip can be found
        $7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"
        if (-not (Test-Path $7zipPath -type leaf)) {
            Write-LogFunctionError $func "Failed to find 7-Zip at: '$7zipPath', ensure it is installed"
        }

        Set-Variable 7zipPath "$7zipPath" -Scope Script
        Write-LogFunction $func "Found 7-Zip at: '$7zipPath'"

        # If specified, check that silent.ini can be found
        if ($silentini -ne "") {
            if (Test-Path $silentini -type leaf) {
                Write-LogFunction $func "Found silent.ini at: '$silentini'"
            }
            else {
                Write-LogFunctionError $func "Failed to find silent.ini at: '$silentini'"
            }
        }
    }

    Write-LogFunction $func "Script parameters checked"
    Write-LogFunctionExit $func
}

function Install-SQLServerExpress() {
    $func = "Install-SQLServerExpress"
    Write-LogFunctionEnter $func
 
    $fTime = [System.Diagnostics.Stopwatch]::StartNew()

    Write-LogFunction $func "Installing Microsoft SQL Server Express..."
    Write-LogFunction $func "Using install kit: '$sql'"

    $params = 
    @(
        "/Q",
        "/IACCEPTSQLSERVERLICENSETERMS=TRUE",
        "/ACTION=INSTALL",
        "/FEATURES=SQLENGINE,FULLTEXT",
        "/INSTANCENAME=$SqlInstance",
        "/UPDATEENABLED=FALSE",
        "/SQLCOLLATION=SQL_LATIN1_GENERAL_CP1_CI_AS",
        "/SQLSYSADMINACCOUNTS=BUILTIN\ADMINISTRATORS"
    )

    if ($remote -eq $true) {
        # Install kit auto update does not work from remote PowerShell session
        $params += ("/UPDATEENABLED=FALSE")
    }

    if ($dryRun -ne $true) {
        Write-LogFunction $func "Starting install..."
        # Begin install attempt using defined parameters
        $rc = Start-Process -FilePath $sql -ArgumentList $params -Wait -PassThru
    
        if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010)) {
            # 3010 means ok, but need to reboot
            Write-LogFunctionError $func "Microsoft SQL Server Express Installation failed with error code: $($rc.ExitCode)"
        }
    }
    else {
        Write-LogFunction $func "DryRun: Parameters: '$params'"
        Write-LogFunction $func "DryRun: Skipping install"
    }

    Write-LogFunction $func "Microsoft SQL Server Express installation completed"
    Write-LogFunctionExit $func $fTime.Elapsed.ToString()
}

function Install-PIServer() {
    $func = "Install-PIServer"
    Write-LogFunctionEnter $func
	
    $fTime = [System.Diagnostics.Stopwatch]::StartNew()

    Write-LogFunction $func "Installing PI Server..."
    Write-LogFunction $func "Using install kit: '$piserver'"
    Write-LogFunction $func "Using license directory: '$pilicdir'"
    Write-LogFunction $func "Using archive/queue directory: '$PiDirectory'"

    if ($sql -ne "") {
        # Check that SQL is running
        $sqlservice = Get-Service -DisplayName "SQL Server ($SqlInstance)" -ErrorAction SilentlyContinue
        $preference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        if ($sqlservice.Status -ne "Running") {
            Write-LogFunctionError $func "SQL Server ($SqlInstance) was not found or is not running."
        }
        $ErrorActionPreference = $preference
    }

    $params =
    @(
        "/Q",
        "/NORESTART",
        "/LOG .\$PiServerLogFile"
        "REBOOT=Suppress",
        "ADDLOCAL=TYPICAL",
        "FDSQLDBSERVER=.\$SqlInstance",
        "AFCLIENT_SHUTDOWN_OPTIONS=2",
        "PI_LICDIR=$pilicdir",
        "PI_INSTALLDIR=$PiDirectory"
        "PI_ARCHIVEDATDIR=$PiDirectory\Archives\",
        "PI_FUTUREARCHIVEDATDIR=$PiDirectory\Archives\Future\",
        "PI_EVENTQUEUEDIR=$PiDirectory\Queues\",
        "PI_ARCHIVESIZE=256",
        "PI_AUTOCREATEARCHIVES=1"
    )
   
    if ($dryRun -ne $true) {
        Write-LogFunction $func "Starting install..."
        $rc = Start-Process $piserver -ArgumentList $params -Wait -PassThru -NoNewWindow
    
        if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010)) {
            # 3010 means ok, but need to reboot
            Write-LogFunctionError $func "PI Server Installation failed with error code: $($rc.ExitCode)"
        }
    }
    else {
        Write-LogFunction $func "DryRun: Parameters: '$params'"
        Write-LogFunction $func "DryRun: Skipping install"
    }

    Write-LogFunction $func "PI Server installation completed"
    Write-LogFunctionExit $func $fTime.Elapsed.ToString()
}

function Update-Environment {
    $func = "Update-Environment"
    Write-LogFunctionEnter $func

    Write-LogFunction $func "Updating PowerShell PATH with new PI variables..."

    # Use the Environment registry entries to update PATH with variables created by PI Installer
    $locations = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    'HKCU:\Environment'

    if ($dryRun -eq $true) {
        Write-LogFunction $func "DryRun: List variables found but do not modify path"
    }

    $locations | ForEach-Object {
        $k = Get-Item $_
        $k.GetValueNames() | ForEach-Object {
            $name = $_
            $value = $k.GetValue($_)

            if ($dryRun -eq $true) {
                Write-LogFunction $func "DryRun: Found variable '$name' with value '$value'"
            }
            elseif ($userLocation -and $name -ieq 'PATH') {
                $Env:Path += ";$value"
            }
            else {
                Set-Item -Path Env:\$name -Value $value
            }
        }

        $userLocation = $true
    }

    Write-LogFunction $func "PowerShell PATH updated"
    Write-LogFunctionExit $func
}

function Add-InitialAFDatabase() {
    $func = "Add-InitialAFDatabase"
    Write-LogFunctionEnter $func

    Write-LogFunction $func "Adding PI AF Database..."
    if ($dryRun -eq $true) {
        Write-LogFunction $func "DryRun: Skipping 'Get-AFServer -Name $env:computername'"
        Write-LogFunction $func "DryRun: Skipping 'Add-AFDatabase -Name $afdatabase' -AFServer {server}"
    }
    else {
        $afserver = Get-AFServer -Name $env:computername
        Add-AFDatabase -Name $afdatabase -AFServer $afserver
    }

    Write-LogFunction $func "PI AF Database added"
    Write-LogFunctionExit $func
}

function Expand-PIBundle() {
    $func = "Expand-PIBundle"
    Write-LogFunctionEnter $func

    Write-LogFunction $func "Expanding self-extracting PI install exe..."
    $baseName = (Get-Item $pibundle).BaseName

    if ($dryRun -eq $true) {
        Write-LogFunction $func "DryRun: Skipping 7zip extraction of '$pibundle' to directory '$baseName'"
    }
    else {
        Write-LogFunction $func "Starting 7zip..."
        $rc = Start-Process -FilePath $7zipPath -ArgumentList "x -y -o""$baseName"" ""$pibundle""" -Wait -PassThru -NoNewWindow

        if ($rc.ExitCode -ne 0) {
            # 0 means ok
            Write-LogFunctionError $func "Expanding self-extracting PI install exe failed with error code: $($rc.ExitCode)"
        }
    }

    Write-LogFunction $func "Self-extracting PI install exe expanded"
    Write-LogFunctionExit $func
}

function Install-PIBundle() {
    $func = "Install-PIBundle"
    Write-LogFunctionEnter $func

    $fTime = [System.Diagnostics.Stopwatch]::StartNew()

    Write-LogFunction $func "Installing PI setup kit..."    
    $baseName = (Get-Item $pibundle).BaseName
    $silentIniPath = $silentini

    if ($silentini -eq "") {
        # Use default silent.ini
        $silentIniPath = ".\$basePath\silent.ini"
    }

    if ($dryRun -eq $true) {
        Write-LogFunction $func "DryRun: Skipping install using '.\$baseName\Setup.exe' with silent ini '$silentIniPath'"
    }
    else {
        $rc = Start-Process -FilePath ".\$baseName\Setup.exe" -ArgumentList "-f ""$silentIniPath""" -Wait -PassThru -NoNewWindow
        
        if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010)) {
            # 3010 means ok, but need to reboot
            Write-LogFunctionError $func "Installing PI setup kit failed with error code: $($rc.ExitCode)"
        }
    }
	
    Write-LogFunction $func "PI setup kit installed"
    Write-LogFunctionExit $func $fTime.Elapsed.ToString()
}
#endregion

#region Main Script Body
Write-Log "Checking system and script parameters"
Confirm-System
Confirm-Params
Write-Log ""

# Run SQL Server Express Install
if ($sql -ne "") {
    Write-Log "-sql flag specified, starting SQL Server Express Install"
    Install-SQLServerExpress
}
else {
    Write-Log "-sql flag not specified, skipping SQL Server Express Install"
}
Write-Log ""

# Run PI Server Install
if ($piserver -ne "") {
    Write-Log "-piserver flag specified, starting PI Server Install"
    Install-PIServer
    Update-Environment
    if ($afdatabse -ne "") {
        Add-InitialAFDatabase
    }
}
else {
    Write-Log "-piserver flag not specified, skipping PI Server Install"
}
Write-Log ""

# Run PI Bundle Install
if ($pibundle -ne "") {
    Write-Log "-pibundle flag specified, starting PI Bundle Install"
    Expand-PIBundle
    Install-PIBundle
}
else {
    Write-Log "-pibundle flag not specified, skipping PI Bundle Install"
}
Write-Log ""
#endregion

#region Completion Messages
$elapsed = $Time.Elapsed.ToString()
$EndTime = Get-Date -f "MM-dd-yyyy HH:mm:ss"

Write-Output "Script started at: '$StartTime'"
Write-Output "Script ended at: '$EndTime'"
Write-Output "Total elapsed time: '$elapsed'"

Write-Log "Script started at: '$StartTime'"
Write-Log "Script ended at: '$EndTime'"
Write-Log "Total elapsed time: '$elapsed'"

Write-Output "Complete!"
Write-Log "Complete!"
#endregion
