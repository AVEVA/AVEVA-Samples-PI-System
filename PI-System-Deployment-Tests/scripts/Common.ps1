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

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

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
# MIIcuAYJKoZIhvcNAQcCoIIcqTCCHKUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAyJpao8Vr0ip64
# Ot1vvNH5sPzFmNWVKWz/aGhFom5Gf6CCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# aGxEMrJmoecYpJpkUe8wggVVMIIEPaADAgECAhAGVvq6kseGimsYGJGsdvpbMA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcNMjAwNjE2MDAwMDAw
# WhcNMjIwNzIyMTIwMDAwWjCBkTELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRQw
# EgYDVQQHEwtTYW4gTGVhbmRybzEVMBMGA1UEChMMT1NJc29mdCwgTExDMQwwCgYD
# VQQLEwNEZXYxFTATBgNVBAMTDE9TSXNvZnQsIExMQzEjMCEGCSqGSIb3DQEJARYU
# cGRlcmVnaWxAb3Npc29mdC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQDPSOGDHDmQTrdWSTB6jfvZ3+ngv2HwU/64ZUGKq+PbyQKcqeRI5MT2Fokj
# K9yp6JoVnipZaBZdjLRj//FuqDR/pNy3VZo1xmufKICqrSS6x2AxKb9l/6mcO/MF
# E2FgG0tND/xftCQlChB91GokCyiVNkwbLleB9uM6yn73ZZkiA0Chmjguipfal+hS
# 27vds5xYGLtcnqWcKcZR5pr838vDT+8zzrxoWQ8se3H9LHYLyCiwk+84mA1M//BW
# xaA7ERt1eJ3vLzYu3+ryH+GFiYEhJHu3FZjktEg5oZ25Vj7iwgTG+/CIMZsEDe5G
# SFvePn3jpMmEaPbOPfx8FVwh8XItAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRa
# xLl7KgqjpepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQUmzSViihexjjLsHHW6j+r7Fxw
# U/gwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRw
# MG4wNaAzoDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQt
# Y3MtZzEuY3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1h
# c3N1cmVkLWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsG
# AQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCB
# hAYIKwYBBQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2Vy
# dC5jb20wTgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8E
# AjAAMA0GCSqGSIb3DQEBCwUAA4IBAQAR/2LHTPvx/fBATBS0jBBhPEhlrpNgkWZ9
# NCo0wJC5H2V2CpokuZxA4HoK0YCsz2x68BpCnBOX3pdSWC+kQOvLyJayTQew+c/R
# sebGEVp9NNtsnpcFhjM3e7hqsQAm6rCIJWk0Q1sSyYnhnqHA/iS1DxNqZ/qZHx1k
# ise1+9bOefqB1YN+vtmPBlLkboKCklbrJmHSEn4cZNBHjq1yVYOPacuws+8kAEMh
# lDjG2NkfyqF72Jo90SFK7xgjE6euLbvmjGYRSF9h4V+aR6MaEcDkUe2aoCgCmnDX
# Q+9sIKX0AojqBVLFUNQpzelOdjGWNzdcMMSu8p0pNw4xeAbuCEHfMYIRgTCCEX0C
# AQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBB
# c3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQBlb6upLHhoprGBiRrHb6WzANBglg
# hkgBZQMEAgEFAKCB/zAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgaUVtstoAJA4y
# Po7mdFRAue/H+DKG7O5u56WApvYxRWowgZIGCisGAQQBgjcCAQwxgYMwgYCgXIBa
# AFAASQAgAFMAeQBzAHQAZQBtACAARABlAHAAbABvAHkAbQBlAG4AdAAgAFQAZQBz
# AHQAcwAgAFAAbwB3AGUAcgBTAGgAZQBsAGwAIABTAGMAcgBpAHAAdABzoSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQAv
# 7cUyZfrFNiTyIFb5l0GLM0DSdoAioVfhvzl21UQwtaCiU0hCpQ9DuoWV5bFcIS9n
# W5QeHJx9hosoUXN/IG6qWB2D214ZlglFUukKIz8kj7AERX5WiBzT4Be69WUuyPSU
# poi4St5eLdYxRHZvhc0pavxkGZB6qfOT0ZGNlCcHFc94VtwdQMiuCeg5mcO7bBzv
# 6iiQsEk2MP5qS/fb4sfYPbd0dKqtbjvS4Dj3rYmgh5Yuc4JirdKP/hMZA27xwL/C
# rtMXGiLwhezd9SONO7lkjc22UViJRNcWWwZ33j931+awl5UkOTht6fqigtLySveo
# sSg/r23sOLqfb6CMChAQoYIOyTCCDsUGCisGAQQBgjcDAwExgg61MIIOsQYJKoZI
# hvcNAQcCoIIOojCCDp4CAQMxDzANBglghkgBZQMEAgEFADB4BgsqhkiG9w0BCRAB
# BKBpBGcwZQIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAEINHKIKSTp47D
# ReauyhuHCZduU7kFCMwh2L1/tVs1qmsqAhEA32gesjGmsVTW0lnSHsVICRgPMjAy
# MDExMjExNDAxNTlaoIILuzCCBoIwggVqoAMCAQICEATNP4VornbGG7D+cWDMp20w
# DQYJKoZIhvcNAQELBQAwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0
# IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNl
# cnQgU0hBMiBBc3N1cmVkIElEIFRpbWVzdGFtcGluZyBDQTAeFw0xOTEwMDEwMDAw
# MDBaFw0zMDEwMTcwMDAwMDBaMEwxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjEkMCIGA1UEAxMbVElNRVNUQU1QLVNIQTI1Ni0yMDE5LTEwLTE1
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA6WQ1nPqpmGVkG+QX3Lgp
# NsxnCViFTTDgyf/lOzwRKFCvBzHiXQkYwvaJjGkIBCPgdy2dFeW46KFqjv/UrtJ6
# Fu/4QbUdOXXBzy+nrEV+lG2sAwGZPGI+fnr9RZcxtPq32UI+p1Wb31pPWAKoMmki
# E76Lgi3GmKtrm7TJ8mURDHQNsvAIlnTE6LJIoqEUpfj64YlwRDuN7/uk9MO5vRQs
# 6wwoJyWAqxBLFhJgC2kijE7NxtWyZVkh4HwsEo1wDo+KyuDT17M5d1DQQiwues6c
# Z3o4d1RA/0+VBCDU68jOhxQI/h2A3dDnK3jqvx9wxu5CFlM2RZtTGUlinXoCm5UU
# owIDAQABo4IDODCCAzQwDgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwggG/BgNVHSAEggG2MIIBsjCCAaEGCWCGSAGG
# /WwHATCCAZIwKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9D
# UFMwggFkBggrBgEFBQcCAjCCAVYeggFSAEEAbgB5ACAAdQBzAGUAIABvAGYAIAB0
# AGgAaQBzACAAQwBlAHIAdABpAGYAaQBjAGEAdABlACAAYwBvAG4AcwB0AGkAdAB1
# AHQAZQBzACAAYQBjAGMAZQBwAHQAYQBuAGMAZQAgAG8AZgAgAHQAaABlACAARABp
# AGcAaQBDAGUAcgB0ACAAQwBQAC8AQwBQAFMAIABhAG4AZAAgAHQAaABlACAAUgBl
# AGwAeQBpAG4AZwAgAFAAYQByAHQAeQAgAEEAZwByAGUAZQBtAGUAbgB0ACAAdwBo
# AGkAYwBoACAAbABpAG0AaQB0ACAAbABpAGEAYgBpAGwAaQB0AHkAIABhAG4AZAAg
# AGEAcgBlACAAaQBuAGMAbwByAHAAbwByAGEAdABlAGQAIABoAGUAcgBlAGkAbgAg
# AGIAeQAgAHIAZQBmAGUAcgBlAG4AYwBlAC4wCwYJYIZIAYb9bAMVMB8GA1UdIwQY
# MBaAFPS24SAd/imu0uRhpbKiJbLIFzVuMB0GA1UdDgQWBBRWUw/BxgenTdfYbldy
# gFBM5OyewTBxBgNVHR8EajBoMDKgMKAuhixodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vc2hhMi1hc3N1cmVkLXRzLmNybDAyoDCgLoYsaHR0cDovL2NybDQuZGlnaWNl
# cnQuY29tL3NoYTItYXNzdXJlZC10cy5jcmwwgYUGCCsGAQUFBwEBBHkwdzAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tME8GCCsGAQUFBzAChkNo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRTSEEyQXNzdXJlZElE
# VGltZXN0YW1waW5nQ0EuY3J0MA0GCSqGSIb3DQEBCwUAA4IBAQAug6FEBUoE47ky
# UvrZgfAau/gJjSO5PdiSoeZGHEovbno8Y243F6Mav1gjskOclINOOQmwLOjH4eLM
# 7ct5a87eIwFH7ZVUgeCAexKxrwKGqTpzav74n8GN0SGM5CmCw4oLYAACnR9HxJ+0
# CmhTf1oQpvgi5vhTkjFf2IKDLW0TQq6DwRBOpCT0R5zeDyJyd1x/T+k5mCtXkkTX
# 726T2UPHBDNjUTdWnkcEEcOjWFQh2OKOVtdJP1f8Cp8jXnv0lI3dnRq733oqptJF
# plUMj/ZMivKWz4lG3DGykZCjXzMwYFX1/GswrKHt5EdOM55naii1TcLtW5eC+Mup
# CGxTCbT3MIIFMTCCBBmgAwIBAgIQCqEl1tYyG35B5AXaNpfCFTANBgkqhkiG9w0B
# AQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMTYwMTA3MTIwMDAwWhcNMzEwMTA3MTIwMDAwWjByMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQg
# VGltZXN0YW1waW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# vdAy7kvNj3/dqbqCmcU5VChXtiNKxA4HRTNREH3Q+X1NaH7ntqD0jbOI5Je/YyGQ
# mL8TvFfTw+F+CNZqFAA49y4eO+7MpvYyWf5fZT/gm+vjRkcGGlV+Cyd+wKL1oODe
# Ij8O/36V+/OjuiI+GKwR5PCZA207hXwJ0+5dyJoLVOOoCXFr4M8iEA91z3FyTgqt
# 30A6XLdR4aF5FMZNJCMwXbzsPGBqrC8HzP3w6kfZiFBe/WZuVmEnKYmEUeaC50ZQ
# /ZQqLKfkdT66mA+Ef58xFNat1fJky3seBdCEGXIX8RcG7z3N1k3vBkL9olMqT4Ud
# xB08r8/arBD13ays6Vb/kwIDAQABo4IBzjCCAcowHQYDVR0OBBYEFPS24SAd/imu
# 0uRhpbKiJbLIFzVuMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMBIG
# A1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsG
# AQUFBwMIMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8EejB4MDqg
# OKA2hjRodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURS
# b290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3JsMFAGA1UdIARJMEcwOAYKYIZIAYb9bAACBDAq
# MCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAsGCWCG
# SAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAQEAcZUS6VGHVmnN793afKpjerN4zwY3
# QITvS4S/ys8DAv3Fp8MOIEIsr3fzKx8MIVoqtwU0HWqumfgnoma/Capg33akOpMP
# +LLR2HwZYuhegiUexLoceywh4tZbLBQ1QwRostt1AuByx5jWPGTlH0gQGF+JOGFN
# YkYkh2OMkVIsrymJ5Xgf1gsUpYDXEkdws3XVk4WTfraSZ/tTYYmo9WuWwPRYaQ18
# yAGxuSh1t5ljhSKMYcp5lH5Z/IwP42+1ASa2bKXuh1Eh5Fhgm7oMLSttosR+u8Ql
# K0cCCHxJrhO24XxCQijGGFbPQTS2Zl22dHv1VjMiLyI2skuiSpXY9aaOUjGCAk0w
# ggJJAgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNI
# QTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0ECEATNP4VornbGG7D+cWDMp20w
# DQYJYIZIAWUDBAIBBQCggZgwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwG
# CSqGSIb3DQEJBTEPFw0yMDExMjExNDAxNTlaMCsGCyqGSIb3DQEJEAIMMRwwGjAY
# MBYEFAMlvVBe2pYwLcIvT6AeTCi+KDTFMC8GCSqGSIb3DQEJBDEiBCC2qOc+TRZE
# 8MJYH/iQ8ANvO54jTBsdTAvRmtFgO+kfMjANBgkqhkiG9w0BAQEFAASCAQAgp4Dz
# /H4bOg7zKgSEzbyXfEVBIjVze/YTR6EyWaTQCwtHCBrdMI4jNzgwFticNA4NO/c0
# /K6OkrOCbcfdcAyWoiBT8WqseJeEYSBiql8XtL4i7ubG224hgAjUXVwDZC/s2h6m
# cuQ6qC1ZASjJaQ3Ixusdz2+jV9rBmi84UqKFAc1NIfXS0+UZUl7yVuMv9wWwfUzs
# JisP/2+nVWp2jXNglSWx7rQ8pGw0zE4k1xbN4fbH1FSXxz8t4sMwnwzZCWuox76m
# hkBchTKeqcXA2dN4Kcz/NV0dMnwaJLXbExL/5y4KSvjn03laobL7m4JMdmhDbhfe
# 2toW+qLSpbMmbKHd
# SIG # End signature block
