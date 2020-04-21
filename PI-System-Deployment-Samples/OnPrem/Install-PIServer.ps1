<#
.SYNOPSIS
	Installs the PI Server on Windows Server 2016 or Windows 10, 64-bit architecture only.
	
.DESCRIPTION
	Installs SQL Server Express, PI Server, and optional PI Connector and performs configuration tasks.	
	Only components whose installers are passed as parameters are installed.

.PARAMETERS

.PARAMETER sql
    Path to Microsoft SQL Server Express installer. Installs only if specified.

.PARAMETER pilicensefile
    TODO: Get this parameter working
	Specifies the license file to use for the Advanced Continuous Historian.

.PARAMETER afdatabase
	Specifies the default PI Asset Framework database name for the PI Connector. Default is Database1.

.PARAMETER ach
    TODO: Rename parameter, consider separating into 'pida' and 'piaf' flags
    Installs the Advanced Continuous Historian components, which include the PI Data Archive and the PI AF Server
	as deployed via the PI Server Installer.

.PARAMETER sc
    TODO: Rename parameter, suggest 'conn' or 'picon'
    Installs the Emerson DeltaV Smart Connector.

.PARAMETER archives
    TODO: Explain exactly what this means, how many extra archives, what type, etc
	Creates additional archives. This option is not run by default and can only be run after installation and a reboot.

.EXAMPLES

.EXAMPLE
	> .\Install-PIServer.ps1 
	
	Installs all components required for the Advanced Continuous Historian

    Uses self-extracting setup kit EXE files to deploy OSIsoft software

.EXAMPLE
	> .\Install-PIServer.ps1 -sql
	
	Install Microsoft SQL Server Express

.NOTES
  This is a sample script and is not signed. It may be necessary to disable the restrictions on
  ExecutionPolicy: Set-ExecutionPolicy Unrestricted
#>

#region Parameters
param(
    # TODO: Investigate Powershell 'ini' or config file
    [string]$pilicense, # location of license file to use
    [string]$afdatabase = "Database1", # default PI AF database name for PI Connector
    [string]$sql, # Path to SQL Server Express install kit
    [string]$piserver, # Path to PI Server install kit
    [string]$piconn, # Path to PI Connector install kit
    [string]$pidrive, # Drive letter to use for PI Data Archive
    [switch]$archives, # Create 2 additional archives
    [switch]$dryRun # Dry run, log but do not install
)
#endregion

#region Startup
# Start stopwatch as soon as possible!
$StartTime = Get-Date -f "yyyy-MM-ddTHH-mm-ss"
$Time = [System.Diagnostics.Stopwatch]::StartNew()
$LogFile = ".\Install-PIServer $StartTime.log"
$SqlInstance = "SQLExpress"
Write-Output "Using log file: $LogFile"
#endregion

#region Helper Functions
function LogOutFile([string]$outputText) {
    Write-Output $outputText | Out-File -FilePath $LogFile -Append
}

function LogMessage([string]$outputText) {	
    LogOutFile $outputText
    Write-Output $outputText
}

function LogError([string]$outputText) {
    LogOutFile $outputText
    throw $outputText
}

function LogFunction([string]$functionName, [string]$outputText) {
    LogOutFile "${functionName}: $outputText"
}

function LogErrorFunction([string]$functionName, [string]$outputText) {
    LogError "${functionName}: $outputText"
}

function LogEnterFunction([string]$functionName) {
    LogOutFile "${functionName}: Entering Function"
}

function LogExitFunction([string]$functionName, [string]$elapsedTime) {
    LogOutFile "${functionName}: Exiting Function, Elapsed time: $elapsedTime"
}
#endregion

#region Install Functions
function InstallSQLServerExpress() {
    $func = "InstallSQLServerExpress"
    LogEnterFunction $func
 
    $fTime = [System.Diagnostics.Stopwatch]::StartNew()

    LogFunction $func "Installing Microsoft SQL Server Express..."
    LogFunction $func "Using install kit: $sql"

    $params = 
    @(
        "/Q",
        "/IACCEPTSQLSERVERLICENSETERMS=TRUE",
        "/ACTION=INSTALL",
        "/FEATURES=SQLENGINE,FULLTEXT",
        "/INSTANCENAME=$SQLInstance",
        "/SQLCOLLATION=SQL_LATIN1_GENERAL_CP1_CI_AS",
        "/SQLSYSADMINACCOUNTS=BUILTIN\ADMINISTRATORS"
    )

    if ($dryRun -ne $true) {
        # Begin install attempt using defined parameters
        $rc = Start-Process -FilePath $sql -ArgumentList $params -Wait -PassThru
    
        if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010)) {
            # 3010 means ok, but need to reboot
            Read-Host
            LogErrorFunction $func "Microsoft SQL Server Express Installation Failed with error code: $($rc.ExitCode)"
        }
    }
    else {
        LogFunction $func "DryRun: Skipping install"
    }

    LogFunction $func "Microsoft SQL Server Express Installation Completed"
    LogExitFunction $func $fTime.Elapsed.ToString()
}

function InstallPIServer() { 
    $func = "InstallPIServer"
    LogEnterFunction $func
	
    $fTime = [System.Diagnostics.Stopwatch]::StartNew()

    LogFunction $func "Installing PI Server..."
    LogFunction $func "Using install kit: $piserver, license: $pilicense"

    # Check that SQL is running
    $sqlservice = Get-Service -DisplayName "SQL Server ($SQLInstance)" -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Continue"     
    if (-not ($sqlservice.Status -eq "Running")) {
        LogErrorFunction $func "SQL Server ($SQLInstance) was not found or is not running."
    }
   

    # TODO: Likely we should have scripts require .NET 4.8 as a prerequisite
    # TODO: If included in the kit and can be directly extracted, then worthwhile to try to run it
    $net48 = ".\ndp48-x86-x64-allos-enu.exe"

    if ($pilicense) {
        if (Test-Path $pilicense -pathtype container) {
            Write-Output "`nInstallPIDataArchive function: if...container branch: Moving PI license file to the proper location, $myTempDir, if license file is present: $pilicense"
            LogOutputFileText $false " "
            LogOutputFileText $false "InstallPIDataArchive function: if...container branch: Moving PI license file to the proper location, $myTempDir, if license file is present: $pilicense"
            
            $pilicense = "$pilicense\pilicense.dat" # Addresses the case where the $pilicense parameter is fed in from the command line
            Copy-Item $pilicense $myTempDir\pilicense.dat
        }
        
        if (Test-Path $pilicense -pathtype leaf) {
            # If it's a real file, install it as the pilicense.dat that the
            # PI Data Archive's silent installer needs
            #
            Write-Output "`nInstallPIDataArchive function: if...leaf branch: Moving PI license file to the proper location, $myTempDir, if license file is present: $pilicense"
            LogOutputFileText $false " "
            LogOutputFileText $false "InstallPIDataArchive function:  if...leaf branch:  Moving PI license file to the proper location, $myTempDir, if license file is present: $pilicense"

            Copy-Item $pilicense $myTempDir\pilicense.dat
        }
        else {
            LogOutputFileText $true "InstallPIDataArchive function: Cannot find PI license file for use in installation: $pilicense`n"
            throw "InstallPIDataArchive function: Cannot find PI license file for use in installation: $pilicense`n"
        }
    }
    		
    LogFileAndOutputText $false "`nInstallPIServerInstaller function: Check .NET 4.8 framework installed"
	
    # .NET 4.8 installed? If not, install and indicate likely requirement to reboot due - at a minimum - SQL Server & PowerShell processes.
    # TODO: Investigate better way to install .NET 4.8, if not feasible, make this a requirement listed in the README
	
    # https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed
    # Got .NET 4.8? If older version found, install
    if ((Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release -lt 528040) {
	
        # Check for installer
        if (Test-Path $net48 -pathtype leaf) {
            $success = $false
            LogFileAndOutputText $true "Installing .NET 4.8. Please reboot if prompted before continuing with installation."
            $success = $false
            $reboot = $false
            # install and process return code
            # https://docs.microsoft.com/en-us/dotnet/framework/deployment/guide-for-administrators#troubleshooting
            $rc = Start-Process $net48 -ArgumentList "/passive /promptrestart" -Wait -PassThru -NoNewWindow
            Switch ($rc.ExitCode) {
                0 { $success = true }
                1602 { break; } # canceled
                1603 { break; } # fatal error
                1641 { $success = $true; $reboot = $true }
                3010 { $success = $true; $reboot = $true }
                5100 { break; } # system requirements not met
                Default { break; } 
            }

            if ($success -and $reboot) {
                LogFileAndOutputExitText $true "Reboot to finish .NET 4.8 installation and rerun script."
            }
            if ($success) {
                LogFileAndOutputText $true ".NET 4.8 installed."
            }
            if (-not $success) {
                LogFileAndOutputExitText $true ".NET 4.8 installation error: $rc.ExitCode"
            }
        }
        else {
            LogFileandOutputExitText $true "InstallPIServerInstaller function: Unable to locate .NET installer: $net48, exiting."
        }
    }
    else {
        LogFileandOutputText $true ".NET 4.8 prerequisite met."
    }

    # Copy the PI Server setup kit to the working folder for silent execution
    # TODO: Check whether necessary to copy this
    Write-Output "`nInstallPIServerInstaller function: Copy the PI Server setup kit ($product) to the working folder: $myTempDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function: Copy the PI Server setup kit ($product) to the working folder: $myTempDir"

    Copy-Item $myScriptDir\$product $myTempDir -Force -errorVariable errors
    if ($errors.count -ne 0 ) {
        LogOutputFileText $true "InstallPIServerInstaller function: Error copying $product to the working folder: $workingDir"
        throw "InstallPIServerInstaller function: Error copying $product to the working folder: $workingDir"
    }
	
    # Copy the SQL Scripts folder to the working folder for silent execution
    # TODO: Check whether necessary to copy this
    Write-Output "`nInstallPIServerInstaller function: Copy the AF SQL Scripts folder to the working folder: $myTempDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function: Copy the AF SQL Scripts folder to the working folder: $myTempDir"

    $SQL_Folder = "PI AF SQL Scripts"
    Copy-Item $myScriptDir\$SQL_Folder -Destination $myTempDir -Recurse -Force -errorVariable errors
    if ($errors.count -ne 0 ) {
        LogOutputFileText $true "InstallPIServerInstaller function: Error copying AF SQL Scripts folder to the working folder: $workingDir"
        throw "InstallPIServerInstaller function: Error copying AF SQL Scripts folder to the working folder: $workingDir"
    }
	
    # Features and parameters for the installation minus drive information    
    # TODO: Review these params with teams/support, likely split to have multiple lines here
    $params =
    @(
        "/Q",
        "/NORESTART",
        "REBOOT=Suppress",
        "PI_ARCHIVEDATDIR=$pidirectory\Archives\",
        "PI_FUTUREARCHIVEDATDIR=$pidirectory\Archives\Future",
        "PI_EVENTQUEUEDIR=$pidirectory\Queues\",
        "FDSQLDBSERVER=.\ADV_CONT_HIST",
        "FDSQLDBNAME=PIFD",
        "FDSQLDBVALIDATE=0",
        "AFCLIENT_SHUTDOWN_OPTIONS=2",
        "IACCEPTSQLNCLILICENSETERMS=YES",
        "ADDLOCAL=PIDataArchive,PITotal,FD_AppsServer,FD_AFExplorer,PiPowerShell,pismt3"
    )
  
    LogFileAndOutputText $false "InstallPIServerInstaller function: Attempting to install product, $product, to the $drive drive (${drive}:\)"

    # install
    $rc = Start-Process .\$product -ArgumentList $params -Wait -PassThru -NoNewWindow

    if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010)) {
        # 3010 means ok, but need to reboot
        Pop-Location
        LogOutputFileText $true "InstallPIServerInstaller function: Installation process returned error code: $($rc.ExitCode)"
        throw "InstallPIServerInstaller function: Installation process returned error code: $($rc.ExitCode)"
    }
    
    # Execute the AF SQL Scripts
    Write-Output "`nInstallPIServerInstaller function: Attempting to install AF SQL Scripts manually"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function: Attempting to install AF SQL Scripts manually"

    # TODO: Declare these somewhere else
    $SqlScriptsExeCmd = "$myTempDir\PI AF Sql Scripts\GO.BAT"
    $SqlScriptsArgs = ".\ADV_CONT_HIST PIFD"
    $SQLExecutionOutputFile_Folder = "$myTempDir\PI AF Sql Scripts"
		
    $rc = Start-Process -FilePath $SqlScriptsExeCmd -ArgumentList $SqlScriptsArgs -WorkingDirectory $SQLExecutionOutputFile_Folder -Wait -PassThru -NoNewWindow
	
    if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010)) {
        # 3010 means ok, but need to reboot
        Pop-Location
        LogOutputFileText $true "InstallPIServerInstaller function: AF SQL Script execution returned error code: $($rc.ExitCode)"
        throw "InstallPIServerInstaller function: AF SQL Script execution returned error code: $($rc.ExitCode)"
    }
	
    # Copy the SQL Scripts execution output file to the script output log file folder
    #
    Write-Output "`nInstallPIServerInstaller function: Copy the AF SQL Scripts execution log file,PIAFSqlScriptExecution_*.txt, to the output log folder: $myLogFileDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function: Copy the AF SQL Scripts execution log file,PIAFSqlScriptExecution_*.txt, to the output log folder: $myLogFileDir"
   
    foreach ($i in Get-ChildItem -Path $SQLExecutionOutputFile_Folder -Recurse) {
        if ($i.Name -match "PIAFSqlScriptExecution_") {
            Copy-Item -Path $i.FullName -Destination $myLogFileDir -Force -errorVariable errors
        }
	
        if ($errors.count -ne 0 ) {
            LogOutputFileText $true "InstallPIServerInstaller function: Error copying AF SQL Scripts execution log file,PIAFSqlScriptExecution_*.txt, to the output log folder:  $myLogFileDir"
            throw "InstallPIServerInstaller function: Error copying AF SQL Scripts execution log file,PIAFSqlScriptExecution_*.txt, to the output log folder:  $myLogFileDir"
        }
    }
		
    # AF Service must be stopped and restarted for the SQL script changes to take effect
    # TODO: If possible, run GO.bat first then PI Server install, then this restart may not be necessary
    Write-Output "`nInstallPIServerInstaller function: Attempting to re-start Windows Service: PI AF Application Service (NT SERVICE\AFService)"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function: Attempting to re-start Windows Service: PI AF Application Service (NT SERVICE\AFService)"
    Restart-Service -Name AFService -Force
	
    # If exist, remove two local groups:
    # TODO: If groups not created on new install, remove this, likely remove this either way
    Write-Output "`nInstallPIServerInstaller function: Attempting to remove local groups, if they exist: AFServers and AFQueryEngines"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function: Attempting to remove local groups, if they exist: AFServers and AFQueryEngines"
    # First group: AFServers
    $AFServersLocalGroup = Get-LocalGroup -Name "AFServers" -EA SilentlyContinue
    $ErrorActionPreference = "Continue" 
	
    if ($AFServersLocalGroup) {
        Write-Output "`nInstallPIServerInstaller function: AFServers local group found:  Deleting AFServers local group"
        LogOutputFileText $false " "
        LogOutputFileText $false "InstallPIServerInstaller function: AFServers local group found:  Deleting AFServers local group"
       
        Remove-LocalGroup -Name "AFServers"
    }
    #	Second group: AFQueryEngine
    $AFQueryEnginesLocalGroup = Get-LocalGroup -Name "AFQueryEngines" -EA SilentlyContinue
    $ErrorActionPreference = "Continue" 

    if ($AFQueryEnginesLocalGroup) {
        Write-Output "`nInstallPIServerInstaller function: AFQueryEngines local group found: Deleting AFQueryEngines local group"
        LogOutputFileText $false " "
        LogOutputFileText $false "InstallPIServerInstaller function: AFQueryEngines local group found: Deleting AFQueryEngines local group"
       
        Remove-LocalGroup -Name "AFQueryEngines"
    }

    # Installation has completed
    #
    Write-Output "`nInstallPIServerInstaller function: Installation completed"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function: Installation completed"

    # Always return to your starting directory
    #
    Pop-Location
    Remove-Item $myTempDir\$product -recurse -force

    LogOutputFileExitFunctionText InstallPIServerInstaller

    LogExecutionTime("InstallPIServerInstaller", $fTime.Elapsed.ToString())
}

function Update-Environment {
    $fn = "Update-Environment"
    LogOutputFileEnterFunctionText($fn)

    # Using the Environment registry entry:
    #    Update Enviroment Variables to pick up variables created
    #    during the execution of the PI Installer package

    $locations = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    'HKCU:\Environment'

    $locations | ForEach-Object {
        $k = Get-Item $_
        $k.GetValueNames() | ForEach-Object {
            $name = $_
            $value = $k.GetValue($_)

            if ($userLocation -and $name -ieq 'PATH') {
                $Env:Path += ";$value"
            }
            else {
                Set-Item -Path Env:\$name -Value $value
            }
        }

        $userLocation = $true
    }

    LogOutputFileExitFunctionText($fn)
}

function Update-KSTandTuningParameters() {
    $fn = "Update-KSTandTuningParameters"
    LogOutputFileEnterFunctionText($fn)

    # Update KST
    LogFileAndOutputText("Updating Known Servers Table")

    # TODO: This bat file adds local server to KST, this should not be necessary
    # TODO: If absolutely necessary, convert bat file into powershell script
    $A = Start-Process -FilePath "$myScriptDir\CopyKST.bat" -Wait -PassThru -NoNewWindow
    if ($A.ExitCode -eq 0) {
        Write-Output "`nKST updated successfully.`n"
        LogOutputFileText $false " "
        LogOutputFileText $false "KST updated successfully."
    }
    else {
        Write-Output "`nKST update failed with exit code:  $A.ExitCode"
        LogOutputFileText $true "KST update failed with exit code:  $A.ExitCode"
    }

    # Change tuning parameters to fix ACH data gap issue
    # This must be run after Update-Environment, else %piserver% is not set
    # Not using PowerShell Tools for the PI System b/c they require PS 4.0. Windows Server 2008 R2 ships with PS 2.0
    
    # TODO: Investigate whether this is really necessary
    # TODO: If necessary, convert to use PowerShell Tools for PI System, no need to support server 2008 R2

    Write-Output "`nenv_PIServer = $env:piserver"
    LogOutputFileText $true "env_PIServer = $env:piserver"
	
    Write-Output "`nUpdating Tuning Parameters"
    LogOutputFileText $false " "
    LogOutputFileText $false "Updating Tuning Parameters"
    Get-Content -Path "$myScriptDir\piconfig_input.txt" | & (${env:piserver} + 'adm\piconfig.exe')
    
    Write-Output "`nStopping the Archive Subsystem to implement change"
    LogOutputFileText $false " "
    LogOutputFileText $false "Stopping the Archive Subsystem to implement change"
    Stop-Service piarchss
    Write-Output "`nArchive Subsystem stopped."
    LogOutputFileText $false " "
    LogOutputFileText $false "Archive Subsystem stopped."

    Write-Output "`nRestarting the Archive Subsystem"
    LogOutputFileText $false " "
    LogOutputFileText $false "Restarting the Archive Subsystem"
    Start-Service piarchss
    Write-Output "`nArchive Subsystem started.`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "Archive Subsystem started.`n"

    LogOutputFileExitFunctionText($fn)
}

function StartPIDataArchive() {
    # TODO: Double check whether this is necessary (whether PI Data Archive is started by default after install)
    LogOutputFileEnterFunctionText StartPIDataArchive

    if (null -ne $env:piserver) {
        Write-Output "`nStartPIDataArchive function: Attempting to start PI Data Archive - archive location:  $env:piserver"
        LogOutputFileText $false " "
        LogOutputFileText $false "StartPIDataArchive function: Attempting to start PI Data Archive - archive location:  $env:piserver"

        # do it gracefully, if I know where the PI server is located
        #
        Push-Location ((Get-Item $env:piserver).FullName + "\adm")
        .\pisrvstart.bat 2>&1 | out-null 
        Pop-Location
    }
    else {
        Write-Output "`nStartPIDataArchive function: Unable to find environment variable %piserver%. Cannot start the PI Data Archive."
        LogOutputFileText $false " "
        LogOutputFileText $false "StartPIDataArchive function: Unable to find environment variable %piserver%. Cannot start the PI Data Archive."
    }   

    LogOutputFileExitFunctionText StartPIDataArchive
}


function CreateAFDatabase( $afdatabase) {
    LogOutputFileEnterFunctionText CreateAFDatabase

    # Create an AF database on the local AF Server for use by the Smart Connector
    Write-Output "`nCreateAFDatabase function: Create an AF database on the local AF Server for use by the Smart Connector`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "CreateAFDatabase function: Create an AF database on the local AF Server for use by the Smart Connector"
	
    $errorStatus = 0

    # See if we can load the assembly and create a PISystems object
    try {
        [System.Reflection.Assembly]::LoadWithPartialName("OSIsoft.AFSDK") | Out-Null
        $afServers = new-object OSIsoft.AF.PISystems
    }
    catch { 
        Write-Output "`nCreateAFDatabase function: Create AF Database Error: Unable to Load AFSDK"
        LogOutputFileText $true "CreateAFDatabase function: Create AF Database Error: Unable to Load AFSDK"
        $errorstatus = 1
    }
    # Connect to the AF Server and if the database does not exist, create it
    if ($errorstatus -eq 0) {
        try {
            # TODO: If we can install Powershell tools for PI, try using that instead
            $AFServerName = [System.Net.Dns]::GetHostByName((hostname)).HostName
            $afServer = $afServers[$AFServerName]
            $afServer.Databases.Refresh | Out-Null
		
            if ($afServer.Databases[ $afdatabase] -eq $null) {
                $afServer.Databases.Add( $afdatabase) | Out-Null
                if ($afServer -eq $null) {
                    $errorStatus = 1
                }
                else {
                    Write-Output "`nCreateAFDatabase function: AF Database created:   $afdatabase"
                    LogOutputFileText $false " "
                    LogOutputFileText $false "CreateAFDatabase function: AF Database created:  $afdatabase"
                    $afServer = $null
                }
            }
            else {
                Write-Output "`nCreateAFDatabase function: AF Database already exists, skipping creation:   $afdatabase"
                LogOutputFileText $false " "
                LogOutputFileText $false "nCreateAFDatabase function: AF Database already exists, skipping creation:   $afdatabase"
            }
        }
        catch { 
            $errorStatus = 1
        } 
    }
    if ($errorStatus -eq 1) { 
        Write-Output "`nCreateAFDatabase function: Error: Cannot create AF database, unable to connect to AF Server: $AFServerName"
        Write-Output "`nCreateAFDatabase function: Check that the AF Server is installed and running"
        Write-Output "`nCreateAFDatabase function: Alternatively Create an AF Database manually called: DeltaV and install the DeltaV Smart Connector."
        LogOutputFileText $true  "CreateAFDatabase function: Error: Cannot create AF database, unable to connect to AF Server: $AFServerName"
        LogOutputFileText $false "CreateAFDatabase function: Check that the AF Server is installed and running"
        LogOutputFileText $false "CreateAFDatabase function: Alternatively Create an AF Database manually called: DeltaV and install the DeltaV Smart Connector.`n`n"
    }
	
    LogOutputFileExitFunctionText CreateAFDatabase

    LogExecutionTime("CreateAFDatabase", $fTime.Elapsed.ToString())
}

function AddArchives() {
    # TODO: Review whether this step of the script is necessary
    # TODO: If we want to keep this, see if possible to use Powershell tools
    LogOutputFileEnterFunctionText AddArchives

    $fTime = [System.Diagnostics.Stopwatch]::StartNew()

    # Create and add two archives to the PI Data Archive
    #
    Write-Output "`nAttempting to configure additional archives to the PI Data Archive`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "Attempting to configure additional archives to the PI Data Archive"

    if ($DDriveFound -eq "true") {
        $archives = "D:\PI\Archives\piarch.00"
    }
    else {
        $archives = "C:\PI\Archives\piarch.00"
    }

    $archivesize = 256;

    try {
        if ($env:PIServer -ne $null) { 
            for ($i = 1; $i -lt 3; $i++) {
                Write-Output "Creating archive: $archives$i"
                LogOutputFileText $false " "
                LogOutputFileText $false "Creating archive: $archives$i"
                $rc = Start-Process  ((Get-Item $env:PIServer).FullName + "\adm\piarcreate.exe") -ArgumentList "$archives$i $archivesize" -Wait -PassThru -NoNewWindow
                if ($rc.ExitCode -ne 0) {
                    Write-Output "`nArchive creation returned error code: $($rc.ExitCode)"
                    LogOutputFileText $true "Archive creation returned error code: $($rc.ExitCode)"
                }
                $rc = Start-Process -FilePath ((Get-Item $env:PIServer).FullName + "\adm\piartool.exe") -ArgumentList "-ar $archives$i" -Wait -PassThru -NoNewWindow
                if ($rc.ExitCode -ne 0) {
                    Write-Output "`nArchive registration returned error code: $($rc.ExitCode)"
                    LogOutputFileText $true "Archive registration returned error code: $($rc.ExitCode)"
                }
            }
        }
        else {
            Write-Output "`nUnable to locate PI software directory, please create additional archives manually"
            LogOutputFileText $false " "
            LogOutputFileText $false "Unable to locate PI software directory, please create additional archives manually"
        }
    }
    catch {
        Write-Output "`nError creating archives, please create additional archives manually"
        LogOutputFileText $true "Error creating archives, please create additional archives manually" 
    } 
    
    LogOutputFileExitFunctionText AddArchives

    LogExecutionTime("AddArchives", $fTime.Elapsed.ToString())
}

function InstallDeltaV_SC() {
    LogOutputFileEnterFunctionText InstallDeltaV_SC

    $fTime = [System.Diagnostics.Stopwatch]::StartNew()

    # Set properties needed to install the DeltaV Smart Connector
    # TODO: Product should be passed in generically
    $product = "DeltaV_Actr_4.1.1.79"
    $setupExeFile = "DeltaV_SC_4.1.1.79_.exe"
    $silent = "silent\DeltaV_SC_4.1.1.79_silent.ini"
    $silent_custom = "${myTempDir}\DeltaV_SC_4.1.1.79_silent.ini"

    Write-Output "`nInstallDeltaV_SC function: Attempting to install  the DeltaV Smart Connector`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallDeltaV_SC function: Attempting to install DeltaV Smart Connector`n"

    #--- Perform Action ---#
    #
    ExpandSetupKitExe $product $setupExeFile

    #--- Update silent.ini ---#
    # TODO: Hopefully not required, this info should be passed in
    (Get-Content $silent) | 
    Foreach-Object { $_ -replace "DELTAV_HOSTNAME", $env:computername } | 
    Out-File $silent_custom
	
    #--- Perform Action ---#
    #
    PerformSilentInstallation $product $silent_custom
    
    # TODO: Unlikely we should be setting this
    UpdateDeltaVService

    #--- Perform Action ---#
    #
    LogOutputFileExitFunctionText InstallDeltaV_SC

    LogExecutionTime("InstallDeltaV_SC", $fTime.Elapsed.ToString())
}

function PerformAFServerPostInstallationTasks() {
    LogOutputFileEnterFunctionText PerformAFServerPostInstallationTasks

    $fTime = [System.Diagnostics.Stopwatch]::StartNew()
    
    Write-Output "`nPerformAFServerPostInstallationTasks function: Get the value for the PIServer EnvironmentVariable"
    LogOutputFileText $false " "
    LogOutputFileText $false "PerformAFServerPostInstallationTasks function: Get the value for the PIServer EnvironmentVariable"

    # TODO: Verify whether any of this loop is necessary
    $i = 0
    while (-Not $env:PISERVER) {
        $i++
        $now = Get-Date -f "MM-dd-yyyy HH:mm:ss"
        
        Write-Output "`nPerformAFServerPostInstallationTasks function: $now, PISERVER not set yet in the environment"
        LogOutputFileText $false " "
        LogOutputFileText $false "PerformAFServerPostInstallationTasks function: $now, PISERVER location not set yet in the environment"
        
        Start-Sleep -seconds 5

        Write-Output "`nPerformAFServerPostInstallationTasks function: Update-Environment function call"
        LogOutputFileText $false " "
        LogOutputFileText $false "PerformAFServerPostInstallationTasks function:  Update-Environment function call"
        Update-Environment # Call again to pick up variables set by the PI Installer package
		
        if ($i -gt 6) {
            LogOutputFileText $true "PerformAFServerPostInstallationTasks function: $now, PISERVER location environment variable not set. Check for successful installation of the PI Data Archive."
            throw "PerformAFServerPostInstallationTasks function: $now, PISERVER environment variable not set. Check for successful installation of the PI Data Archive."
        }
    }
    Write-Output "`nPerformAFServerPostInstallationTasks function: PISERVER location is set in the environment as $env:PISERVER"
    LogOutputFileText $false " "
    LogOutputFileText $false "PerformAFServerPostInstallationTasks function: PISERVER location is set in the environment as $env:PISERVER"
    LogOutputFileText $false " "	
	
    # Create an AF database for the Emerson Smart Connector
    #
    CreateAFDatabase

    #--- Perform Action ---#
    #
    LogOutputFileExitFunctionText PerformAFServerPostInstallationTasks

    LogExecutionTime("PerformAFServerPostInstallationTasks", $fTime.Elapsed.ToString())
}

function ExpandSetupKitExe($product, $setupExeFile) {
    # TODO: Use fewer log messages?
    LogOutputFileEnterFunctionText ExpandSetupKitExe

    # Use absolute path to the setup kit self-extracting EXE
    #
    $zipArchiveWithPath = "$myScriptDir\$setupExeFile"

    # Extraction will be performed from under the temp scripts folder
    #
    $workingDir = "$myScriptDir"
    Write-Output "`n`nExpandSetupKitExe: Perform extraction from the temp scripts folder - going there now:"
    Write-Output "`n`n     $workingDir"
    LogOutputFileText $false " "
    LogOutputFileText $false " "
    LogOutputFileText $false "ExpandSetupKitExe: Perform extraction from the temp scripts folder - going there now:"
    LogOutputFileText $false " "
    LogOutputFileText $false "     $workingDir"
    Push-Location $workingDir
 
    Write-Output "`n`nExpandSetupKitExe function: Extraction command for:"
    Write-Output "`n`n     1) product:        $product"
    Write-Output "`n`n     2) setup EXE file: $setupExeFile"
    Write-Output "`n`nExpandSetupKitExe function: Extraction command parameters:"
    Write-Output "`n`n     7zip Exe location:     $7zipExeLocation"
    Write-Output "`n`n     Output folder:         -o`"$myTempDir`""
    Write-Output "`n`n     Setup kit with path:   $zipArchiveWithPath"

    LogOutputFileText $false " "
    LogOutputFileText $false "ExpandSetupKitExe function: Extraction command for:"
    LogOutputFileText $false " "
    LogOutputFileText $false "     1) product:        $product"
    LogOutputFileText $false " "
    LogOutputFileText $false "     2) setup EXE file: $setupExeFile"
    LogOutputFileText $false " "
    LogOutputFileText $false "ExpandSetupKitExe function: Extraction command parameters:"
    LogOutputFileText $false " "
    LogOutputFileText $false " "
    LogOutputFileText $false "     7zip Exe location:     $7zipExeLocation"
    LogOutputFileText $false " "
    LogOutputFileText $false "     Output folder:         -o`"$myTempDir`""
    LogOutputFileText $false " "    
    LogOutputFileText $false "     Setup kit with path:   $zipArchiveWithPath"    
    
    #   Expand the self-extracting setup kit EXE using the 7zip executable
    Write-Output "`n`nExpandSetupKitExe function:  Attempting to expand setup kit self-extracting executable for:  $setupExeFile"
    LogOutputFileText $false " "
    LogOutputFileText $false " "
    LogOutputFileText $false "ExpandSetupKitExe function:  Attempting to expand setup kit self-extracting executable for:  $setupExeFile"    

    $rc = Start-Process -FilePath $7zipExeLocation -ArgumentList "x -y -o`"$myTempDir`" `"$zipArchiveWithPath`"" -Wait -PassThru -NoNewWindow
    if ($rc.ExitCode -ne 0) {
        # 0 means ok
        #        Pop-Location
        LogOutputFileText $true "ExpandSetupKitExe function - $product : Installation process returned error code: $($rc.ExitCode)"
        throw "ExpandSetupKitExe function - $product : Installation process returned error code: $($rc.ExitCode)"
    }

    Write-Output "`nExpandSetupKitExe function: Expanding of setup kit is complete for self-extracting executable:  $setupExeFile"
    LogOutputFileText $false " "
    LogOutputFileText $false " "
    LogOutputFileText $false "ExpandSetupKitExe function: Expanding of setup kit is complete for self-extracting executable:  $setupExeFile"    

    # Always return to your starting directory
    #
    Pop-Location
    LogOutputFileExitFunctionText ExpandSetupKitExe
}

function PerformSilentInstallation($product, $silent) {
    Write-Output "`n`nPerformSilentInstallation function: Attempting to install product:  $product"
    LogOutputFileText $false " "
    LogOutputFileText $false " "
    LogOutputFileText $false "PerformSilentInstallation function: Attempting to install product:  $product"
    LogOutputFileText $false " "

    # Everything will be done from under the temp folder
    #
    $workingDir = "$myTempDir\$product"

    # Copy custom silent.ini file from archive location to installation working folder
    Copy-Item $silent $workingDir\silent.ini -Force -errorVariable errors

    if ($errors.count -ne 0 ) {
        LogOutputFileText $true "PerformSilentInstallation function: Error updating silent.ini file:  $product"
        throw "PerformSilentInstallation function: Error updating silent.ini file:  $product"
    }

    Write-Output "`nPerformSilentInstallation function: Going to work folder:  $workingDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "PerformSilentInstallation function: Going to work folder:  $workingDir"
    Push-Location $workingDir
    
    # Need to use silent.bat file if attempting to install the PI Data Archive
    # TODO: Why? This seems unnecessary, this function is not used to install PI Data Archive anyway
    if ($product -like "Enterprise_x64") {
        # Update the silent.ini file if a D: drive is NOT found on the target installation system;
        # if a D: drive is NOT found, D: drive entries are updated to contain system drive value C:\
        if ((Test-Path D:) -and (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='D:'").DriveType -eq [int]3) {
            Write-Output "`nInstallPIDataArchive function: Update the custom PI Data Archive silent.ini file to replace D drive (D:\) with C drive (C:\)"
            LogOutputFileText $false " "
            LogOutputFileText $false "InstallPIDataArchive function: Update the custom PI Data Archive silent.ini file to replace D drive (D:\) with C drive (C:\)"

            $contents = Get-Content .\silent.ini 
            $contents -replace "D:\\", "C:\" | Set-Content .\silent.ini -Force
        }

        # Begin install attempt using silent.bat
        $rc = Start-Process -FilePath ".\silent.bat" -ArgumentList "-install" -Wait -PassThru -NoNewWindow
    }
    else {
        # Use the custom silent.ini file directly and without additional modifications
        # Begin install attempt using silent.ini
        $rc = Start-Process -FilePath ".\Setup.exe" -ArgumentList "-f `"silent.ini`"" -Wait -PassThru -NoNewWindow
    }
    if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010)) {
        # 3010 means ok, but need to reboot
        #        Pop-Location
        LogOutputFileText $true "PerformSilentInstallation function - $product : Installation process returned error code: $($rc.ExitCode)"
        throw "PerformSilentInstallation function - $product : Installation process returned error code: $($rc.ExitCode)"
    }
        
    # Always return to your starting directory
    #
    Pop-Location
    Remove-Item $workingDir -recurse -force
    
    LogOutputFileExitFunctionText PerformSilentInstallation
}
#endregion

#region System Checks
# Check that this is a 64-bit system
$bitness = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
if ($bitness -NotLike "*64*") {
    LogError "Operating System not supported. This script is intended for 64 bit systems only."
}

# Check that this is Windows major version 10
$osVersion = (Get-WmiObject Win32_OperatingSystem).Version
if (-not ($osVersion -like "10.0*")) {
    LogError "Operating system not supported. This script is intended for Windows Server 2016 or Windows 10 systems only."
}

# Checks for SQL Server Express
if ($sql -ne "") {
    # Installing SQL Server Express
    if (Test-Path $sql -type leaf) {
        LogOutFile "Found a potential SQL Server Express install kit at: $sql"
    }
    else {
        LogError "Failed to find SQL Server Express install kit at: $sql"
    }
}

# Checks for PI Server
if ($piserver -ne "") {
    # Installing PI Server
    if (Test-Path $piserver -type leaf) {
        LogOutFile "Found a potential PI Server install kit at: $piserver"
    }
    else {
        LogError "Failed to find PI Server install kit at: $piserver"
    }

    # Check that PI drive can be found
    if ($pidrive -ne "") {
        # Specified drive as parameter, check it exists
        $testDrive = "${pidrive}:"
        if ((Test-Path $testDrive) -and (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$testDrive'").DriveType -eq [int]3) {
            $pidirectory = "$testDrive\PI"
        }
        else {
            LogError "PI Drive specified ($pidrive) was not found."
        }
    }
    else {
        # No specified drive, try D: or C:
        if ((Test-Path D:) -and (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='D:'").DriveType -eq [int]3) {
            $pidirectory = "D:\PI"
        }
        elseif ((Test-Path C:) -and (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'").DriveType -eq [int]3) {
            $pidirectory = "C:\PI"
        }
        else {
            LogError "Failed to find local D: or C: drive for PI Data Archive directory. Please specify a drive using the -pidrive parameter."
        }
    }

    LogOutFile "Will use $pidirectory as PI Data Archive directory"

    # Check that pilicense.dat can be found
    if ($pilicense -ne "") {
        # Specified pilicense as parameter, check it exists
        if (-not(Test-Path $pilicense -type leaf)) {
            LogError "Failed to find pilicense at: $pilicense"
        }
    }
    else {
        # No specified pilicense, try .\pilicense.dat
        $pilicense = ".\pilicense.dat";
        if (-not (Test-Path $pilicense -type leaf)) {
            LogError "Failed to find local pilicense.dat. Please specify a pilicense using the -pilicense parameter."
        }
    }

    LogOutFile "Found a potential pilicense.dat at: $pilicense"
}
#endregion

#region Run Installs
# Run SQL Server Express Install
if ($sql -ne "") {
    InstallSQLServerExpress
}

# Run PI Server Install
if ($piserver -ne "") {
    InstallPIServer
}
#endregion

throw "Incomplete"

# TODO: Investigate hard-coding 7zip path, C:\Program Files\7-Zip
# TODO: Verify this exists in Windows Server 2016
# TODO: If hard coded, declare higher in the script
#
# Verify 7zip program exists
# 
$7zipExeLocation = "$myScriptDir\7z.exe"

Write-Output "`n7zip exectuable located in folder: $7zipExeLocation`n"
LogOutputFileText $false "7zip exectuable located in folder: $7zipExeLocation"

if (-not (test-path $7zipExeLocation)) {
    LogOutputFileText $true "The following program is required to continue: $7zipExeLocation"
    throw "The following program is required to continue: $7zipExeLocation"
}
#endregion

#region Run Installs
# Increment as parameters are processed and individual components installed
# If no parameters are specified install all components
$noparams = 1

# Install SQL Server Express if -sql switch specified.
if ($sql) {    
    $noparams = 0
   
    InstallSQLServerExpress
}

# Install the Advanced Continuous Historian
if ($ach) {
    $noparams = 0

    InstallPIServerInstaller
    Update-Environment
    PerformAFServerPostInstallationTasks
    StartPIDataArchive
    Update-KSTandTuningParameters
}

# Install Emerson DeltaV SmartConnector
if ($sc) {
    $noparams = 0
	
    InstallDeltaV_SC
}

# Create additional archives
if ($archives) {
    $noparams = 0

    AddArchives
}

#
# If no command line parameters supplied for specific installation components, install all components
# TODO: Remove this block, fill in defaults and such as necessary
if ($noparams) { 
    InstallPIServerInstaller
    Update-Environment
    PerformAFServerPostInstallationTasks
    StartPIDataArchive
    Update-KSTandTuningParameters
    AddArchives
    InstallDeltaV_SC
}
#endregion

#region Cleanup
$elapsed = $Time.Elapsed.ToString()
$EndTime = Get-Date -f "MM-dd-yyyy HH:mm:ss"

Write-Output "`nScript started at $StartTime"
Write-Output "`nScript ended at $EndTime"
Write-Output "`nTotal Elapsed Time: $elapsed"

LogOutputFileText $false " "
LogOutputFileText $false "Script started at $StartTime"
LogOutputFileText $false "Script ended at $EndTime"
LogOutputFileText $false "Total Elapsed Time: $elapsed"

Write-Output "`nSoftware installation finished."
LogOutputFileText $true "Software installation finished."
#endregion
