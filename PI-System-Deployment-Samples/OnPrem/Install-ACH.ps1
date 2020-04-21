<#
.SYNOPSIS

	Installs the Emerson Advanced Continuous Historian on Windows Server 2016 or Windows 10,
	64-bit architecture only.
	
.DESCRIPTION

	Installs SQL Server Express, Advanced Continuous Historian and Smart Connector and related 
	configuration tasks.
	
	When no parameters are specified, all components and configuration tasks are completed with the exception
    of SQL Server Express, which is only installed using the -sql parameter.
	
	Parameters can be supplied to specify which specific components to install or configure.

.PARAMETERS

.PARAMETER pilicensefile
	Specifies the license file to use for the Advanced Continuous Historian.

.PARAMETER SQLInstanceName
	Specifies the default SQL Server Instance name.

.PARAMETER AFDatabase
	Specifies the default PI Asset Framework database name for the Smart Connector.

.PARAMETER sql
    Installs Microsoft SQL Server Express.

.PARAMETER ach
    Installs the Advanced Continuous Historian components, which include the PI Data Archive and the PI AF Server
	as deployed via the PI Server Installer.

.PARAMETER sc
    Installs the Emerson DeltaV Smart Connector.

.PARAMETER archives
	Creates additional archives. This option is not run by default and can only be run after installation and a reboot.

.PARAMETER updatesOnly
	Updates only the Emerson DeltaV Smart Connector, from a previously-installed version to version 4.1.1.79.

.EXAMPLES

.EXAMPLE
	E:\ACH> .\Install-ACH.ps1 
	
	Installs all components required for the Advanced Continuous Historian

    Uses self-extracting setup kit EXE files to deploy OSIsoft software

.EXAMPLE
	E:\ACH> .\Install-ACH.ps1 -sql
	
	Install Microsoft SQL Server Express

.NOTES
  This may be a sample script and, if so, it is not presently signed.  In which case, there
  is a need to disable the restrictions on ExecutionPolicy: Set-ExecutionPolicy Unrestricted	

  Before this script is handed over to Emersion, this script must be renamed from its TFS
  name to be:  Install-ACH.ps1

  After being renamed and before being handed over to Emerson, the release version of this
  script must be digitally signed.
#>
<#***************************************************************************************
 ©2009-2020 OSIsoft, LLC. All Rights Reserved.
 
 No Warranty or Liability.  The OSIsoft Samples contained herein are licensed “AS IS” without any warranty of any kind.  
 Licensee bears all risk of use. OSIsoft DISCLAIMS ALL EXPRESS AND IMPLIED WARRANTIES,INCLUDING BUT NOT LIMITED TO THE 
 IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE and NONINFRINGEMENT. In no event will OSIsoft
 be liable to Licensee or to any third party for damages of any kind arising from Licensee’s use of the OSIsoft Samples 
 OR OTHERWISE, including but not limited to direct, indirect, special, incidental, lost profits and consequential 
 damages, and Licensee expressly assumes the risk of all such damages. This limitation applies to any claims related to
 Licensee’s use of the OSIsoft Samples and claims for breach of contract, breach of warranty, guarantee or condition, 
 strict liability, negligence or other tort to the extent permitted by applicable law.  This limitation applies even if
 OSIsoft knew or should have known about the possibility of the damages. FURTHER, THE OSIsoft SAMPLES ARE NOT ELIGIBLE 
 FOR SUPPORT UNDER EITHER OSISOFT’S STANDARD OR ENTERPRISE LEVEL SUPPORT AGREEMENTS.
 
  Install-ACH v1.7 (19 April 2020)
	  - Manually install .NET 4.8 Framework to allow control over reboot
 
  Install-ACH v1.6 (19 April 2020)
	  - Additional logging functions
	  - UpdateServer funtion for DeltaV Asset Connector 
 
  Install-ACH v1.5 (16 April 2020)
   -Update for PI Server 2018 SP3 Patch 1 
 
  Install-ACH v1.4 (21 June 2019)
   -Added the PiPowerShell feature to the set of features to be installed with the
    PI Server 2018 SP2 Installer.


 Install-ACH v1.3 (28 May 2019)
   -Added entry, $ErrorActionPreference = "Continue", after each instance of -ErrorAction
    or -EA being set to SilentlyContinue to explicitly reset the error action preference to
	its default value

   -Added code to copy the SQL Scripts execution output file to the script output log
    file folder


Install-ACH v1.2 (06 May 2019)
   -Modified to use updated version PI Server 2018 SP2a Installer (PI Server_2018 SP2a_.exe)


 Install-ACH v1.1 (25 April 2019)
   -Updated to use the released version of the PI Server 2018 SP2 Installer.
   -Updated to create the AF SQL database 'manually' (separate from the AF Server
    installation).
   -Updated to remove two local groups:  AFServers and AFQueryEngines

 
 Install-ACH v1.0 (30 January 2019)
   -Using the the PI Server 2016 R2 Install-ACH.ps1 (v1.9) script as a springboard,
    this script has been updated to use PI Server 2018 SP2 Installer and updated
    versions of associated software.

 
 Install-ACH.ps1 v1.0 (30 January 2019)
****************************************************************************************#>

# ========================================================================================
# SECTION 1:  Process script parameters
#
param(
		[string]$pilicense = "",                       # location of license file to use
        [string]$SQLInstanceName = "ADV_CONT_HIST",    # default SQL Server Instance
		[string]$AFDatabase = "DeltaV",                # default PI AF database name for the Smart Connector
        # version of script - update manually for new versions
		[string]$scriptVersion="Install-ACH.ps1 v1.7 (19-Apr-2020) (PI Server 2018 SP3 patch 1) (DeltaV 14.3.1)",
        [switch]$sql,                                  # install SQL Server Express 
        [switch]$ach,                                  # install PI Data Archive and PI AF
		[switch]$sc,                                   # install the Emerson Smart Connector
        [switch]$archives,                             # create 2 additional archives
		[switch]$updatesOnly                           # execute updates portion of script only
)

# Start stopwatch as soon as possible!
#
$StartTime = Get-Date -f "MM-dd-yyyy HH:mm:ss"
$Time = [System.Diagnostics.Stopwatch]::StartNew()

# Identify module just executed
[string]$moduleName2print = ""

# Ouput information to text log file
[boolean]$OutputFileFormatNeeded = $false
[string]$OutputFileText = ""
[string]$OutputFileFunctionName = ""

# ========================================================================================
# SECTION 2:  Begin helper functions here
#
function LogOutputFileText()
{
    # Get argument values
    $OutputFileFormatNeeded = $args[0]
    $OutputFileText = $args[1]

    # Format white space around text if needed
    if ($OutputFileFormatNeeded -eq $true)
    {
	   write-output " " | Out-File -FilePath $myLogFileDir\InstallACHlog.txt -Append
       write-output "--------------------------------------------------------------------------------" | Out-File -FilePath $myLogFileDir\InstallACHlog.txt -Append
       write-output " " | Out-File -FilePath $myLogFileDir\InstallACHlog.txt -Append
    }
    
    # Output information to text log file
    write-output $OutputFileText | Out-File -FilePath $myLogFileDir\InstallACHlog.txt -Append
}

function LogFileAndOutputText() 
{
    # Get argument values
    $OutputFileFormatNeeded = $args[0]
    $OutputFileText = $args[1]
	
	LogOutputFileText $OutputFileFormatNeeded OutputFileText
	Write-Output ""
	Write-Output "$OutputFileText"

}

function LogFileandOutputExitText() 
{
    # Get argument values
    $OutputFileFormatNeeded = $args[0]
    $OutputFileText = $args[1]
	
	Write-Output ""
	Throw $OutputFileText

}


#*************************
function LogOutputFileEnterFunctionText()
{
    # Get argument values
    $OutputFileFunctionName = $args[0]

    # Log entering function message
    write-output "`n--------------------------------------------------------------------------------"
    write-output "`n     Entering function:  $OutputFileFunctionName`n"
	write-output "`n--------------------------------------------------------------------------------"
    
    LogOutputFileText $false " "
    LogOutputFileText $false "--------------------------------------------------------------------------------"
    LogOutputFileText $false " "
    LogOutputFileText $false "     Entering function:  $OutputFileFunctionName"
    LogOutputFileText $false " "
    LogOutputFileText $false "--------------------------------------------------------------------------------"
    LogOutputFileText $false " "
}

#*************************
function LogOutputFileExitFunctionText()
{
    # Get argument values
    $OutputFileFunctionName = $args[0]

    # Log exiting function message
    write-output "`nExiting function:  $OutputFileFunctionName`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "Exiting function:  $OutputFileFunctionName"
    LogOutputFileText $false " "
}

#*************************
function LogExecutionTime()
{
    param([string]$eTime)

    write-output "`n***** Duration of $moduleName2print module installation: $eTime *****`n"
    
    LogOutputFileText $false " "
    LogOutputFileText $false "***** Duration of $moduleName2print module installation: $eTime *****"
    LogOutputFileText $false " "
}

#*************************
function Update-Environment 
{
    # Using the Environment registry entry:
	#    Update Enviroment Variables to pick up variables created
    #    during the execution of the PI Installer package

    LogOutputFileEnterFunctionText Update-Environment

    $locations = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
                 'HKCU:\Environment'

    $locations | ForEach-Object {
        $k = Get-Item $_
        $k.GetValueNames() | ForEach-Object {
            $name  = $_
            $value = $k.GetValue($_)

            if ($userLocation -and $name -ieq 'PATH') {
                $Env:Path += ";$value"
            } else {
                Set-Item -Path Env:\$name -Value $value
            }
        }

        $userLocation = $true
    }

    LogOutputFileExitFunctionText Update-Environment
}

#*************************
function Update-KSTandTuningParameters()
{
    LogOutputFileEnterFunctionText Update-KSTandTuningParameters

    # Update KST
	write-output "`nEntering Updating Known Servers Table"
    LogOutputFileText $false " "
    LogOutputFileText $false "Updating Known Servers Table"


    $A = Start-Process -FilePath "$myScriptDir\CopyKST.bat" -Wait -PassThru -NoNewWindow
    if($A.ExitCode -eq 0)
    {
        write-output "`nKST updated successfully.`n"
		LogOutputFileText $false " "
        LogOutputFileText $false "KST updated successfully."
    }
    else
    {
		write-output "`nKST update failed with exit code:  $A.ExitCode"
		LogOutputFileText $true "KST update failed with exit code:  $A.ExitCode"
    }

    # Change tuning parameters to fix ACH data gap issue
    # This must be run after Update-Environment, else %piserver% is not set
    # Not using PowerShell Tools for the PI System b/c they require PS 4.0. Windows Server 2008 R2 ships with PS 2.0.

	write-output "`nenv_PIServer = $env:piserver"
	LogOutputFileText $true "env_PIServer = $env:piserver"
	
    write-output "`nUpdating Tuning Parameters"
    LogOutputFileText $false " "
    LogOutputFileText $false "Updating Tuning Parameters"
        Get-Content -Path "$myScriptDir\piconfig_input.txt" | & (${env:piserver} + 'adm\piconfig.exe')
    
    
    write-output "`nStopping the Archive Subsystem to implement change"
    LogOutputFileText $false " "
    LogOutputFileText $false "Stopping the Archive Subsystem to implement change"
        Stop-Service piarchss
    write-output "`nArchive Subsystem stopped."
    LogOutputFileText $false " "
    LogOutputFileText $false "Archive Subsystem stopped."

    
    write-output "`nRestarting the Archive Subsystem"
    LogOutputFileText $false " "
    LogOutputFileText $false "Restarting the Archive Subsystem"
        Start-Service piarchss
    write-output "`nArchive Subsystem started.`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "Archive Subsystem started.`n"

    LogOutputFileExitFunctionText Update-KSTandTuningParameters
}

#*************************
function StartPIDataArchive()
{
    LogOutputFileEnterFunctionText StartPIDataArchive

    if ($env:piserver -ne $null)
    {
        write-output "`nStartPIDataArchive function: Attempting to start PI Data Archive - archive location:  $env:piserver"
        LogOutputFileText $false " "
        LogOutputFileText $false "StartPIDataArchive function: Attempting to start PI Data Archive - archive location:  $env:piserver"

        # do it gracefully, if I know where the PI server is located
        #
        pushd ((Get-Item $env:piserver).FullName + "\adm")
        .\pisrvstart.bat 2>&1 | out-null 
        popd
    } else
    {
        write-output "`nStartPIDataArchive function: Unable to find environment variable %piserver%.  Cannot start the PI Data Archive."
        LogOutputFileText $false " "
        LogOutputFileText $false "StartPIDataArchive function: Unable to find environment variable %piserver%.  Cannot start the PI Data Archive."
    }   

    LogOutputFileExitFunctionText StartPIDataArchive
}

#*************************
function StopDisableConnectors
{
    LogOutputFileEnterFunctionText StopDisableConnectors

    $ACService=$null
    $ACService = Get-Service "PIDeltaV_ACtr" -ErrorAction SilentlyContinue
	$ErrorActionPreference = "Continue" 
    
    if ($ACService)
    {
        write-output "`nStopDisableConnectors function:  Stopping and disabling Asset Connector"
        LogOutputFileText $false " "
        LogOutputFileText $false "StopDisableConnectors function:  Stopping and disabling Asset Connector"
        if ($ACService.Status -eq "Running")
        {
            Stop-Service -Name $ACService.Name -Force
        }
        Set-Service $ACService.Name -StartupType Disabled
    }

    $OPCInts=$null
    $OPCInts = Get-Service "OPCInt_SC*" -ErrorAction SilentlyContinue
	$ErrorActionPreference = "Continue" 

    if ($OPCInts)
    {
        write-output "`nStopDisableConnectors function:  Stopping and disabling all OPC Smart Connector Interfaces."
        LogOutputFileText $false " "
        LogOutputFileText $false "StopDisableConnectors function:  Stopping and disabling all OPC Smart Connector Interfaces."
        foreach ($OPCInt in $OPCInts)
        {
            if ($OPCInt.Status -eq "Running")
            {
                Stop-Service $OPCInt.Name -Force
            }
            Set-Service $OPCInt.Name -StartupType Disabled
        }
    }

    Start-Sleep 5

    $success = $true

    if ($ACService)
    {
        $ACService = Get-Service "PIDeltaV_ACtr"
        if ($ACService.Status -ne "Stopped")
        {
            write-output "`nStopDisableConnectors function:  Could not stop the" $ACService.Name", please do so manually."
            LogOutputFileText $false " "
            LogOutputFileText $false "StopDisableConnectors function:  Could not stop the" $ACService.Name", please do so manually."
            $success = $false
        }
        if ((Get-WmiObject Win32_Service -Filter ("Name='" + $ACService.Name + "'")).StartMode -ne "Disabled")
        {
            write-output "`nStopDisableConnectors function:  Could not change the startup type of the" $ACService.Name "to Disabled. Please do so manually."
            LogOutputFileText $false " "
            LogOutputFileText $false "StopDisableConnectors function:  Could not change the startup type of the" $ACService.Name "to Disabled. Please do so manually."
            $success = $false
        }
    }

    if ($OPCInts)
    {
        $OPCInts = Get-Service "OPCInt_SC*"
        foreach ($OPCInt in $OPCInts)
        {
            if ($OPCInt.Status -ne "Stopped")
            {
                write-output "`nStopDisableConnectors function:  Could not stop the" $OPCInt.Name ", please do so manually."
                LogOutputFileText $false " "
                LogOutputFileText $false "StopDisableConnectors function:  Could not stop the" $OPCInt.Name ", please do so manually."
                $success = $false
            }
            if ((Get-WmiObject Win32_Service -Filter ("Name='" + $OPCInt.Name + "'")).StartMode -ne "Disabled")
            {
                write-output "`nStopDisableConnectors function:  Could not change the startup type of the" $OPCInt.Name " to Disabled. Please do so manually."
                LogOutputFileText $false " "
                LogOutputFileText $false "StopDisableConnectors function:  Could not change the startup type of the" $OPCInt.Name " to Disabled. Please do so manually."
                $success = $false
            }
        }
    }
    if ($success)
    {
        if ($ACService -or $OPCInts)
        {
            write-output "`nStopDisableConnectors function:  All connector services have been stopped and disabled successfully."
            LogOutputFileText $false " "
            LogOutputFileText $false "StopDisableConnectors function:  All connector services have been stopped and disabled successfully."
        }
        else
        {
            write-output "`nStopDisableConnectors function:  No connector services exist. No need to stop or disable."
            LogOutputFileText $false " "
            LogOutputFileText $false "StopDisableConnectors function:  No connector services exist. No need to stop or disable."
        }
    }
    else
    {
        LogOutputFileText $true "StopDisableConnectors function:  Unable to stop and/or set all connectors to disabled.  Please stop and disable the Asset Connector and all Smart Connector interfaces manually, then rerun the script."
        throw "StopDisableConnectors function:  Unable to stop and/or set all connectors to disabled.  Please stop and disable the Asset Connector and all Smart Connector interfaces manually, then rerun the script."
    }

    LogOutputFileExitFunctionText StopDisableConnectors
}

#*************************
function InstallSQLServerExpress() 
{
    LogOutputFileEnterFunctionText InstallSQLServerExpress
 
    $fTime = [System.Diagnostics.Stopwatch]::StartNew()

    write-output "`nInstalling Microsoft SQL Server Express 2016 SP2 (64-bit)`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "Installing Microsoft SQL Server Express 2016 SP2 (64-bit)`n"
        
    # Define name of the work folder and the MS SQL Server Express setup kit
    $productFolder = "SQLEXPR_x64_ENU"
    $setupExeFile  = "SQLEXPR_x64_ENU.exe"
    $productExtractFolder = "SQLEXPR_x64_ENU"


    # Installation will be performed from within the temp folder
    #
    $workingDir = "$myTempDir"


    write-output "`nNote: Installation of Microsoft SQL Server Express 2016 SP2, $setupExeFile, can run for 15 minutes or longer on slower systems"
    LogOutputFileText $false " "
    LogOutputFileText $false "Note: Installation of Microsoft SQL Server Express 2016 SP2, $setupExeFile, can run for 15 minutes or longer on slower systems"


    # Copy the SQL Server Express setup kit to the working folder for silent execution
    #
    write-output "`nInstallSQLServerExpress function:  Copy the MS SQL Server Express setup kit, $setupExeFile, to the working folder:  $workingDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallSQLServerExpress function:  Copy the MS SQL Server Express setup kit, $setupExeFile, to the working folder:  $workingDir"

    # Target folder must be created to enable the copy command to complete successfully
    Copy-Item $myScriptDir\$setupExeFile $workingDir -Force -errorVariable errors
    if ($errors.count -ne 0 ) 
    {
        LogOutputFileText $true "InstallSQLServerExpress function: Error copying $setupExeFile to the working folder:  $myTempDir\$product"
        throw "InstallSQLServerExpress function: Error copying $setupExeFile to the working folder:  $myTempDir\$product"
    }

	
    # Installation will be performed from under the temp folder
    #
    write-output "`nInstallSQLServerExpress function:  Going to work folder to execute the MS SQL Server Express setup kit:  $workingDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallSQLServerExpress function:  Going to work folder to execute the MS SQL Server Express setup kit:  $workingDir"
    pushd $workingDir


    # Define installation parameters for the MS SQL Server Express installation
    #$cmd = ".\productExtractFolder\setup.exe"
    $cmd = ".\SQLEXPR_x64_ENU.exe"
    $list = 
    @(
        "/Q",
        "/IACCEPTSQLSERVERLICENSETERMS=TRUE",
        "/ACTION=INSTALL",
        "/FEATURES=SQLENGINE,FULLTEXT",
        "/UpdateEnabled=FALSE",
        "/INSTANCENAME=$SQLInstanceName",      
        "/SQLCOLLATION=SQL_LATIN1_GENERAL_CP1_CI_AS",
        "/SQLSYSADMINACCOUNTS=BUILTIN\ADMINISTRATORS",
        "/BROWSERSVCStartupType=2",
        "/NPENABLED=1",
        "/TCPENABLED=1",
        "/SQLSVCACCOUNT=`"NT AUTHORITY\SYSTEM`"",
        "/AGTSVCACCOUNT=`"NT AUTHORITY\SYSTEM`""
     )

    write-output "`nInstallSQLServerExpress function:  Attempting to install product:  $setupExeFile"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallSQLServerExpress function:  Attempting to install product:  $setupExeFile"

    # Begin install attempt using defined parameters
    $rc = Start-Process -FilePath $cmd -ArgumentList $list -Wait -PassThru

    if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010))   # 3010 means ok, but need to reboot
    {
       popd
       LogOutputFileText $true "InstallSQLServerExpress function:  Installation process returned error code: $($rc.ExitCode)"
       throw "InstallSQLServerExpress function:  Installation process returned error code: $($rc.ExitCode)"
    }

    # Installation has completed
    #
    write-output "`nInstallSQLServerExpress function:  Installation completed for:  $setupExeFile"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallSQLServerExpress function:  Installation completed for:  $setupExeFile"

    # Always return to your starting directory
    #
    popd
    Remove-Item $myTempDir\$productFolder -recurse -force


    LogOutputFileExitFunctionText InstallSQLServerExpress

	$moduleName2print = "InstallSQLServerExpress"
    LogExecutionTime($fTime.Elapsed.ToString())
}

#*************************
function InstallPIServerInstaller() 
{ 
    LogOutputFileEnterFunctionText InstallPIServerInstaller
	
	$fTime = [System.Diagnostics.Stopwatch]::StartNew()

    # Define proper install kit to use
    #
	$product   = "PI Server_2018 SP3 Patch 1_.exe"
    $pilicense = "silent\pilicense.dat"
	$net48 = ".\ndp48-x86-x64-allos-enu.exe"

    # Let's first check to see if the SQL instance is running
	#   -  SQL instance needs to be in a running state prior to the installatoin of
    #	   the PI AF Server component, which is part of the PI Server setup kit
    #   
    $sqlservice = Get-Service -DisplayName "SQL Server ($SQLInstanceName)" -ErrorAction SilentlyContinue
	$ErrorActionPreference = "Continue" 
    
    if (-not ($sqlservice.Status -eq "Running"))
    {
        LogOutputFileText $true "InstallPIServerInstaller function:  Cannot find SQL Server ($SQLInstanceName) in services, exiting now."
        throw "InstallPIServerInstaller function:  Cannot find SQL Server ($SQLInstanceName) in services, exiting now."
    }
    write-output "`nInstallPIServerInstaller function:  Confirmed that SQL Server ($SQLInstanceName) is running, installing PI Server Installer"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function:  Confirmed that SQL Server ($SQLInstanceName) is running, installing PI Server Installer"
	
    # Check for and install the PI Data Archive license, if directed to do so
    # 
    write-output "`nInstallPIDataArchive function:  Attempting to move PI license file to the proper location,, if license file is present:  $pilicense"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIDataArchive function:  Attempting to move PI license file to the proper location, if license file is present:  $pilicense"
    
    if ($pilicense)
    {
        if (Test-Path $pilicense -pathtype container)
        {
            write-output "`nInstallPIDataArchive function:  if...container branch:  Moving PI license file to the proper location, $myTempDir, if license file is present:  $pilicense"
            LogOutputFileText $false " "
            LogOutputFileText $false "InstallPIDataArchive function:  if...container branch:  Moving PI license file to the proper location, $myTempDir, if license file is present:  $pilicense"
            
            $pilicense = "$pilicense\pilicense.dat"   #  Addresses the case where the $pilicense parameter is fed in from the command line
            Copy-Item $pilicense $myTempDir\pilicense.dat
        }
        
        if (Test-Path $pilicense -pathtype leaf)
        {
            # If it's a real file, install it as the pilicense.dat that the
            # PI Data Archive's silent installer needs
            #
            write-output "`nInstallPIDataArchive function:  if...leaf branch:  Moving PI license file to the proper location, $myTempDir, if license file is present:  $pilicense"
            LogOutputFileText $false " "
            LogOutputFileText $false "InstallPIDataArchive function:  if...leaf branch:  Moving PI license file to the proper location, $myTempDir, if license file is present:  $pilicense"

            Copy-Item $pilicense $myTempDir\pilicense.dat
        }
        else
        {
            LogOutputFileText $true "InstallPIDataArchive function:  Cannot find PI license file for use in installation:  $pilicense`n"
            throw "InstallPIDataArchive function:  Cannot find PI license file for use in installation:  $pilicense`n"
        }
	}
    		
    LogFileAndOutputText $false "`nInstallPIServerInstaller function: Check .NET 4.8 framework installed"
	
	# .NET 4.8 installed? If not, install and indicate likely requirement to reboot due - at a minimum - SQL Server & PowerShell processes.
 	# 
	
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
			Switch ($rc.ExitCode)
			{
				0    { $success=true }
				1602 { break; } # canceled
				1603 { break ;} # fatal error
				1641 {$success=$true; $reboot=$true}
				3010 {$success=$true; $reboot=$true}
				5100 {break; } # system requirements not met
				Default { break;} 
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
		} else {
		LogFileandOutputExitText $true "InstallPIServerInstaller function: Unable to locate .NET installer: $net48, exiting."
		}
	} else {
		LogFileandOutputText $true ".NET 4.8 prerequisite met."
	}

    # Copy the PI Server setup kit to the working folder for silent execution
    #
    write-output "`nInstallPIServerInstaller function:  Copy the PI Server setup kit ($product) to the working folder:  $myTempDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function:  Copy the PI Server setup kit ($product) to the working folder:  $myTempDir"

    Copy-Item $myScriptDir\$product $myTempDir -Force -errorVariable errors
    if ($errors.count -ne 0 ) 
    {
        LogOutputFileText $true "InstallPIServerInstaller function: Error copying $product to the working folder:  $workingDir"
        throw "InstallPIServerInstaller function: Error copying $product to the working folder:  $workingDir"
    }

	
    # Copy the SQL Scripts folder to the working folder for silent execution
    #
    write-output "`nInstallPIServerInstaller function:  Copy the AF SQL Scripts folder to the working folder:  $myTempDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function:  Copy the AF SQL Scripts folder to the working folder:  $myTempDir"

	$SQL_Folder = "PI AF SQL Scripts"
    Copy-Item $myScriptDir\$SQL_Folder -Destination $myTempDir -Recurse -Force -errorVariable errors
    if ($errors.count -ne 0 ) 
    {
        LogOutputFileText $true "InstallPIServerInstaller function: Error copying AF SQL Scripts folder to the working folder:  $workingDir"
        throw "InstallPIServerInstaller function: Error copying AF SQL Scripts folder to the working folder:  $workingDir"
    }
	
    # Changing folders to the work folder
    #
    write-output "`nInstallPIServerInstaller function:  Going to work folder to execute the PI Server kit:  $myTempDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function:  Going to work folder to execute the PI Server setup kit:  $myTempDir"

    pushd $myTempDir

	# Features and parameters for the installation minus drive information
	$FeatsParams = "REBOOT=Suppress PI_ARCHIVEDATDIR={0}:\PI\Archives\ PI_FUTUREARCHIVEDATDIR={0}:\PI\Archives\Future PI_EVENTQUEUEDIR={0}:\PI\Queues\ FDSQLDBSERVER=.\ADV_CONT_HIST FDSQLDBNAME=PIFD FDSQLDBVALIDATE=0 AFCLIENT_SHUTDOWN_OPTIONS=2 IACCEPTSQLNCLILICENSETERMS=YES ADDLOCAL=PIDataArchive,PITotal,FD_AppsServer,FD_AFExplorer,PiPowerShell,pismt3 /q /norestart"
  
    # Is is preferable to use the D drive (D:\) for the PI Data Archive
    if ($DDriveFound -eq "true")
	{
		$drive="d" 
	} else {
		$drive="c" 
	}
	LogFileAndOutputText $false "InstallPIServerInstaller function:  Attempting to install product, $product, to the $drive drive (${drive}:\)"
	# update parameters with drive to use
    $list = $FeatsParams -f $drive
	# install
    $rc = Start-Process .\$product -ArgumentList $list -Wait -PassThru -NoNewWindow

    if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010))   # 3010 means ok, but need to reboot
    {
       popd
       LogOutputFileText $true "InstallPIServerInstaller function:  Installation process returned error code: $($rc.ExitCode)"
       throw "InstallPIServerInstaller function:  Installation process returned error code: $($rc.ExitCode)"
    }
    
	# Execute the AF SQL Scripts
    write-output "`nInstallPIServerInstaller function:  Attempting to install AF SQL Scripts manually"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function:  Attempting to install AF SQL Scripts manually"

    $SqlScriptsExeCmd = "$myTempDir\PI AF Sql Scripts\GO.BAT"
    $SqlScriptsArgs = ".\ADV_CONT_HIST PIFD"
	$SQLExecutionOutputFile_Folder = "$myTempDir\PI AF Sql Scripts"
		
	$rc = Start-Process -FilePath $SqlScriptsExeCmd -ArgumentList $SqlScriptsArgs -WorkingDirectory $SQLExecutionOutputFile_Folder -Wait -PassThru -NoNewWindow
	
	if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010))   # 3010 means ok, but need to reboot
    {
       popd
       LogOutputFileText $true "InstallPIServerInstaller function:  AF SQL Script execution returned error code: $($rc.ExitCode)"
       throw "InstallPIServerInstaller function:  AF SQL Script execution returned error code: $($rc.ExitCode)"
    }

	
    # Copy the SQL Scripts execution output file to the script output log file folder
    #
    write-output "`nInstallPIServerInstaller function:  Copy the AF SQL Scripts execution log file,PIAFSqlScriptExecution_*.txt, to the output log folder:  $myLogFileDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function:  Copy the AF SQL Scripts execution log file,PIAFSqlScriptExecution_*.txt, to the output log folder:  $myLogFileDir"


    
    foreach ($i in Get-ChildItem -Path $SQLExecutionOutputFile_Folder -Recurse)
    {
       if ($i.Name -match "PIAFSqlScriptExecution_")
       {
          Copy-Item -Path $i.FullName -Destination $myLogFileDir -Force -errorVariable errors
       }
	
	   if ($errors.count -ne 0 ) 
       {
           LogOutputFileText $true "InstallPIServerInstaller function: Error copying AF SQL Scripts execution log file,PIAFSqlScriptExecution_*.txt, to the output log folder:  $myLogFileDir"
           throw "InstallPIServerInstaller function: Error copying AF SQL Scripts execution log file,PIAFSqlScriptExecution_*.txt, to the output log folder:  $myLogFileDir"
       }
    }
	
	
	# AF Service must be stopped and restarted for the SQL script changes to take effect
    write-output "`nInstallPIServerInstaller function:  Attempting to re-start Windows Service:  PI AF Application Service (NT SERVICE\AFService)"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function:  Attempting to re-start Windows Service:  PI AF Application Service (NT SERVICE\AFService)"
	Restart-Service -Name AFService -Force
	
	# If exist, remove two local groups:
    write-output "`nInstallPIServerInstaller function:  Attempting to remove local groups, if they exist:  AFServers and AFQueryEngines"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function:  Attempting to remove local groups, if they exist:  AFServers and AFQueryEngines"
    #	First group: AFServers
	$AFServersLocalGroup = Get-LocalGroup -Name "AFServers" -EA SilentlyContinue
	$ErrorActionPreference = "Continue" 
	
	if ($AFServersLocalGroup)
    {
       write-output "`nInstallPIServerInstaller function:  AFServers local group found:  Deleting AFServers local group"
       LogOutputFileText $false " "
       LogOutputFileText $false "InstallPIServerInstaller function:  AFServers local group found:  Deleting AFServers local group"
       
	   Remove-LocalGroup -Name "AFServers"
    }
	#	Second group: AFQueryEngine
	$AFQueryEnginesLocalGroup = Get-LocalGroup -Name "AFQueryEngines" -EA SilentlyContinue
	$ErrorActionPreference = "Continue" 

	if ($AFQueryEnginesLocalGroup)
    {
       write-output "`nInstallPIServerInstaller function:    AFQueryEngines local group found:  Deleting AFQueryEngines local group"
       LogOutputFileText $false " "
       LogOutputFileText $false "InstallPIServerInstaller function:  AFQueryEngines local group found:  Deleting AFQueryEngines local group"
       
	   Remove-LocalGroup -Name "AFQueryEngines"
    }

    # Installation has completed
    #
    write-output "`nInstallPIServerInstaller function:  Installation completed"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallPIServerInstaller function:  Installation completed"

    # Always return to your starting directory
    #
    popd
    Remove-Item $myTempDir\$product -recurse -force

    LogOutputFileExitFunctionText InstallPIServerInstaller

	$moduleName2print = "InstallPIServerInstaller"
	LogExecutionTime($fTime.Elapsed.ToString())
}

#*************************
function UpdateAFBackup()
{
    LogOutputFileEnterFunctionText UpdateAFBackup

    $fTime = [System.Diagnostics.Stopwatch]::StartNew()
 

    $afbackup = "AF\SQL\afbackup.bat"

	# See if we can get the path to the AF backup script
    try {
    if (test-Path "${env:PIHOME64}\$afbackup")
    { 
       $afbackuppath="${env:PIHOME64}\$afbackup"
    } 
    elseif (test-Path "${env:PIHOME}\$afbackup") { 
       $afbackuppath="${env:PIHOME}\$afbackup"
    }  
    }
    catch {
       # No action
    }
    try {
		if (($afbackuppath -ne $null) -and (Test-Path $afbackuppath))
		{
			# Remove the read only attribute from the file if set
			Set-ItemProperty $afbackuppath -Name IsReadonly -Value $false
			# load the file
			$content = Get-Content "$afbackuppath"
			# search for the configuration of the sql instance
			if ($content -match "^SET SQLINSTANCE=*")
			{
				# update the SQL instance to match that installed earlier
				write-output "`nUpdateAFBackup function:  Updating AF backup script: $afbackuppath to reference SQL Instance: $SQLInstanceName"
				write-output "`nUpdateAFBackup function:  Verify changes by 1) checking for $SQLInstanceName in $afbackuppath and 2) the results of running a backup" 
                LogOutputFileText $false " "
                LogOutputFileText $false "UpdateAFBackup function:  Updating AF backup script: $afbackuppath to reference SQL Instance: $SQLInstanceName"
				LogOutputFileText $false "UpdateAFBackup function:  Verify changes by 1) checking for $SQLInstanceName in $afbackuppath and 2) the results of running a backup" 
                LogOutputFileText $false " "
				$content -replace "^SET\s*SQLINSTANCE=.*$", "SET SQLINSTANCE=.\$SQLInstanceName" | Set-Content $afbackuppath
			}
			else
			{
				write-output "`nUpdateAFBackup function:  Update failed for AF backup script: $afbackuppath. Update AF backup file manually to reference SQL Instance: $SQLInstanceName"
                LogOutputFileText $true "UpdateAFBackup function:  Update failed for AF backup script: $afbackuppath. Update AF backup file manually to reference SQL Instance: $SQLInstanceName"       
			}	
		}
		else
		{
		write-output "`nUpdateAFBackup function:  Cannot find AF backup script. Update AF backup file manually to reference SQL Instance: $SQLInstanceName"
        LogOutputFileText $true "UpdateAFBackup function:  Cannot find AF backup script. Update AF backup file manually to reference SQL Instance: $SQLInstanceName"
		}
	}
    catch 
    {
        write-output "`nUpdateAFBackup function:  Update failed for AF backup script. Update AF backup file manually to reference SQL Instance: $SQLInstanceName"
        LogOutputFileText $true "UpdateAFBackup function:  Update failed for AF backup script. Update AF backup file manually to reference SQL Instance: $SQLInstanceName"
    }
    
    LogOutputFileExitFunctionText UpdateAFBackup

	$moduleName2print = "UpdateAFBackup"
	LogExecutionTime($fTime.Elapsed.ToString())
}

#*************************
function CreateAFDatabase($AFDatabase)
{
    LogOutputFileEnterFunctionText CreateAFDatabase

	# Create an AF database on the local AF Server for use by the Smart Connector
    write-output "`nCreateAFDatabase function:  Create an AF database on the local AF Server for use by the Smart Connector`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "CreateAFDatabase function:  Create an AF database on the local AF Server for use by the Smart Connector"
	
	$errorStatus = 0

	# if Database isn't specified, use the default name
	if ($AFDatabase -eq $null) {
		$AFDatabase="DeltaV"
	}
	# See if we can load the assembly and create a PISystems object
    try
    {
		[System.Reflection.Assembly]::LoadWithPartialName("OSIsoft.AFSDK") | Out-Null
		$afServers = new-object OSIsoft.AF.PISystems
	} catch { 
		write-output "`nCreateAFDatabase function:  Create AF Database Error: Unable to Load AFSDK"
        LogOutputFileText $true "CreateAFDatabase function:  Create AF Database Error: Unable to Load AFSDK"
		$errorstatus=1
	}
	# Connect to the AF Server and if the database does not exist, create it
	if ($errorstatus -eq 0)
    {
	    try
        { 
		    $AFServerName=[System.Net.Dns]::GetHostByName((hostname)).HostName
    		$afServer = $afServers[$AFServerName]
	    	$afServer.Databases.Refresh | Out-Null
		
            if ( $afServer.Databases[$AFDatabase] -eq $null)
                {
    			    $afServer.Databases.Add($AFDatabase) | Out-Null
	    		    if ( $afServer -eq $null ) {
		    		    $errorStatus=1
			    } else {
				    write-output "`nCreateAFDatabase function:  AF Database created:  $AFDatabase"
                    LogOutputFileText $false " "
                    LogOutputFileText $false "CreateAFDatabase function:  AF Database created: $AFDatabase"
	     			$afServer=$null
		    	}
    		} else {
	    		write-output "`nCreateAFDatabase function:  AF Database already exists, skipping creation:  $AFDatabase"
                LogOutputFileText $false " "
                LogOutputFileText $false "nCreateAFDatabase function:  AF Database already exists, skipping creation:  $AFDatabase"
		    }
    	}
	catch { 
		    $errorStatus = 1
	    } 
	}
	if ($errorStatus -eq 1) { 
		write-output "`nCreateAFDatabase function:  Error: Cannot create AF database, unable to connect to AF Server: $AFServerName"
		write-output "`nCreateAFDatabase function:  Check that the AF Server is installed and running"
		write-output "`nCreateAFDatabase function:  Alternatively Create an AF Database manually called: DeltaV and install the DeltaV Smart Connector."
        LogOutputFileText $true  "CreateAFDatabase function:  Error: Cannot create AF database, unable to connect to AF Server: $AFServerName"
		LogOutputFileText $false "CreateAFDatabase function:  Check that the AF Server is installed and running"
		LogOutputFileText $false "CreateAFDatabase function:  Alternatively Create an AF Database manually called: DeltaV and install the DeltaV Smart Connector.`n`n"
	}
	
    LogOutputFileExitFunctionText CreateAFDatabase

	$moduleName2print = "CreateAFDatabase"
	LogExecutionTime($fTime.Elapsed.ToString())
}

#*************************
function AddArchives()
{
    LogOutputFileEnterFunctionText AddArchives

	$fTime = [System.Diagnostics.Stopwatch]::StartNew()

    # Create and add two archives to the PI Data Archive
	#
    write-output "`nAttempting to configure additional archives to the PI Data Archive`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "Attempting to configure additional archives to the PI Data Archive"

	if ($DDriveFound -eq "true")
    {
        $archives="D:\PI\Archives\piarch.00"
    }
    else
    {
        $archives="C:\PI\Archives\piarch.00"
    }

    $archivesize=256;

    try
    {
		if ($env:PIServer -ne $null) { 
			for ($i=1; $i -lt 3;$i++) {
				write-output "Creating archive: $archives$i"
                LogOutputFileText $false " "
                LogOutputFileText $false "Creating archive: $archives$i"
				$rc = Start-Process  ((Get-Item $env:PIServer).FullName + "\adm\piarcreate.exe") -ArgumentList "$archives$i $archivesize" -Wait -PassThru -NoNewWindow
				if ($rc.ExitCode -ne 0)
				{
					write-output "`nArchive creation returned error code: $($rc.ExitCode)"
                    LogOutputFileText $true "Archive creation returned error code: $($rc.ExitCode)"
				}
				$rc = Start-Process -FilePath ((Get-Item $env:PIServer).FullName + "\adm\piartool.exe") -ArgumentList "-ar $archives$i" -Wait -PassThru -NoNewWindow
				if ($rc.ExitCode -ne 0)
				{
					write-output "`nArchive registration returned error code: $($rc.ExitCode)"
                    LogOutputFileText $true "Archive registration returned error code: $($rc.ExitCode)"
				}
			}
		} else {
		write-output "`nUnable to locate PI software directory, please create additional archives manually"
        LogOutputFileText $false " "
        LogOutputFileText $false "Unable to locate PI software directory, please create additional archives manually"
		}
    } catch {
        write-output "`nError creating archives, please create additional archives manually"
        LogOutputFileText $true "Error creating archives, please create additional archives manually" 
    } 
    
    LogOutputFileExitFunctionText AddArchives

	$moduleName2print = "AddArchives"
	LogExecutionTime($fTime.Elapsed.ToString())
}

#*************************
function UninstallDeltaV_SC()
{
    LogOutputFileEnterFunctionText UninstallDeltaV_SC
    
    write-output "`nUninstall intended to ensure a DeltaV Asset Connector upgrade is not attempted"
    write-output "`n   for an installed version incompatible with the new version"
    LogOutputFileText $false " "
    LogOutputFileText $false "Uninstall intended to ensure a DeltaV Asset Connector upgrade is not attempted"
    LogOutputFileText $false "   for an installed version incompatible with the new version"

    $scapp = Get-WmiObject Win32_Product -Filter "Name LIKE '%DeltaV_ACtr%'"

    if($scapp.Name -like "*DeltaV_ACtr*")
    {    
        #Uninstall Version 3.x of the DeltaV Smart Connector
        write-output "`nUninstalling DeltaV Asset Connector"
        LogOutputFileText $false " "
        LogOutputFileText $false "Uninstalling DeltaV Asset Connector"
        try
        {
            $scapp.Uninstall() | Out-Null
        }
        catch
        {
            LogOutputFileText $true "Unable to uninstall DeltaV Asset Connector"
            throw "Unable to uninstall DeltaV Asset Connector"
        }
        
        #Rename the AC config file
        write-output "`nRenaming DeltaV Asset Connector configuration file."
        LogOutputFileText $false " "
        LogOutputFileText $false "Renaming DeltaV Asset Connector configuration file."

        try{
            $acconfig = (Get-Item $env:PIHOME).FullName + "\Asset Connectors\DeltaV\PIDeltaV_ACtr.exe.config"
            if (Test-Path ($acconfig + ".old"))
            {
                Remove-Item ($acconfig + ".old")
            }
            Rename-Item $acconfig ($acconfig +".old") -Force
        } catch {
            LogOutputFileText $true "Unable to rename the Asset Connector configuration file."  
            throw "Unable to rename the Asset Connector configuration file."  
        }
    }
    else
    {
        write-output "`nDeltaV Asset Connector is not installed, will proceed with DeltaV Asset Connector installation."
        LogOutputFileText $false " "
        LogOutputFileText $false "DeltaV Asset Connector is not installed, will proceed with DeltaV Asset Connector installation."
    }
	
    LogOutputFileExitFunctionText UninstallDeltaV_SC

#	$moduleName2print = "UninstallDeltaV_SC"
#	LogExecutionTime($fTime.Elapsed.ToString())
}

function UpdateDeltavService()
{
	# Set the Service name and new account name
	$DeltaVActr = "PI DeltaV Asset Connector"
	$DeltaVActrServiceAccount = "NT Service\$DeltaVActr"
	try {
		# Change Service account name so it is no longer 'Local System'
		# Ref: https://gallery.technet.microsoft.com/scriptcenter/79644be9-b5e1-4d9e-9cb5-eab1ad866eaf
		$ServiceWMI = gwmi win32_service -computername $env:computername -filter "name='$DeltaVActr'"
		$ChangeStatus = $ServiceWMI.change($null,$null,$null,$null,$null,$null,"NT Service\$DeltaVActr",$null,$null,$null,$null) 
		If ($ChangeStatus.ReturnValue -eq 0) {
			LogFileAndOutputText $false "$DeltaVActr -> Service account updated."
			try {
				# Add authorization for the account to create objects in Asset Framework
				$AFServer = (Get-AFServer -Name $env:computername)
				$Engineers = Get-AFSecurityIdentity -Name "Engineers" -Refresh -AFServer $AFServer
				Add-AFSecurityMapping -Name $DeltaVActr -WindowsAccount "NT Service\$DeltaVActr" -AFSecurityIdentity $Engineers -CheckIn -AFServer $AFServer
				}
				catch {
					LogFileandOutputExitText $false "Error adding AF access."
					LogFileandOutputExitText $false "Error: $_"
				}
			$Service = Restart-Service -Name $DeltaVActr -PassThru
			If ($Service.Status -eq "Running") { # validating status - http://msdn.microsoft.com/en-us/library/aa393673(v=vs.85).aspx 
					LogFileAndOutputText $false "$DeltaVActr -> Service restarted."
			} else {
				LogFileAndOutputText $false $Status
				LogFileandOutputExitText $false "$DeltaVActr -> Service did not restart. Please manually restart. $Status"
			}
		} else {
			LogFileandOutputExitText $false "$DeltaVActr -> Service name not changed. Recommendation: Manually change service account name to `"NT Service\$DeltaVActr`"."
		}
	} 
	catch {
			LogFileandOutputExitText $false "Unable to change $DeltaVActr Account. Error: $_"
	}
}

#*************************
function InstallDeltaV_SC()
{
    LogOutputFileEnterFunctionText InstallDeltaV_SC

    $fTime = [System.Diagnostics.Stopwatch]::StartNew()

    # Set properties needed to install the DeltaV Smart Connector
    $product      = "DeltaV_Actr_4.1.1.79"
    $setupExeFile = "DeltaV_SC_4.1.1.79_.exe"
    $silent       = "silent\DeltaV_SC_4.1.1.79_silent.ini"
	$silent_custom = "${myTempDir}\DeltaV_SC_4.1.1.79_silent.ini"

    write-output "`nInstallDeltaV_SC function: Attempting to install  the DeltaV Smart Connector`n"
    LogOutputFileText $false " "
    LogOutputFileText $false "InstallDeltaV_SC function: Attempting to install DeltaV Smart Connector`n"

    #--- Perform Action ---#
    #
    ExpandSetupKitExe $product $setupExeFile

	#--- Update silent.ini ---#
	
	(Get-Content $silent) | 
	Foreach-Object {$_ -replace "DELTAV_HOSTNAME",$env:computername}  | 
	Out-File $silent_custom
	
    #--- Perform Action ---#
    #
    PerformSilentInstallation $product $silent_custom
	
	UpdateDeltaVService

    #--- Perform Action ---#
    #
    LogOutputFileExitFunctionText InstallDeltaV_SC

	$moduleName2print = "InstallDeltaV_SC"
	LogExecutionTime($fTime.Elapsed.ToString())
}

#*************************
function PerformAFServerPostInstallationTasks()
{
    LogOutputFileEnterFunctionText PerformAFServerPostInstallationTasks

    $fTime = [System.Diagnostics.Stopwatch]::StartNew()
    

    write-output "`nPerformAFServerPostInstallationTasks function:  Get the value for the PIServer EnvironmentVariable"
    LogOutputFileText $false " "
    LogOutputFileText $false "PerformAFServerPostInstallationTasks function:  Get the value for the PIServer EnvironmentVariable"

	$i=0
    while (-Not $env:PISERVER)
    {
		$i++
        $now = Get-Date -f "MM-dd-yyyy HH:mm:ss"
        
        write-output "`nPerformAFServerPostInstallationTasks function:  $now, PISERVER not set yet in the environment"
        LogOutputFileText $false " "
        LogOutputFileText $false "PerformAFServerPostInstallationTasks function:  $now, PISERVER location not set yet in the environment"
        
        Start-Sleep -seconds 5

        write-output "`nPerformAFServerPostInstallationTasks function:  Update-Environment function call"
        LogOutputFileText $false " "
        LogOutputFileText $false "PerformAFServerPostInstallationTasks function:  Update-Environment function call"
        Update-Environment # Call again to pick up variables set by the PI Installer package
		
        if ($i -gt 6)
        {
            LogOutputFileText $true "PerformAFServerPostInstallationTasks function:  $now, PISERVER location environment variable not set. Check for successful installation of the PI Data Archive."
			throw "PerformAFServerPostInstallationTasks function:  $now, PISERVER environment variable not set. Check for successful installation of the PI Data Archive."
		}
    }
    write-output "`nPerformAFServerPostInstallationTasks function:  PISERVER location is set in the environment as $env:PISERVER"
    LogOutputFileText $false " "
    LogOutputFileText $false "PerformAFServerPostInstallationTasks function:  PISERVER location is set in the environment as $env:PISERVER"
    LogOutputFileText $false " "	

  	# Update the backup script to refer to the SQL Instance 
	#
	UpdateAFBackup
	
	# Create an AF database for the Emerson Smart Connector
	#
	CreateAFDatabase


    #--- Perform Action ---#
    #
    LogOutputFileExitFunctionText PerformAFServerPostInstallationTasks

	$moduleName2print = "PerformAFServerPostInstallationTasks"
	LogExecutionTime($fTime.Elapsed.ToString())
}

#*************************
function ExpandSetupKitExe($product,$setupExeFile)
{
    LogOutputFileEnterFunctionText ExpandSetupKitExe

    # Use absolute path to the setup kit self-extracting EXE
    #
    $zipArchiveWithPath = "$myScriptDir\$setupExeFile"

    # Extraction will be performed from under the temp scripts folder
    #
    $workingDir = "$myScriptDir"
    write-output "`n`nExpandSetupKitExe:  Perform extraction from the temp scripts folder - going there now:"
    write-output "`n`n     $workingDir"
    LogOutputFileText $false " "
    LogOutputFileText $false " "
    LogOutputFileText $false "ExpandSetupKitExe:  Perform extraction from the temp scripts folder - going there now:"
    LogOutputFileText $false " "
    LogOutputFileText $false "     $workingDir"
    pushd $workingDir
 
    write-output "`n`nExpandSetupKitExe function: Extraction command for:"
    write-output "`n`n     1) product:        $product"
    write-output "`n`n     2) setup EXE file: $setupExeFile"
    write-output "`n`nExpandSetupKitExe function: Extraction command parameters:"
    write-output "`n`n     7zip Exe location:     $7zipExeLocation"
    write-output "`n`n     Output folder:         -o`"$myTempDir`""
    write-output "`n`n     Setup kit with path:   $zipArchiveWithPath"

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
    write-output "`n`nExpandSetupKitExe function:  Attempting to expand setup kit self-extracting executable for:  $setupExeFile"
    LogOutputFileText $false " "
    LogOutputFileText $false " "
    LogOutputFileText $false "ExpandSetupKitExe function:  Attempting to expand setup kit self-extracting executable for:  $setupExeFile"    

    $rc = Start-Process -FilePath $7zipExeLocation -ArgumentList "x -y -o`"$myTempDir`" `"$zipArchiveWithPath`"" -Wait -PassThru -NoNewWindow
    if ($rc.ExitCode -ne 0)   # 0 means ok
    {
#        popd
        LogOutputFileText $true "ExpandSetupKitExe function - $product : Installation process returned error code: $($rc.ExitCode)"
        throw "ExpandSetupKitExe function - $product : Installation process returned error code: $($rc.ExitCode)"
    }

    write-output "`nExpandSetupKitExe function:  Expanding of setup kit is complete for self-extracting executable:  $setupExeFile"
    LogOutputFileText $false " "
    LogOutputFileText $false " "
    LogOutputFileText $false "ExpandSetupKitExe function:  Expanding of setup kit is complete for self-extracting executable:  $setupExeFile"    


    # Always return to your starting directory
    #
    popd
    LogOutputFileExitFunctionText ExpandSetupKitExe
}

#*************************
function PerformSilentInstallation($product,$silent)
{
    write-output "`n`nPerformSilentInstallation function:  Attempting to install product:  $product"
    LogOutputFileText $false " "
    LogOutputFileText $false " "
    LogOutputFileText $false "PerformSilentInstallation function: Attempting to install product:  $product"
    LogOutputFileText $false " "

    # Everything will be done from under the temp folder
    #
    $workingDir = "$myTempDir\$product"


    # Copy custom silent.ini file from archive location to installation working folder
    Copy-Item $silent $workingDir\silent.ini -Force -errorVariable errors


    if ($errors.count -ne 0 ) 
    {
        LogOutputFileText $true "PerformSilentInstallation function: Error updating silent.ini file:  $product"
        throw "PerformSilentInstallation function: Error updating silent.ini file:  $product"
    }


    write-output "`nPerformSilentInstallation function: Going to work folder:  $workingDir"
    LogOutputFileText $false " "
    LogOutputFileText $false "PerformSilentInstallation function: Going to work folder:  $workingDir"
    pushd $workingDir
    

    # Need to use silent.bat file if attempting to install the PI Data Archive
    #
    if ($product -like "Enterprise_x64")
    {
        # Update the silent.ini file if a D: drive is NOT found on the target installation system;
        # if a D: drive is NOT found, D: drive entries are updated to contain system drive value C:\
        if((Test-Path D:) -and (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='D:'").DriveType -eq [int]3)
        {
            write-output "`nInstallPIDataArchive function:  Update the custom PI Data Archive silent.ini file to replace D drive (D:\) with C drive (C:\)"
            LogOutputFileText $false " "
            LogOutputFileText $false "InstallPIDataArchive function:  Update the custom PI Data Archive silent.ini file to replace D drive (D:\) with C drive (C:\)"

            $contents=Get-Content .\silent.ini 
            $contents -replace "D:\\", "C:\" | Set-Content .\silent.ini -Force
        }

        # Begin install attempt using silent.bat
        $rc = Start-Process -FilePath ".\silent.bat" -ArgumentList "-install" -Wait -PassThru -NoNewWindow
    }
    else   # Use the custom silent.ini file directly and without additional modifications
    {
        # Begin install attempt using silent.ini
        $rc = Start-Process -FilePath ".\Setup.exe" -ArgumentList "-f `"silent.ini`"" -Wait -PassThru -NoNewWindow
    }
     if (($rc.ExitCode -ne 0) -and ($rc.ExitCode -ne 3010))   # 3010 means ok, but need to reboot
    {
#        popd
        LogOutputFileText $true "PerformSilentInstallation function - $product : Installation process returned error code: $($rc.ExitCode)"
        throw "PerformSilentInstallation function - $product : Installation process returned error code: $($rc.ExitCode)"
    }
        
    # Always return to your starting directory
    #
    popd
    Remove-Item $workingDir -recurse -force
    
    LogOutputFileExitFunctionText PerformSilentInstallation
}


# ========================================================================================
# ========================================================================================
#
#   Start:  Main Body of Script
#
# ========================================================================================
# ========================================================================================
# SECTION 3:  Learn about this system
#
# Get location
#
$myScriptOrigin = $MyInvocation.MyCommand.Path
$myScriptSource = Split-Path $myScriptOrigin

$piserver_version = "PI2018_SP3_patch_1"
$piserver_version_text = "PI Server 2018 SP3 Patch 1"


# Do not call the LogOutputText function for the initial informational message
# Need to first create folder, in temp area, to hold log file
write-output "`n`n"
write-output "`nInstalling the Emerson Advanced Continuous Historian"
write-output "`n"
write-output "`n`nExecuting Install script version:  $scriptVersion"


# Check to see if output log file folder already exists
#
$myLogFileDir = (Get-Item $env:TEMP).FullName + $piserver_version + "_Install_ExecutionOuputLog"
if (Test-Path $myLogFileDir -type container)
{
    # if output file folder exists, wipe out everything here to ensure execution output
	# is from current installation attempt and not previous ones
    #
    Start-Sleep -seconds 5
    Remove-Item $myLogFileDir -recurse -force
}
elseif (Test-Path $myLogFileDir -type leaf)
{
    Start-Sleep -seconds 5
    Remove-Item $myLogFileDir -recurse -force
} 
# Create output log file folder
#
write-output "`n`nCreating folder for execution output file - this action may take a few seconds"
mkdir $myLogFileDir

# Execution output folder is now created, begin logging messages to file
LogOutputFileText $false " "
LogOutputFileText $false "Installing the Emerson Advanced Continuous Historian"
LogOutputFileText $false " "
LogOutputFileText $false "Executing Install script version:  $scriptVersion"


write-output "`n`nScript execution output log: $myLogFileDir\InstallACHlog.txt"
LogOutputFileText $false " "
LogOutputFileText $false "Script execution output log: $myLogFileDir\InstallACHlog.txt"


# Check to see if script files folder already exists
#
$myScriptDir = (Get-Item $env:TEMP).FullName + $piserver_version + "_Install_ScriptFiles"
if (Test-Path $myScriptDir -type container)
{
    # if script files folder exists, wipe out everything here to ensure execution
	# is using files from current installation attempt and not previous ones
    #
    Start-Sleep -seconds 5
    Remove-Item $myScriptDir -recurse -force
}
elseif (Test-Path $myScriptDir -type leaf)
{
    Start-Sleep -seconds 5
    Remove-Item $myScriptDir -recurse -force
} 
# Create script files folder
#
write-output "`n`nCreating folder for script files - this action may take a few seconds`n`n"
mkdir $myScriptDir

# Copy all files needed to execute script from DVD to target installation system
write-output "`n`nCopying all files needed to execute script - this may take a few seconds "
write-output "`n`n     From:  $myScriptSource"
write-output "`n`n     To:    $myScriptDir`n`n"
LogOutputFileText $false " "
LogOutputFileText $false "Copying all files needed to execute script - this may take a few seconds"
LogOutputFileText $false " "
LogOutputFileText $false "     From:  $myScriptSource"
LogOutputFileText $false " "
LogOutputFileText $false "     To:    $myScriptDir"
LogOutputFileText $false " "
LogOutputFileText $false " "

Copy-Item -Path "$myScriptSource\*" -Destination "$myScriptDir" -recurse -Force

# Determine bitness and OS version
#
# Default global flag to indicate a 32-bit system
$X64_SYSTEM = "false"
$bitness = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
#write-debug "OS bitness is $bitness ...`n"
$OSversion = (Get-WmiObject Win32_OperatingSystem).Version

# If this is a 64-bit system, set global flag to indicate this is so.
if ($bitness -like "*64*")
{
    $X64_SYSTEM = "true"
}

# Determine the PI Data Archive installation drive:
#
#	If the preferred drive, D:\, is NOT found on the target installation system, use the C:\ drive instead.
#
# Default DDriveFound to be true since this is the prefferred drive to use
$DDriveFound = "true"
if((Test-Path D:) -and (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='D:'").DriveType -eq [int]3)
{
    write-output "`nDetermine PI Data Archives location: D drive (D:\) found, using D drive (D:\) for the PI Data Archives files location: DDriveFound = $DDriveFound"
    LogOutputFileText $false " "
    LogOutputFileText $false "Determine PI Data Archives location: D drive (D:\) found, using D drive (D:\) for the PI Data Archives files location: DDriveFound = $DDriveFound"
	LogOutputFileText $false " "
	LogOutputFileText $false " "
}
else
{
    $DDriveFound="false"
    write-output "`nDetermine PI Data Archives location: D drive (D:\) not found, use C drive (C:\) for the PI Data Archives files location: DDriveFound = $DDriveFound"
    LogOutputFileText $false " "
    LogOutputFileText $false "Determine PI Data Archives location: D drive (D:\) not found, use C drive (C:\) for the PI Data Archives files location: DDriveFound = $DDriveFound"
	LogOutputFileText $false " "
	LogOutputFileText $false " "
}

# PI Data Archive supports 64-bit systems ONLY
#   If an attempt is made to install on a non-64-bit system, halt script execution.
if ($X64_SYSTEM -ne "true") # 32-bit system found
{
    LogOutputFileText $true "Install-ACH - $piserver_version_text script cannot be installed:  Operating System is not supported.  $piserver_version_text is supported on 64-bit operating systems only.  Quitting script.`n"
    throw "Install-ACH - $piserver_version_text script cannot be installed:  Operating System is not supported.  $piserver_version_text is supported on 64-bit operating systems only.  Quitting script.`n"
}


# PI Data Archive supports Windows Server 2016 or Windows 10
#   If an attempt is made to install on a non-supported OS, halt script execution.
if(-not ($OSversion -like "10.0*"))
{
    LogOutputFileText $true "Unsupported OS Version detected:  $OSVersion `nThe operating system must be Windows Server 2016 or Windows 10 Anniversary Edition for production environments.  Quitting script."
    throw "Unsupported OS Version detected:  $OSVersion `nThe operating system must be Windows Server 2016 or Windows 10 Anniversary Edition for production environments.  Quitting script."
}


#
# Verify 7zip program exists
# 
$7zipExeLocation="$myScriptDir\7z.exe"

write-output "`n7zip exectuable located in folder: $7zipExeLocation`n"
LogOutputFileText $false "7zip exectuable located in folder: $7zipExeLocation"

if (-not (test-path $7zipExeLocation))
{
    LogOutputFileText $true "The following program is required to continue: $7zipExeLocation"
    throw "The following program is required to continue: $7zipExeLocation"
}

# create temporary working folder to operate on
#
$myTempDir = (Get-Item $env:TEMP).FullName + "\" + $piserver_version + "_Install"   #22-Sept-2014 JGalginaitis: Used Full Name of
                                                                     #  $env:TEMP, rather than the default short name
if (Test-Path $myTempDir -type container)
{
    # wipe out everything here
    #
    write-output "`nTemporary work folder already exists - removing to ensure fresh installation"
    LogOutputFileText $false " "
    LogOutputFileText $false "Temporary work folder already exists - removing to ensure fresh installation"

    Start-Sleep -seconds 10
    Remove-Item $myTempDir -recurse -force
}
elseif (Test-Path $myTempDir -type leaf)
{
    write-output "`nTemporary work folder already exists - removing"
    LogOutputFileText $false " "
    LogOutputFileText $false "Temporary work folder already exists - removing"
    
    Start-Sleep -seconds 10
    Remove-Item $myTempDir -recurse -force
} 
write-output "`n`nCreating temporary work folder - this action may take a few seconds"
write-output "`n`n     Installations will be executed from here:  $myTempDir`n`n"
LogOutputFileText $false " "
LogOutputFileText $false "Creating temporary work folder - this action may take a few seconds"
LogOutputFileText $false " "
LogOutputFileText $false "     Installations will be executed from here:  $myTempDir"
mkdir $myTempDir


# ========================================================================================
# SECTION 4:  Process the command-line options
#
#             Execute appropriate installers based on the options specified
#

# Increment as parameters are processed and individual components installed
# If no parameters are specified install all components
$noparams = 1

#Install SQL Server Express: 22-Sept-2014 JGalginaits: Install SQL only if -sql switch specified.  No longer installed by default
if ($sql)
{    
	$noparams = 0
   
    InstallSQLServerExpress
}

#Install the Advanced Continuous Historian
if ($ach)
{
	$noparams = 0

    InstallPIServerInstaller
	Update-Environment
	PerformAFServerPostInstallationTasks
    StartPIDataArchive
    Update-KSTandTuningParameters
}

#Install Emerson DeltaV SmartConnector
if ($sc)
{
	$noparams = 0
	
    InstallDeltaV_SC
}

#Create additional archives
if ($archives)
{
	$noparams = 0

    AddArchives
}

#Create additional archives
if ($updatesOnly)
{
	$noparams = 0
	
    StopDisableConnectors
    Update-KSTandTuningParameters
    UninstallDeltaV_SC
    InstallDeltaV_SC	
}

#
# If no command line parameters supplied for specific installation components, install all components
#
if ($noparams) 
{ 
	StopDisableConnectors
    InstallPIServerInstaller
	Update-Environment
    PerformAFServerPostInstallationTasks
    StartPIDataArchive
    Update-KSTandTuningParameters
    AddArchives
    UninstallDeltaV_SC
    InstallDeltaV_SC
}

$elapsed = $Time.Elapsed.ToString()
$EndTime = Get-Date -f "MM-dd-yyyy HH:mm:ss"

write-output "`nScript started at $StartTime"
write-output "`nScript ended at $EndTime"
write-output "`nTotal Elapsed Time: $elapsed"

LogOutputFileText $false " "
LogOutputFileText $false "Script started at $StartTime"
LogOutputFileText $false "Script ended at $EndTime"
LogOutputFileText $false "Total Elapsed Time: $elapsed"


# clean up my temp folder if it is still present
#
if (Test-Path $myTempDir)
{
    write-output "`nPre-ScriptCompletion Cleanup:  Temporary folder is still present:  Deleting it"
    LogOutputFiletext $false " "
    LogOutputFileText $false "Pre-ScriptCompletion Cleanup:  Temporary folder is still present:  Deleting it"

    Remove-Item $myTempDir -recurse -force
}


# clean up my script files folder if it is still present
#
if (Test-Path $myScriptDir)
{
    write-output "`nPre-ScriptCompletion Cleanup:  Script files folder is still present:  Deleting it"
    LogOutputFiletext $false " "
    LogOutputFileText $false "Pre-ScriptCompletion Cleanup:  Script files folder is still present:  Deleting it"

    Remove-Item $myScriptDir -recurse -force
}

write-output "`nSoftware installation finished."
LogOutputFileText $true "Software installation finished."

#08-Feb-2017 JRoberts: Emerson no longer wants the reboot messages logged
#write-output "`n`nPlease reboot to complete the installation."
#LogOutputFileText $true "Please reboot to complete the installation."
#
#08-Feb-2017 JRoberts: Emerson no longer wants the reboot message box displayed
# display message to reboot system
#$wshell = New-Object -ComObject Wscript.Shell
#$wshell.Popup("To complete the Emerson Advanced Continuous Historian installation, please reboot now.",0,"Install-ACH Script Execution has Completed",0)