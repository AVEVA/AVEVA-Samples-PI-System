#requires -version 4.0
<##############################################################################

Functions for setting up OSIsoft test environment and running work flow.

###############################################################################>

### Constants ###
## OSIsoftTests ##
$Root = Split-Path -Path $PSScriptRoot -Parent
$BuildPlatform = 'Any CPU'
$BuildConfiguration = 'Release'
$WindFarmxml = Join-Path $Root 'xml\OSIsoftTests-Wind.xml'
$Source = Join-Path $Root 'source'
$Logs = Join-Path $Root 'logs'
$AppConfigFile = Join-Path $Source 'App.config'
$TestResults = Join-Path $Root 'testResults'
$Solution = Join-Path $Source 'OSIsoft.PISystemDeploymentTests.sln'
$Binaries = Join-Path $Source 'bin' | Join-Path -ChildPath $BuildConfiguration
$TestDll = Join-Path $Binaries 'OSIsoft.PISystemDeploymentTests.dll'
$PSEErrorHandlingMsg = "Please use PI System Explorer to run this step and troubleshoot any potential issues."
$TestsPIPointSource = "OSIsoftTests"
$SamplePIPoint = "OSIsoftTests.Region 0.Wind Farm 00.TUR00000.SineWave"
$CoveredByRecalcPIPointRegex = "Random|SineWave"
$DefaultPIDataStartTime = "*-1d"
$PIAnalysisServicePort = 5463
$WaitIntervalInSeconds = 10
$MaxRetry = 120
$RetryCountBeforeReporting = 18
$LastTraceTime = Get-Date
$FormatedLastTraceTime = "OSIsoftTests_{0:yyyy.MM.dd@HH-mm-ss}" -f $Script:LastTraceTime
$ExecutionLog = Join-Path $Logs "$FormatedLastTraceTime.log"
$MaxLogFileCount = 50
$TestResultFile = Join-Path $TestResults "$FormatedLastTraceTime.html"
$PreCheckTestResultFile = Join-Path $TestResults ($FormatedLastTraceTime + "_PreCheck.html")
$RequiredSettings = @("PIDataArchive", "AFServer", "AFDatabase", "PIAnalysisService")
$HiddenSettingsRegex = "user|password|encrypt"
# A hashtable mapping the appSettings to the test classes of optional products with a string key setting.
$TestClassesForOptionalProductWithKeySetting = @{ 
    PINotificationsService = "NotificationTests";
    PIWebAPI               = "PIWebAPITests";
    PIManualLogger         = "ManualLoggerTests"; 
    PIVisionServer         = "Vision3Tests"
}
# A hashtable mapping the appSettings to the test classes of optional products with a boolean key setting.
$TestClassesForOptionalProductWithBooleanFlag = @{ 
    PIDataLinkTests  = "DataLinkAFTests,DataLinkPIDATests"; 
    PISqlClientTests = "PISqlClientTests"
}
## Build Tools ##
$DefaultMSBuildVersion = 15
$NuGetExe = Join-Path $Root '.nuget\nuget.exe'
$MSBuildExe = ""
$TempDir = Join-Path $Root 'temp'
$DotNETFrameworkDir = "${Env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8"
$DotNETDevPackFileName = 'ndp48-devpack-enu.exe'
$DotNETDevPack = Join-Path $TempDir $DotNETDevPackFileName
$VSBuildToolsFileName = 'VS_BuildTools.exe'
$VSBuildTools = Join-Path $TempDir $VSBuildToolsFileName
$NuGetExeUri = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
$DotNETDevPackUri = "https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/" +
"c8c829444416e811be84c5765ede6148/ndp48-devpack-enu.exe"
$VSBuildToolsUri = "https://download.visualstudio.microsoft.com/download/pr/a1603c02-8a66-4b83-b821-811e3610a7c4/" + 
"aa2db8bb39e0cbd23e9940d8951e0bc3/vs_buildtools.exe"
$xUnitConsole = Join-Path $Source 'packages\xunit.runner.console.2.4.1\tools\net471\xunit.console.exe'
$VsWhereExe = "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$BuildTools = "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\BuildTools"


function Add-VerboseLog() {
    [cmdletbinding()]
    param
    (
        [string]
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        $Message,

        [switch]
        [Parameter(Mandatory = $false)]
        $Log = [switch]::Present
    )
    $processedMessage = "[$(Trace-Time)]`t$Message"
    Write-Verbose  $processedMessage

    #If logging is enabled, write to file
    if ($Log) { try { $processedMessage | Write-ExecutionLog } catch { $_ = $Error } }
}


function Add-InfoLog() {
    [cmdletbinding()]
    param
    (
        [string]
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        $Message,

        [switch]
        [Parameter(Mandatory = $false)]
        $Log = [switch]::Present
    )
    $processedMessage = "[$(Trace-Time)]`t$Message"
    Write-Host $processedMessage

    #If logging is enabled, write to file
    if ($Log) { try { $processedMessage | Write-ExecutionLog } catch { $_ = $Error } }
}


function Add-WarningLog() {
    [cmdletbinding()]
    param
    (
        [string]
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        $Message,

        [switch]
        [Parameter(Mandatory = $false)]
        $Log = [switch]::Present
    )
    $processedMessage = "[$(Trace-Time)]`t$Message"
    Write-Warning $processedMessage

    #If logging is enabled, write to file
    if ($Log) { try { $processedMessage | Write-ExecutionLog } catch { $_ = $Error } }
}


function Add-ErrorLog {
    [cmdletbinding()]
    param
    (
        [string]
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        $Message,

        [switch]
        [Parameter(Mandatory = $false)]
        $Log = [switch]::Present,

        [switch]
        [Parameter(Mandatory = $false)]
        $Fatal
    )
    $processedMessage = "[$(Trace-Time)]`t$Message"

    #If logging is enabled, write to file
    if ($Log) { try { $processedMessage | Write-ExecutionLog } catch { $_ = $Error } }

    if (-not $Fatal) {
        Write-Host $processedMessage -ForegroundColor Red
    }
    else {
        Write-Host ($processedMessage + [Environment]::NewLine) -ForegroundColor Red
        exit 1
    }
}


function Write-ExecutionLog {
    [cmdletbinding()]
    param
    (
        [string]
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        $Message,

        [int32]
        [Parameter(Mandatory = $false)]
        $MaxLogs = $MaxLogFileCount
    )
    Begin {
        # Prepare the log path and file
        $logFolder = Split-Path $ExecutionLog -Parent
        New-FolderIfNotExists($logFolder)

        # Create the logs folder if missing and remove old logs
        if (!(Test-Path -Path $ExecutionLog)) {
            New-Item -ItemType File -Path $ExecutionLog -Force > $null
        
            $logCount = (Get-ChildItem $logFolder | Measure-Object).Count
            $logsByDate = (Get-ChildItem $logFolder | Sort-Object -Property CreationDate)
            $logIndex = 0

            while ($logCount -ge $MaxLogs) {
            
                Remove-Item -Path $logsByDate[$logIndex].FullName
                $logCount -= 1
                $logIndex += 1
            }
        }
    }
    Process {
        # Write the message to the log file
        Write-Output $_ >> $ExecutionLog
    }
}


function Trace-Time() {
    [CmdletBinding()]
    param ()
    $currentTime = Get-Date
    $lastTime = $Script:LastTraceTime
    $Script:LastTraceTime = $currentTime
    "{0:HH:mm:ss} +{1:F0}" -f $currentTime, ($currentTime - $lastTime).TotalSeconds
}


function Format-ElapsedTime($ElapsedTime) {
    '{0:D2}:{1:D2}:{2:D2}' -f $ElapsedTime.Hours, $ElapsedTime.Minutes, $ElapsedTime.Seconds
}


function New-FolderIfNotExists {
    [CmdletBinding()]
    param (
        [string]$FolderPath
    )
    if (!(Test-Path $FolderPath)) {
        New-Item -ItemType Directory -Force -Path $FolderPath
    }
}


function Install-NuGet {
    [CmdletBinding()]
    param()
    if (-not (Test-Path $NuGetExe)) {
        $NuGetFolder = Split-Path -Path $NuGetExe -Parent
        New-FolderIfNotExists($NuGetFolder)

        Add-InfoLog -Message "Downloading nuget.exe."

        Invoke-WebRequest $NuGetExeUri -OutFile $NuGetExe

        if (Test-Path $NuGetExe) {
            Add-InfoLog -Message "Downloaded nuget.exe successfully."
        }
        else {
            Add-ErrorLog -Message "Failed to download nuget.exe." -Fatal
        }
    }
}


function Install-DotNETDevPack {
    [CmdletBinding()]
    param()
    if (-not (Test-Path $DotNETFrameworkDir)) {
        if (-not (Test-Path $DotNETDevPack)) {
            New-FolderIfNotExists($TempDir)

            Add-InfoLog -Message "Downloading $DotNETDevPackFileName."
            Invoke-WebRequest $DotNETDevPackUri -OutFile $DotNETDevPack
            Add-InfoLog -Message "Downloaded $DotNETDevPackFileName."
        }

        # Install .NET Framework Developer Pack
        # Warn user about the reboot if .NET runtime will also be installed
        if ((Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release -lt 528040) {
            $proceed = Get-UserBooleanInput -Message ("The script will install .NET Framework of 4.8 and require a reboot after the installation, " + 
                "you may select 'Y' to proceed or 'N' to exit if you are not ready.")
            if (-not $proceed) {
                exit
            }
        }

        $p = Start-Process $DotNETDevPack -ArgumentList "/install /quiet" -PassThru -Wait
        if ($p.ExitCode -ne 0 -or -not (Test-Path $DotNETFrameworkDir)) {
            Add-ErrorLog -Message ("Failed to install .NET Developer Pack. " + 
                "Please run ""$DotNETDevPack"" interactively and troubleshoot any issues.") -Fatal
        }
        
        Add-InfoLog -Message "Installed .NET Developer Pack successfully."
    }
}


function Install-BuildTools {
    [CmdletBinding()]
    param()
    if (-not (Test-MSBuildVersionPresent)) {
        if (-not (Test-Path $VSBuildTools)) {
            New-FolderIfNotExists($TempDir)

            Add-InfoLog -Message "Downloading $VSBuildToolsFileName."
            Invoke-WebRequest $VSBuildToolsUri -OutFile $VSBuildTools
        }

        # Install Visual Studio Build Tools
        $p = Start-Process $VSBuildTools -ArgumentList "-q" -PassThru -Wait
        if ($p.ExitCode -ne 0 -or -not (Test-MSBuildVersionPresent)) {
            Add-ErrorLog -Message ("Failed to install MSBuild. " + 
                "Please run ""$VSBuildTools"" interactively and troubleshoot any issues.") -Fatal
        }

        Add-InfoLog -Message "Installed MSBuild successfully."
    }
}


function Get-LatestVisualStudioRoot {
    [CmdletBinding()]
    param()
    # Try to use vswhere to find the latest version of Visual Studio.
    if (Test-Path $VsWhereExe) {
        $installationPath = & $VsWhereExe -latest -prerelease -property installationPath
        if ($installationPath) {
            Add-VerboseLog -Message "Found Visual Studio installed at `"$installationPath`"."
        }
        
        return $installationPath
    }    
}


function Get-MSBuildRoot {
    [CmdletBinding()]
    param(    )
    # Assume msbuild is installed with Visual Studio
    $VisualStudioRoot = Get-LatestVisualStudioRoot
    if ($VisualStudioRoot -and (Test-Path $VisualStudioRoot)) {
        $MSBuildRoot = Join-Path $VisualStudioRoot 'MSBuild'
    }

    # Assume msbuild is installed with Build Tools
    if (-not $MSBuildRoot -or -not (Test-Path $MSBuildRoot)) {
        $MSBuildRoot = Join-Path $BuildTools 'MSBuild'
    }

    # If not found before
    if (-not $MSBuildRoot -or -not (Test-Path $MSBuildRoot)) {
        # Assume msbuild is installed at default location
        $MSBuildRoot = Join-Path ${env:ProgramFiles(x86)} 'MSBuild'
    }

    $MSBuildRoot
}


function Get-MSBuildExe {
    [CmdletBinding()]
    param(
        [int]$MSBuildVersion,
        [switch]$TestOnly
    )
    if (-not $Script:MSBuildExe) {
        # Get the highest msbuild version if version was not specified
        if (-not $MSBuildVersion) {
            Get-MSBuildExe -MSBuildVersion $DefaultMSBuildVersion -TestOnly:$TestOnly
            return
        }

        $MSBuildRoot = Get-MSBuildRoot
        $MSBuildExe = Join-Path $MSBuildRoot 'Current\bin\msbuild.exe'

        if (-not (Test-Path $MSBuildExe)) {
            $MSBuildExe = Join-Path $MSBuildRoot "${MSBuildVersion}.0\bin\msbuild.exe"
        }

        if (Test-Path $MSBuildExe) {
            Add-VerboseLog -Message "Found MSBuild.exe at `"$MSBuildExe`"."
            $Script:MSBuildExe = $MSBuildExe
        } 
        elseif (-not $TestOnly) {
            Add-ErrorLog -Message ("Cannot find MSBuild.exe. Please download and install the Visual Studio Build Tools " +
                "from $VSBuildToolsUri.") -Fatal
        }
    }
}


function Test-MSBuildVersionPresent {
    [CmdletBinding()]
    param(
        [int]$MSBuildVersion = $DefaultMSBuildVersion
    )
    Get-MSBuildExe $MSBuildVersion -TestOnly

    $Script:MSBuildExe -and (Test-Path $Script:MSBuildExe)
}


function Restore-SolutionPackages {
    [CmdletBinding()]
    param(
        [Alias('path')]
        [string]$SolutionPath,
        [ValidateSet(15)]
        [int]$MSBuildVersion
    )
    $opts = , 'restore'
    if (-not $SolutionPath) {
        $opts += $Source
    }
    else {
        $opts += $SolutionPath
    }

    if ($MSBuildVersion) {
        $opts += '-MSBuildVersion', $MSBuildVersion
    }

    if (-not $VerbosePreference) {
        $opts += '-verbosity', 'quiet'
    }

    & $NuGetExe $opts
    if (-not $?) {
        Add-ErrorLog -Message "Restore failed @""$Root"". Code: ${LASTEXITCODE}."
    }
}


function Build-TestSolution {
    [CmdletBinding()]
    param()
    if (-not $Script:MSBuildExe) {
        Get-MSBuildExe
    }
    
    (& $Script:MSBuildExe /nologo $Solution /t:rebuild /p:Configuration=$BuildConfiguration`;Platform=$BuildPlatform) |
    Select-String -Pattern "Build succeeded|Build failed" -Context 0, 100 | Out-String | 
    ForEach-Object { $_.Trim().substring(2) } | Add-InfoLog
    
    if ($LASTEXITCODE) {
        Add-ErrorLog -Message "Build failed @""$Solution""." -Fatal
    }
}


function Build-ExcludedTestClassesString {
    [CmdletBinding()]
    param ()
    if (-not $Script:ConfigureHashTable) {
        Read-PISystemConfig -Force > $null
    }

    $noClassString = ""

    foreach ($key in $TestClassesForOptionalProductWithKeySetting.Keys) {
        if (-not $Script:ConfigureHashTable.ContainsKey($key) -or 
            [string]::IsNullOrEmpty($Script:ConfigureHashTable[$key])) {
            foreach ($testClass in $TestClassesForOptionalProductWithKeySetting[$key].split(',')) {
                $noClassString += '-noclass "{0}" ' -f ("OSIsoft.PISystemDeploymentTests.$testClass")        
            }
        }
    }
    
    foreach ($key in $TestClassesForOptionalProductWithBooleanFlag.Keys) {
        if ($Script:ConfigureHashTable.ContainsKey($key)) {
            $runTests = $null
            if (-not [bool]::TryParse($Script:ConfigureHashTable[$key], [ref]$runTests)) {
                Add-ErrorLog -Message "The setting value of ""$key"" in App.config is not boolean."
            }

            if (-not $runTests) {
                foreach ($testClass in $TestClassesForOptionalProductWithBooleanFlag[$key].split(',')) {
                    $noClassString += '-noclass "{0}" ' -f ("OSIsoft.PISystemDeploymentTests.$testClass")        
                }
            }
        }
    }

    $noClassString.Trim()
}

function Build-Tests {
    [CmdletBinding()]
    param ()
    # In order to build xUnit test solution, we need .NET Framework Developer Pack, NuGet.exe, and MSBuild
    Add-InfoLog -Message "Install .NET Framework Developer Pack if missing."
    Install-DotNETDevPack

    Add-InfoLog -Message "Install NuGet.exe if missing."
    Install-NuGet

    Add-InfoLog -Message "Install MSBuild if missing."
    Install-BuildTools

    Add-InfoLog -Message "Restore the NuGet packages of the test solution."
    Restore-SolutionPackages

    Add-InfoLog -Message "Build the test solution."
    Build-TestSolution
}

function Start-PrelimTesting {
    [CmdletBinding()]
    param ()
    Add-InfoLog -Message "Run Preliminary Checks."
    try {
        & $xUnitConsole $TestDll -class "OSIsoft.PISystemDeploymentTests.PreliminaryChecks" -html ""$PreCheckTestResultFile"" -verbose | 
        Tee-Object -Variable "preliminaryCheckResults"
        $preliminaryCheckResults | Write-ExecutionLog
        $errorTestCount = [int]($preliminaryCheckResults[-1] -replace ".*Errors: (\d+),.*", '$1')
        $failedTestCount = [int]($preliminaryCheckResults[-1] -replace ".*Failed: (\d+),.*", '$1')
    }
    catch {
        Add-ErrorLog -Message "Failed to run the PreliminaryChecks"
        Add-ErrorLog -Message ($_ | Out-String) -Fatal
	}

    if (($errorTestCount + $failedTestCount) -gt 0) {
        Add-ErrorLog -Message "Preliminary Checks failed, please troubleshoot the errors and try again." -Fatal
    }
}

function Start-Testing {
    [CmdletBinding()]
    param
    (
        [String]
        [Parameter(Mandatory = $false)]
        $TestName = '',
        $TestClassName = ''
    )
    if (-not (Test-Path $TestDll)) {
        Add-ErrorLog -Message "@""$TestDll"" is not available, please build the solution first." -Fatal
    }

    if ($TestName -ne '' -and $TestClassName -ne '') {
        Add-InfoLog -Message "Run product test '$TestName'."
        $fullCommand = "& $xUnitConsole $TestDll -method OSIsoft.PISystemDeploymentTests.$TestClassName.$TestName -verbose -parallel none"
    }
    elseif ($TestClassName -ne '') {
        Add-InfoLog -Message "Run product test class '$TestClassName'."
        $fullCommand = "& $xUnitConsole $TestDll -class OSIsoft.PISystemDeploymentTests.$TestClassName -verbose -parallel none"
    }
    else {
        $excludedTestClassesString = '-noclass "OSIsoft.PISystemDeploymentTests.PreliminaryChecks" ' + 
        (Build-ExcludedTestClassesString)
        Add-InfoLog -Message "Run product tests."
        $fullCommand = '& $xUnitConsole $TestDll --% ' + $excludedTestClassesString + 
        " -html ""$TestResultFile"" -verbose -parallel none"
    }

    Add-InfoLog -Message $fullCommand
    try {
        Invoke-Expression $fullCommand | Tee-Object -Variable "productTestResults"
        $productTestResults | Write-ExecutionLog
        $errorTestCount = [int]($productTestResults[-1] -replace ".*Errors: (\d+),.*", '$1')
        $failedTestCount = [int]($productTestResults[-1] -replace ".*Failed: (\d+),.*", '$1')
    }
    catch {
        Add-ErrorLog -Message "Failed to execute the full xUnit test run"
        Add-ErrorLog -Message ($_ | Out-String) -Fatal
	}

    if (($errorTestCount + $failedTestCount) -gt 0 -and $TestName -eq '' -and $TestClassName -eq '') {
        Add-ErrorLog -Message "xUnit test run finished with some failures, please troubleshoot the errors in $TestResultFile."
    }
    elseif (($errorTestCount + $failedTestCount) -eq 0 -and $TestName -eq '' -and $TestClassName -eq '') {
        Add-InfoLog -Message "xUnit test run finished, test results were saved in $TestResultFile."
    }
}


function Read-PISystemConfig {
    [CmdletBinding()]
    param (
        # Switch to skip confirmation
        [switch]$Force
    ) 
    Encrypt-PIWebAPICredentials
    $ConfigureSettings = Read-AppSettings
    Add-InfoLog ($ConfigureSettings | Out-String).TrimEnd()

    if (-not $Force) {
        Write-Host
        Add-InfoLog -Message ("Please double check the above PI System configuration loaded from $AppConfigFile," + 
            " update the file using a text editor if needed, press enter to continue...")
        Read-Host > $null
        Write-Host

        # Read the config again 
        Add-InfoLog -Message "Execution will continue with following settings."
        $ConfigureSettings = Read-AppSettings
        Add-InfoLog ($ConfigureSettings | Out-String).TrimEnd()
    }

    # Convert the setting array into properties, save the copy in a hashtable
    $ConfigureObject = New-Object PSObject
    $Script:ConfigureHashTable = @{ }
    $ConfigureSettings | ForEach-Object { 
        $AddMemberParams = @{
            InputObject       = $ConfigureObject
            NotePropertyName  = $_.Setting
            NotePropertyValue = $_.Value 
        }
        Add-Member @AddMemberParams

        $Script:ConfigureHashTable.Add($_.Setting, $_.Value)
    }
    
    foreach ($setting in $RequiredSettings) {
        if (-not $Script:ConfigureHashTable.ContainsKey($setting) -or 
            [string]::IsNullOrEmpty($Script:ConfigureHashTable[$setting])) {
            Add-ErrorLog -Message ("The required setting, $setting, is missing or has an empty value. " + 
                "Please fix it in App.config") -Fatal
        }
    }

    $ConfigureObject
}

function Encrypt-PIWebAPICredentials {
    [CmdletBinding()]
    param ()
    $Script:ConfigureData = @{ }
    ([xml](Get-Content $AppConfigFile)).Configuration.AppSettings.Add | 
    ForEach-Object { 
        $Script:ConfigureData.Add($_.key, $_.value)
    }

    $CredentialEncryptValue = $Script:ConfigureData["PIWebAPIEncryptionID"]
    if ((![string]::IsNullOrWhitespace($Script:ConfigureData["PIWebAPIUser"]) -and ![string]::IsNullOrWhitespace($Script:ConfigureData["PIWebAPIPassword"])) -and 
        [string]::IsNullOrWhitespace($CredentialEncryptValue)) {
            Add-Type -AssemblyName "System.Security"

            Write-Host
            Write-Host "Encrypting and writing to App.config..."

            $Entropy = New-Object byte[] 16
            $RNG = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
            $RNG.GetBytes($Entropy)

            $AppConfigXML = New-Object XML
            $AppConfigXML.Load($AppConfigFile)
            $ProtectionScope = [System.Security.Cryptography.DataProtectionScope]
            foreach ($Setting in $AppConfigXML.Configuration.AppSettings.Add) {
                if ($Setting.key -eq "PIWebAPIUser") {
                    $ToEncryptUser = [System.Text.Encoding]::ASCII.GetBytes($Setting.value)
                    $EncryptedUser = Encrypt-CredentialData $ToEncryptUser $Entropy $ProtectionScope::CurrentUser
                    $Setting.value = [System.BitConverter]::ToString($EncryptedUser)
				}

                if ($Setting.key -eq "PIWebAPIPassword") {
                    $ToEncryptPass = [System.Text.Encoding]::ASCII.GetBytes($Setting.value)
                    $EncryptedPass = Encrypt-CredentialData $ToEncryptPass $Entropy $ProtectionScope::CurrentUser
                    $Setting.value = [System.BitConverter]::ToString($EncryptedPass)
				}

                if ($Setting.key -eq "PIWebAPIEncryptionID") {
                    $Setting.value = [System.BitConverter]::ToString($Entropy)
				}
            }

            $AppConfigXML.Save($AppConfigFile)
    }
}

function Encrypt-CredentialData {
    [CmdletBinding()]
    param (
        [byte[]]$Buffer,
        [byte[]]$Entropy,
        [System.Security.Cryptography.DataProtectionScope]$Scope
    )

    # Encrypt the data and store the result in a new byte array. The original data remains unchanged.
    $EncryptedData = [System.Security.Cryptography.ProtectedData]::Protect($Buffer, $Entropy, $Scope);
    return $EncryptedData
}

function Read-AppSettings {
    [CmdletBinding()]
    param ()
    ([xml](Get-Content $AppConfigFile)).Configuration.AppSettings.Add | 
    Select-Object -property @{
        Name = 'Setting'; Expression = { $_.key } 
    }, 
    @{
        Name = 'Value'; Expression = { if ($_.key -match $HiddenSettingsRegex -and $_.value ) { "********" } else { $_.value } } 
    }
}


function Get-UserBooleanInput {
    [CmdletBinding()]
    param (
        # Message presented to the user
        [string]$Message = ""
    )
    
    $flag = 'n'
    do {
        Add-InfoLog -Message ($Message + " (Y/N)")
        $flag = (Read-Host | Tee-Object -FilePath $ExecutionLog -Append).ToLower()
    } until ('y', 'n' -contains $flag)

    if ($flag -eq 'y') {
        $true
    }
    else {
        $false
    }
}


# load OSIsoft.AFSDK.dll for the following PI/AF related functions
Add-Type -AssemblyName 'OSIsoft.AFSDK, Version=4.0.0.0, Culture=neutral, PublicKeyToken=6238be57836698e6' > $null


function Set-TargetDatabase {
    [CmdletBinding()]
    param(
        # AF Server object
        [Parameter(Mandatory = $true)]
        [OSIsoft.AF.PISystem]$PISystem,

        # Name of AF Database
        [Parameter(Mandatory = $true)]
        [string]$Database,

        # PI Data Archive ClientChannel
        [Parameter(Mandatory = $true)]
        [OSIsoft.PI.Net.ClientChannel]$PIDA,

        # Switch to force rebuilding database, it will override the Reset switch if both are specified
        [switch]$Force
    )   
    $db = $PISystem.Databases[$Database]
    $buildDatabase = $true

    if ($db) {
        if (-not $Force) {
            $buildDatabase = Get-UserBooleanInput("Found existing AF database, $($db.GetPath())." + 
                [Environment]::NewLine +
                "Do you want to remove this database and build one from scratch?")
        }

        if ($buildDatabase) {
            try {
                $RemoveTargetDatabaseParams = @{
                    PISystem = $PISystem
                    Database = $Database
                    PIDA     = $PIDA
                    Force    = $true
                }
                Remove-TargetDatabase @RemoveTargetDatabaseParams
            }
            catch {
                Add-ErrorLog -Message ($_ | Out-String) -Fatal
            } 
        }
        else {
            Add-InfoLog -Message "Execution will continue with the current AF database."
        }
    }

    if ($buildDatabase) {
        try {
            Add-InfoLog -Message "Start building the target PI AF database."
            
            Add-InfoLog -Message "Start xml importing."
            $PISystem.ImportXml($null, 1041, $WindFarmxml) > $null

			$db = $PISystem.Databases[$Database]
            $elementSearch = New-Object OSIsoft.AF.Search.AFElementSearch $db, "AllElements", ""
            # Pause for the xml importing to finish, otherwise CreateConfig may throw errors.
            $attempt = 0
            $elementCount = $elementSearch.GetTotalCount()
            do {
                Start-Sleep -Seconds $WaitIntervalInSeconds

                if (($elementSearch.GetTotalCount() -eq $elementCount) -and -not $db.IsDirty) {
                    break
                }
                else {
                    $elementCount = $elementSearch.GetTotalCount()
                }

                if ((++$attempt % $RetryCountBeforeReporting) -eq 0) {
                    Add-InfoLog -Message "Waiting on xml importing to finish..."
                }
            }while ($attempt -lt $MaxRetry)

            if ($attempt -eq $MaxRetry) {
                Add-WarningLog -Message ("The step of importing a xml file to $($db.GetPath()) " + 
                    "did not finish after $($WaitIntervalInSeconds * $MaxRetry) seconds.")
            }
            else {
                Add-InfoLog -Message "Finished xml importing."
            }
            
            $PIDAAttribute = $db.Elements["PI Data Archive"].Attributes["Name"]
            Set-AFAttribute -AFAttribute $PIDAAttribute -Value $PIDA.CurrentRole.Name -ErrorAction Stop
        }
        catch {
            Add-ErrorLog -Message ($_ | Out-String) -Fatal                
        }

        $createConfigSecondTry = $false
        [System.EventHandler[OSIsoft.AF.AFProgressEventArgs]]$hndl = {
            if (($_.Status -eq [OSIsoft.AF.AFProgressStatus]::HasError) -or
                ($_.Status -eq [OSIsoft.AF.AFProgressStatus]::CompleteWithErrors)) {
                $_.Cancel = $true

                if ($createConfigSecondTry) {
                    Add-ErrorLog -Message ("Encountered errors when trying to create or update PI Point data reference in " + 
                        "$($db.GetPath()). $PSEErrorHandlingMsg") -Fatal
                }
            }
        }

        Add-InfoLog -Message "Start PI point creation."
        try {
            [OSIsoft.AF.Asset.AFDataReference]::CreateConfig($db, $hndl) > $null
        }
        catch {
            Start-Sleep -Seconds $WaitIntervalInSeconds
            Add-WarningLog -Message ("The first try of creating or updating PI Point data reference failed, try again.")
            $createConfigSecondTry = $true
            $db.UndoCheckOut($false);
            [OSIsoft.AF.Asset.AFDataReference]::CreateConfig($db, $hndl) > $null
        }
        Add-InfoLog -Message "Finished PI point creation."
		
        # Retrieve recalculation end time as the time when we start all analyses
        $recalculationEndTime = (ConvertFrom-AFRelativeTime -RelativeTime "*").ToString('u')

        # Enable all analyses
        Add-InfoLog -Message "Enabling all analyses of the AF database."
        $db.Analyses | ForEach-Object { $_.SetStatus([OSIsoft.AF.Analysis.AFStatus]::Enabled) }

        # Wait for all analyses to be in running state
        $attempt = 0
        $resetAnalysisCount = 10
        do {
            Start-Sleep -Seconds $WaitIntervalInSeconds

            $path = "Path:= '\\\\$($PISystem.Name)\\$($Database)\\*"
            $analysesStatus = $PISystem.AnalysisService.QueryRuntimeInformation($path, 'status id')

            # Potentially QueryRuntimeInformation returns analyses which have been deleted in AF 
            # but not fully cleaned up from PI Analysis Service.
            $inactiveAnalysesCount = $analysesStatus.Count - $db.Analyses.Count
            if ($analysesStatus.Count -gt 0) {
                $NotRunningAnalyses = $analysesStatus.Where( { $_[0].ToString() -notlike "Running" })
                if ($NotRunningAnalyses.Count -le $inactiveAnalysesCount) {
                    break
                }
            }

            # Periodically output a status message and try to reset error analyses
            if ((++$attempt % $RetryCountBeforeReporting) -eq 0) {
                Add-InfoLog -Message "Waiting on analyses to be enabled..."

                # Reset a number of analyses in error in order to expedite the process
                $analysesInError = $NotRunningAnalyses | Where-Object { 
                    $db.Analyses.Contains([System.guid]::New($_[1]))
                } | Select-Object -First $resetAnalysisCount | ForEach-Object { $db.Analyses[[System.guid]::New($_[1])] }
                $analysesInError | ForEach-Object { $_.SetStatus([OSIsoft.AF.Analysis.AFStatus]::Disabled) }
                $analysesInError | ForEach-Object { $_.SetStatus([OSIsoft.AF.Analysis.AFStatus]::Enabled) }
            }
        } while ($attempt -lt $MaxRetry) 

        if ($attempt -eq $MaxRetry) {
            Add-ErrorLog -Message ("Waiting on analyses to be enabled did not finish within " + 
                "$($WaitIntervalInSeconds * $MaxRetry) seconds. Please check the analysis status in" + 
                " PI System Explorer and troubleshoot any issues with PI Analysis Service.") -Fatal
        }

        Add-InfoLog -Message "Enabled all analyses of the AF database."
        Add-InfoLog -Message "Successfully added a new AF database, $($db.GetPath())."
    }

    # Build a new PI archive file if the existing archives do not cover the expected archive start time.
    # We assume there is no archive gap in PI Data Archive server.
    # Create an archive file covering additional 10 days so that tests have more flexibility in choosing event timestamp.
    $archiveStartTime = ConvertFrom-AFRelativeTime -RelativeTime "$DefaultPIDataStartTime-10d"
    $oldestArchive = (Get-PIArchiveFileInfo -Connection $PIDA -ErrorAction Stop | Sort-Object -Property StartTime)[0]

    if ($oldestArchive.StartTime -gt $archiveStartTime) {
        Add-InfoLog -Message "Adding a new archive file covering $archiveStartTime."

        $archiveName = $PIDA.CurrentRole.Name + '_' + $archiveStartTime.ToString("yyyy-MM-dd_HH-mm-ssZ") + ".arc"
        $NewPIArchiveParams = @{
            Name                = $archiveName
            StartTime           = $archiveStartTime
            EndTime             = $oldestArchive.StartTime
            Connection          = $PIDA
            UsePrimaryPath      = [switch]::Present
            WaitForRegistration = [switch]::Present
        }

        try {
            New-PIArchive @NewPIArchiveParams -ErrorAction Stop
        }
        catch {
            Add-ErrorLog -Message ($_ | Out-String) -Fatal                
        }

        if ( -not ((Get-PIArchiveInfo -Connection $PIDA).ArchiveFileInfo |
                Select-Object Path |
                Where-Object Path -Match $archiveName)) {
            Add-ErrorLog -Message "Creating the new archive failed." -Fatal
        }
    }
    
    # Run analysis recalculation if the existing PI data does not cover the minimal archive start time.
    $minimalArchivedDataStartTime = ConvertFrom-AFRelativeTime -RelativeTime $DefaultPIDataStartTime
    $val = Get-PIValue -PointName $SamplePIPoint -Time $minimalArchivedDataStartTime -Connection $PIDA
    if (-not $val.IsGood) {
        # Queue the recalculation on all analog analyses. 
        Add-InfoLog -Message "Start analysis recalculation, this may take a few minutes."
        $StartPIANRecalculationParams = @{
            Database = $db
            Query    = "TemplateName:'Demo Data - Analog*'"
            Start    = $minimalArchivedDataStartTime.ToString('u') 
            End      = $recalculationEndTime
        }
        Start-PIANRecalculation @StartPIANRecalculationParams 

        # Wait for the recalculation to finish
        $attempt = 0
        $recalcNotDone = $false
        $pointList = Get-PIPoint -Connection $PIDA -WhereClause pointsource:=$TestsPIPointSource |
        Where-Object { $_.Point.Name -match $CoveredByRecalcPIPointRegex }
        do {
            Start-Sleep -Seconds $WaitIntervalInSeconds

            $recalcNotDone = $false
            ForEach ($point in $pointList) {
                # Get the point value at 1 hour after the start time because some analyses are scheduled to run hourly.
                $pointValue = Get-PIValue -PIPoint $point -Time (
                    ConvertFrom-AFRelativeTime -RelativeTime "$DefaultPIDataStartTime+1h")

                # If a point value remains "No Data" (State: 248(Set: 0)), recalculation has not done yet.
                if (($pointValue.Value.StateSet -eq 0) -and ($pointValue.Value.State -eq 248)) {
                    $recalcNotDone = $true
                    break
                }
            }
            
            if ((++$attempt % $RetryCountBeforeReporting) -eq 0) {
                Add-InfoLog -Message "Waiting on analyses recalculation to finish..."
            }
        } while (($attempt -lt $MaxRetry) -and $recalcNotDone)

        if ($recalcNotDone) {
            Add-ErrorLog -Message ("Waiting on analysis recalculation did not finish within " +
                "$($WaitIntervalInSeconds * $attempt) seconds.  Please check the recalculation status in" + 
                " PI System Explorer and troubleshoot any issues with PI Analysis Service.") -Fatal
        }
        else {
            Add-InfoLog -Message "Finished analysis recalculation."
        }
    }   
}


function Start-PIANRecalculation {
    [CmdletBinding()]
    param(
        # Name of AF Database
        [Parameter(Mandatory = $true)]
        [OSIsoft.AF.AFDatabase]$Database,

        # Query string to search for target analyses to recalculate
        [string]$Query = "",

        # Start time of recalculation
        [string]$Start = $DefaultPIDataStartTime,

        # End time of recalculation
        [string]$End = "*",

        # Recalculation Mode
        [ValidateSet('DeleteExistingData', 'FillDataGaps')]
        [string]$Option = 'DeleteExistingData'
    )
    # Build an AFAnalysisSerach object to find all matching analyses
    $analysisSearch = New-Object OSIsoft.AF.Search.AFAnalysisSearch $Database, "", $Query

    # Get the total count of analyses that could be returned from the search query
    $count = $analysisSearch.GetTotalCount()

    if ($count -gt 0) {
        # Find all analyses that match the query string
        $analyses = $analysisSearch.FindAnalyses()

        $timeRange = New-Object OSIsoft.AF.Time.AFTimeRange $Start, $End
        Add-InfoLog -Message ("Queue $count analyses for recalculation from $($timeRange.StartTime) to $($timeRange.EndTime) " + 
            "in order to backfill data.")

        try {
            $Database.PISystem.AnalysisService.QueueCalculation($analyses, $timeRange, $Option) > $null
        }
        catch {
            Add-ErrorLog -Message ("Cannot connect to the PI Analysis Service on $($Database.PISystem.AnalysisService.Host). " +
                "Please make sure the service is running and Port $PIAnalysisServicePort is open.") -Fatal
        }
    } 
    else {
        Add-InfoLog -Message "No analyses found matching '$Query' in $Database."
    }
}


function Remove-TargetDatabase {
    [CmdletBinding()]
    param(
        # AF Server object
        [Parameter(Mandatory = $true)]
        [OSIsoft.AF.PISystem]$PISystem,

        # Name of AF Database
        [Parameter(Mandatory = $true)]
        [string]$Database,

        # PI Data Archive ClientChannel
        [Parameter(Mandatory = $true)]
        [OSIsoft.PI.Net.ClientChannel]$PIDA,

        # Switch to force cleanup
        [switch]$Force
    )
    $cleanupFlag = $true
    if (-not $Force) {
        $cleanupFlag = Get-UserBooleanInput -Message ("Execution will remove the target AF database, $Database, " + 
            "and all associated PI points, please confirm.")
    }

    if ($cleanupFlag) {
        try {
            $db = $PISystem.Databases[$Database]
            if ($db) {
                $db.Analyses | ForEach-Object { $_.SetStatus([OSIsoft.AF.Analysis.AFStatus]::Disabled) }
                $PISystem.AnalysisService.Refresh()
                Add-InfoLog -Message "Deleting the AF database, $($db.GetPath())."
                Remove-AFDatabase -Name $Database -AFServer $PISystem -ErrorAction Stop > $null
                Add-InfoLog -Message "Deleted the AF database."
            }
            else {
                Add-WarningLog -Message "Cannot find the AF database, $Database, on $PISystem."
            }

            # Delete all PI points with the test point source
            $pipoints = Get-PIPoint -WhereClause "pointsource:=$TestsPIPointSource" -Connection $PIDA
            if ($pipoints.Count -gt 0) {
                Add-InfoLog -Message "Deleting PI points with the pointsource of $TestsPIPointSource."
                $pipoints | ForEach-Object { Remove-PIPoint -Name $_.Point.Name -Connection $PIDA -ErrorAction Stop } 
                Add-InfoLog -Message "Deleted $($pipoints.Count) PI points."
            }
        }
        catch {
            Add-ErrorLog -Message ($_ | Out-String) -Fatal
        } 

        # Uninstall Visual Studio Build Tools
        if (Test-Path $VSBuildTools) {
            $p = Start-Process $VSBuildTools -ArgumentList "uninstall --installPath $BuildTools -q" -PassThru -Wait
            if ($p.ExitCode -ne 0) {
                Add-ErrorLog -Message ("Failed to uninstall Visual Studio Build Tools." + 
                    "Please run ""$VSBuildTools"" interactively and troubleshoot any issues.") -Fatal
            }
        }

        # Uninstall .NET Developer Pack
        if (Test-Path $DotNETDevPack) {
            $p = Start-Process $DotNETDevPack -ArgumentList "/uninstall /quiet /norestart" -PassThru -Wait
            if ($p.ExitCode -ne 0 -or (Test-Path $DotNETFrameworkDir)) {
                Add-ErrorLog -Message ("Failed to uninstall .NET Developer Pack." + 
                    "Please run ""$DotNETDevPack"" interactively and troubleshoot any issues.") -Fatal
            }
        }
    }
}
# SIG # Begin signature block
# MIIcLAYJKoZIhvcNAQcCoIIcHTCCHBkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBnpWsir8/+aUn4
# rwdZQ1lMLQMPLpYfTVUn4XFf2hN7/aCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
# ZnVTQ7VvlVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBa
# Fw0yODEwMjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lD
# ZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/l
# qJ3bMtdx6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fT
# eyOU5JEjlpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqH
# CN8M9eJNYBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+
# bMt+dDk2DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLo
# LFH3c7y9hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIB
# yTASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAK
# BggrBgEFBQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHow
# eDA6oDigNoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJl
# ZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwA
# AgQwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAK
# BghghkgBhv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0j
# BBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7s
# DVoks/Mi0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGS
# dQ9RtG6ljlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6
# r7VRwo0kriTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo
# +MUSaJ/PQMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qz
# sIzV6Q3d9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHq
# aGxEMrJmoecYpJpkUe8wggVWMIIEPqADAgECAhAFTTVZN0yftPMcszD508Q/MA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcNMTkwNjE3MDAwMDAw
# WhcNMjAwNzAxMTIwMDAwWjCBkjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRQw
# EgYDVQQHEwtTYW4gTGVhbmRybzEVMBMGA1UEChMMT1NJc29mdCwgTExDMQwwCgYD
# VQQLEwNEZXYxFTATBgNVBAMTDE9TSXNvZnQsIExMQzEkMCIGCSqGSIb3DQEJARYV
# c21hbmFnZXJzQG9zaXNvZnQuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
# CgKCAQEAqbP+VTz8qtsq4SWhF7LsXqeDGyUwtDpf0vlSg+aQh2fOqJhW2uiPa1GO
# M5+xbr+RhTTWzJX2vEwqSIzN43ktTdgcVT9Bf5W2md+RCYE1D17jGlj5sCFTS4eX
# Htm+lFoQF0donavbA+7+ggd577FdgOnjuYxEpZe2lbUyWcKOHrLQr6Mk/bKjcYSY
# B/ipNK4hvXKTLEsN7k5kyzRkq77PaqbVAQRgnQiv/Lav5xWXuOn7M94TNX4+1Mk8
# 74nuny62KLcMRtjPCc2aWBpHmhD3wPcUVvTW+lGwEaT0DrCwcZDuG/Igkhqj/8Rf
# HYfnZQtWMnBFAHcuA4jJgmZ7xYMPoQIDAQABo4IBxTCCAcEwHwYDVR0jBBgwFoAU
# WsS5eyoKo6XqcQPAYPkt9mV1DlgwHQYDVR0OBBYEFNcTKM3o/Fjj9J3iOakcmKx6
# CPetMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB3BgNVHR8E
# cDBuMDWgM6Axhi9odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVk
# LWNzLWcxLmNybDA1oDOgMYYvaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL3NoYTIt
# YXNzdXJlZC1jcy1nMS5jcmwwTAYDVR0gBEUwQzA3BglghkgBhv1sAwEwKjAoBggr
# BgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAIBgZngQwBBAEw
# gYQGCCsGAQUFBwEBBHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tME4GCCsGAQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRTSEEyQXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/
# BAIwADANBgkqhkiG9w0BAQsFAAOCAQEAigLIcsGUWzXlZuVQY8s1UOxYgch5qO1Y
# YEDFF8abzJQ4RiB8rcdoRWjsfpWxtGOS0wkA2CfyuWhjO/XqgmYJ8AUHIKKCy6QE
# 31/I6izI6iDCg8X5lSR6nKsB2BCZCOnGJOEi3r+WDS18PMuW24kaBo1ezx6KQOx4
# N0qSrMJqJRXfPHpl3WpcLs3VA1Gew9ATOQ9IXbt8QCvyMICRJxq4heHXPLE3EpK8
# 2wlBKwX3P4phapmEUOWxB45QOcRJqgahe9qIALbLS+i5lxV+eX/87YuEiyDtGfH+
# dAbq5BqlYz1Fr8UrWeR3KIONPNtkm2IFHNMdpsgmKwC/Xh3nC3b27DGCEPQwghDw
# AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIg
# QXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAVNNVk3TJ+08xyzMPnTxD8wDQYJ
# YIZIAWUDBAIBBQCggf8wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPeyko3ViB1h
# UnLZ+R1TPNDOkwP2mYdgwbz9tck6Nl+fMIGSBgorBgEEAYI3AgEMMYGDMIGAoFyA
# WgBQAEkAIABTAHkAcwB0AGUAbQAgAEQAZQBwAGwAbwB5AG0AZQBuAHQAIABUAGUA
# cwB0AHMAIABQAG8AdwBlAHIAUwBoAGUAbABsACAAUwBjAHIAaQBwAHQAc6EggB5o
# dHRwOi8vdGVjaHN1cHBvcnQub3Npc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# anGHJk055vyQuFMHJ0Dfb+Lh+bWEnCTdjU6iizH6mX8tj/Bb05CTPIo+++rX51Lj
# vXgnHQ9rAvYxy88BcCXa+IPL8XU3R5339oQtBgDU/t/ptTuGQB/P8kiL3xuP75nz
# hT6y8ZMsMZ5rXT9L9KiIL74G0OE6/8N1aBrAQtXlonBbNEh8diJCVoxHVEaEcVyV
# RbfB9v5MTgKYqThcfB2X2eEkpNuCSQ4YG9qYPNJDWvC6YH2bfNrRBawQUcx6z4qU
# FINc4aFhRDQd9T81C8WqqUCCm1h/jTGyuri8ByTdsc9ThvusaJYx+fIv57/tZsmf
# Y0fy+LQBMTeDUEq0zvZttaGCDjwwgg44BgorBgEEAYI3AwMBMYIOKDCCDiQGCSqG
# SIb3DQEHAqCCDhUwgg4RAgEDMQ0wCwYJYIZIAWUDBAIBMIIBDgYLKoZIhvcNAQkQ
# AQSggf4EgfswgfgCAQEGC2CGSAGG+EUBBxcDMDEwDQYJYIZIAWUDBAIBBQAEIFQ4
# oj+ran6j6Se6dPbJOCmHPqYYG7UBcEnhOLfsFnCkAhRZ/htrY3AMxs7e3NAI3ZDo
# kJFh1hgPMjAyMDA0MDMxODU2MzZaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
# MR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50
# ZWMgVHJ1c3QgTmV0d29yazExMC8GA1UEAxMoU3ltYW50ZWMgU0hBMjU2IFRpbWVT
# dGFtcGluZyBTaWduZXIgLSBHM6CCCoswggU4MIIEIKADAgECAhB7BbHUSWhRRPfJ
# idKcGZ0SMA0GCSqGSIb3DQEBCwUAMIG9MQswCQYDVQQGEwJVUzEXMBUGA1UEChMO
# VmVyaVNpZ24sIEluYy4xHzAdBgNVBAsTFlZlcmlTaWduIFRydXN0IE5ldHdvcmsx
# OjA4BgNVBAsTMShjKSAyMDA4IFZlcmlTaWduLCBJbmMuIC0gRm9yIGF1dGhvcml6
# ZWQgdXNlIG9ubHkxODA2BgNVBAMTL1ZlcmlTaWduIFVuaXZlcnNhbCBSb290IENl
# cnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTE2MDExMjAwMDAwMFoXDTMxMDExMTIz
# NTk1OVowdzELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0
# aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVzdCBOZXR3b3JrMSgwJgYDVQQDEx9T
# eW1hbnRlYyBTSEEyNTYgVGltZVN0YW1waW5nIENBMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAu1mdWVVPnYxyXRqBoutV87ABrTxxrDKPBWuGmicAMpdq
# TclkFEspu8LZKbku7GOz4c8/C1aQ+GIbfuumB+Lef15tQDjUkQbnQXx5HMvLrRu/
# 2JWR8/DubPitljkuf8EnuHg5xYSl7e2vh47Ojcdt6tKYtTofHjmdw/SaqPSE4cTR
# fHHGBim0P+SDDSbDewg+TfkKtzNJ/8o71PWym0vhiJka9cDpMxTW38eA25Hu/ryS
# V3J39M2ozP4J9ZM3vpWIasXc9LFL1M7oCZFftYR5NYp4rBkyjyPBMkEbWQ6pPrHM
# +dYr77fY5NUdbRE6kvaTyZzjSO67Uw7UNpeGeMWhNwIDAQABo4IBdzCCAXMwDgYD
# VR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYBAf8CAQAwZgYDVR0gBF8wXTBbBgtg
# hkgBhvhFAQcXAzBMMCMGCCsGAQUFBwIBFhdodHRwczovL2Quc3ltY2IuY29tL2Nw
# czAlBggrBgEFBQcCAjAZGhdodHRwczovL2Quc3ltY2IuY29tL3JwYTAuBggrBgEF
# BQcBAQQiMCAwHgYIKwYBBQUHMAGGEmh0dHA6Ly9zLnN5bWNkLmNvbTA2BgNVHR8E
# LzAtMCugKaAnhiVodHRwOi8vcy5zeW1jYi5jb20vdW5pdmVyc2FsLXJvb3QuY3Js
# MBMGA1UdJQQMMAoGCCsGAQUFBwMIMCgGA1UdEQQhMB+kHTAbMRkwFwYDVQQDExBU
# aW1lU3RhbXAtMjA0OC0zMB0GA1UdDgQWBBSvY9bKo06FcuCnvEHzKaI4f4B1YjAf
# BgNVHSMEGDAWgBS2d/ppSEefUxLVwuoHMnYH0ZcHGTANBgkqhkiG9w0BAQsFAAOC
# AQEAdeqwLdU0GVwyRf4O4dRPpnjBb9fq3dxP86HIgYj3p48V5kApreZd9KLZVmSE
# cTAq3R5hF2YgVgaYGY1dcfL4l7wJ/RyRR8ni6I0D+8yQL9YKbE4z7Na0k8hMkGNI
# OUAhxN3WbomYPLWYl+ipBrcJyY9TV0GQL+EeTU7cyhB4bEJu8LbF+GFcUvVO9muN
# 90p6vvPN/QPX2fYDqA/jU/cKdezGdS6qZoUEmbf4Blfhxg726K/a7JsYH6q54zoA
# v86KlMsB257HOLsPUqvR45QDYApNoP4nbRQy/D+XQOG/mYnb5DkUvdrk08PqK1qz
# lVhVBH3HmuwjA42FKtL/rqlhgTCCBUswggQzoAMCAQICEHvU5a+6zAc/oQEjBCJB
# TRIwDQYJKoZIhvcNAQELBQAwdzELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFu
# dGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVzdCBOZXR3b3Jr
# MSgwJgYDVQQDEx9TeW1hbnRlYyBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTE3
# MTIyMzAwMDAwMFoXDTI5MDMyMjIzNTk1OVowgYAxCzAJBgNVBAYTAlVTMR0wGwYD
# VQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1
# c3QgTmV0d29yazExMC8GA1UEAxMoU3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGlu
# ZyBTaWduZXIgLSBHMzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAK8O
# iqr43L9pe1QXcUcJvY08gfh0FXdnkJz93k4Cnkt29uU2PmXVJCBtMPndHYPpPydK
# M05tForkjUCNIqq+pwsb0ge2PLUaJCj4G3JRPcgJiCYIOvn6QyN1R3AMs19bjwgd
# ckhXZU2vAjxA9/TdMjiTP+UspvNZI8uA3hNN+RDJqgoYbFVhV9HxAizEtavybCPS
# nw0PGWythWJp/U6FwYpSMatb2Ml0UuNXbCK/VX9vygarP0q3InZl7Ow28paVgSYs
# /buYqgE4068lQJsJU/ApV4VYXuqFSEEhh+XetNMmsntAU1h5jlIxBk2UA0XEzjwD
# 7LcA8joixbRv5e+wipsCAwEAAaOCAccwggHDMAwGA1UdEwEB/wQCMAAwZgYDVR0g
# BF8wXTBbBgtghkgBhvhFAQcXAzBMMCMGCCsGAQUFBwIBFhdodHRwczovL2Quc3lt
# Y2IuY29tL2NwczAlBggrBgEFBQcCAjAZGhdodHRwczovL2Quc3ltY2IuY29tL3Jw
# YTBABgNVHR8EOTA3MDWgM6Axhi9odHRwOi8vdHMtY3JsLndzLnN5bWFudGVjLmNv
# bS9zaGEyNTYtdHNzLWNhLmNybDAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCB4AwdwYIKwYBBQUHAQEEazBpMCoGCCsGAQUFBzABhh5odHRwOi8v
# dHMtb2NzcC53cy5zeW1hbnRlYy5jb20wOwYIKwYBBQUHMAKGL2h0dHA6Ly90cy1h
# aWEud3Muc3ltYW50ZWMuY29tL3NoYTI1Ni10c3MtY2EuY2VyMCgGA1UdEQQhMB+k
# HTAbMRkwFwYDVQQDExBUaW1lU3RhbXAtMjA0OC02MB0GA1UdDgQWBBSlEwGpn4XM
# G24WHl87Map5NgB7HTAfBgNVHSMEGDAWgBSvY9bKo06FcuCnvEHzKaI4f4B1YjAN
# BgkqhkiG9w0BAQsFAAOCAQEARp6v8LiiX6KZSM+oJ0shzbK5pnJwYy/jVSl7OUZO
# 535lBliLvFeKkg0I2BC6NiT6Cnv7O9Niv0qUFeaC24pUbf8o/mfPcT/mMwnZolkQ
# 9B5K/mXM3tRr41IpdQBKK6XMy5voqU33tBdZkkHDtz+G5vbAf0Q8RlwXWuOkO9Vp
# JtUhfeGAZ35irLdOLhWa5Zwjr1sR6nGpQfkNeTipoQ3PtLHaPpp6xyLFdM3fRwmG
# xPyRJbIblumFCOjd6nRgbmClVnoNyERY3Ob5SBSe5b/eAL13sZgUchQk38cRLB8A
# P8NLFMZnHMweBqOQX1xUiz7jM1uCD8W3hgJOcZ/pZkU/djGCAlowggJWAgEBMIGL
# MHcxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEf
# MB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazEoMCYGA1UEAxMfU3ltYW50
# ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQe9Tlr7rMBz+hASMEIkFNEjALBglg
# hkgBZQMEAgGggaQwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3
# DQEJBTEPFw0yMDA0MDMxODU2MzZaMC8GCSqGSIb3DQEJBDEiBCAwugwoTL4xBsHH
# aJGwSdu6pztVmVoapakx0oz4KtAaFjA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# Bm/5TabGO0Ow5O9ABnXbkFGWguHyuR0C6LpwdxJnvtJQjJJRxhP8Kqk6iFiTUA8/
# 1jNdwcyEwFYnQ2nGP1iy3O49oQFf5BqYBrbOeKVXFYYv1eUH4zezxxf15bF6DVzG
# 3M+sQeQXlWSCkMaq8wfHcE/5i0DtmcUof8WJaBPrElVO+4m/fAIMlF3dWkR46CzQ
# KdU0gypfJJqakUo6rQFiItLuO+z5lPpfxQHyuFRvk80xthWkquQ8zYas/Tuwkv7h
# 53ej4YZoykXmGPk0bs5bDrQEQfzMEg87eJAwFplMsDENlN4CViHVV+um9LYMzdoh
# E8gxL41WeYj5U+vPRX5qHA==
# SIG # End signature block
