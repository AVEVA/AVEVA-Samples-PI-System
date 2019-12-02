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
$HiddenSettingsRegex = "user|password"
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
        Add-InfoLog -Message "Run Preliminary Checks."
        & $xUnitConsole $TestDll -class "OSIsoft.PISystemDeploymentTests.PreliminaryChecks" -html ""$PreCheckTestResultFile"" -verbose | 
        Tee-Object -Variable "preliminaryCheckResults"
        $preliminaryCheckResults | Write-ExecutionLog
        $errorTestCount = [int]($preliminaryCheckResults[-1] -replace ".*Errors: (\d+),.*", '$1')
        $failedTestCount = [int]($preliminaryCheckResults[-1] -replace ".*Failed: (\d+),.*", '$1')
        if (($errorTestCount + $failedTestCount) -gt 0) {
            Add-ErrorLog -Message "Preliminary Checks failed, please troubleshoot the errors and try again." -Fatal
        }

        $excludedTestClassesString = '-noclass "OSIsoft.PISystemDeploymentTests.PreliminaryChecks" ' + 
        (Build-ExcludedTestClassesString)
        Add-InfoLog -Message "Run product tests."
        $fullCommand = '& $xUnitConsole $TestDll --% ' + $excludedTestClassesString + 
        " -html ""$TestResultFile"" -verbose -parallel none"
    }

    Add-InfoLog -Message $fullCommand
    Invoke-Expression $fullCommand | Tee-Object -Variable "productTestResults"
    $productTestResults | Write-ExecutionLog
    $errorTestCount = [int]($productTestResults[-1] -replace ".*Errors: (\d+),.*", '$1')
    $failedTestCount = [int]($productTestResults[-1] -replace ".*Failed: (\d+),.*", '$1')
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
    $ConfigureObject = New-Object psobject
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


function Read-AppSettings {
    [CmdletBinding()]
    param ()
    ([xml](Get-Content $AppConfigFile)).configuration.appsettings.add | 
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
            Add-AFDatabase $Database -AFServer $PISystem -ErrorAction Stop > $null
            $db = $PISystem.Databases[$Database]
            $elementSearch = New-Object OSIsoft.AF.Search.AFElementSearch $db, "AllElements", ""
            
            Add-InfoLog -Message "Start xml importing."
            $PISystem.ImportXml($db, 1041, $WindFarmxml) > $null

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
        $isLocalAccount = [Security.Principal.WindowsIdentity]::GetCurrent().Name.ToUpper().Contains([Environment]::MachineName.ToUpper())
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
                if ($isLocalAccount -and $attempt -gt 1) {
                    Add-ErrorLog -Message ("A local account is detected as the running user. Due to a known issue, an explicit mapping " +
                        "from the local account to the PI AF Administrators identity need to be created in AF security despite the default " +
                        "BUILTIN\Administrators to PI AF Administrators mapping.") -Fatal
                }
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
# MIIcLQYJKoZIhvcNAQcCoIIcHjCCHBoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBEi7sMoAzaIntb
# YeMjoPl/hNwiiCRyagS+aghl/reHvKCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# dAbq5BqlYz1Fr8UrWeR3KIONPNtkm2IFHNMdpsgmKwC/Xh3nC3b27DGCEPUwghDx
# AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIg
# QXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAVNNVk3TJ+08xyzMPnTxD8wDQYJ
# YIZIAWUDBAIBBQCggf8wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJE+8h1U8d0R
# 0iLkp/qzdRecrxjQbB7Q5dTg076itiGsMIGSBgorBgEEAYI3AgEMMYGDMIGAoFyA
# WgBQAEkAIABTAHkAcwB0AGUAbQAgAEQAZQBwAGwAbwB5AG0AZQBuAHQAIABUAGUA
# cwB0AHMAIABQAG8AdwBlAHIAUwBoAGUAbABsACAAUwBjAHIAaQBwAHQAc6EggB5o
# dHRwOi8vdGVjaHN1cHBvcnQub3Npc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# itciiu8LHFnSM2RhhlB5QVP/sAFtzxy7cBwIK1+7HbCE7zOG/SpJFv07MrRyNuPT
# tUwE9Imor6ve0994j0GzOJfXBPqbrielbYa61Jy/lZg31+WTqLHfy1xAOmdhG7zi
# fppaa7+wv616lTiXZTsVI386x8sV31+BmtkOmMfsrWZmbr+m5b41aW303kYyMBF+
# F73BaJDx93R/SwG6JFtKud+j/DUnw8VDGynC+e0liwu+mHhZ+0w/W4lfrmS1hI6c
# tasuIRI1EEz6WVPIPbuf+Sr20rqmQwH3axgIhZi9S+0ISuNh1GDfaTmR29+oMITn
# qqek3YnczS1+MMm5sBi+SKGCDj0wgg45BgorBgEEAYI3AwMBMYIOKTCCDiUGCSqG
# SIb3DQEHAqCCDhYwgg4SAgEDMQ0wCwYJYIZIAWUDBAIBMIIBDwYLKoZIhvcNAQkQ
# AQSggf8EgfwwgfkCAQEGC2CGSAGG+EUBBxcDMDEwDQYJYIZIAWUDBAIBBQAEIPte
# e5QyNoybwOFZ7NsCDC2iBOwuksQ/mJLYRs9pCftjAhUArWzIqyxCskCKBL+tbYam
# yl1B1DsYDzIwMTkxMTIwMTUzODQ0WjADAgEeoIGGpIGDMIGAMQswCQYDVQQGEwJV
# UzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xHzAdBgNVBAsTFlN5bWFu
# dGVjIFRydXN0IE5ldHdvcmsxMTAvBgNVBAMTKFN5bWFudGVjIFNIQTI1NiBUaW1l
# U3RhbXBpbmcgU2lnbmVyIC0gRzOgggqLMIIFODCCBCCgAwIBAgIQewWx1EloUUT3
# yYnSnBmdEjANBgkqhkiG9w0BAQsFADCBvTELMAkGA1UEBhMCVVMxFzAVBgNVBAoT
# DlZlcmlTaWduLCBJbmMuMR8wHQYDVQQLExZWZXJpU2lnbiBUcnVzdCBOZXR3b3Jr
# MTowOAYDVQQLEzEoYykgMjAwOCBWZXJpU2lnbiwgSW5jLiAtIEZvciBhdXRob3Jp
# emVkIHVzZSBvbmx5MTgwNgYDVQQDEy9WZXJpU2lnbiBVbml2ZXJzYWwgUm9vdCBD
# ZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTAeFw0xNjAxMTIwMDAwMDBaFw0zMTAxMTEy
# MzU5NTlaMHcxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazEoMCYGA1UEAxMf
# U3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBALtZnVlVT52Mcl0agaLrVfOwAa08cawyjwVrhponADKX
# ak3JZBRLKbvC2Sm5Luxjs+HPPwtWkPhiG37rpgfi3n9ebUA41JEG50F8eRzLy60b
# v9iVkfPw7mz4rZY5Ln/BJ7h4OcWEpe3tr4eOzo3HberSmLU6Hx45ncP0mqj0hOHE
# 0XxxxgYptD/kgw0mw3sIPk35CrczSf/KO9T1sptL4YiZGvXA6TMU1t/HgNuR7v68
# kldyd/TNqMz+CfWTN76ViGrF3PSxS9TO6AmRX7WEeTWKeKwZMo8jwTJBG1kOqT6x
# zPnWK++32OTVHW0ROpL2k8mc40juu1MO1DaXhnjFoTcCAwEAAaOCAXcwggFzMA4G
# A1UdDwEB/wQEAwIBBjASBgNVHRMBAf8ECDAGAQH/AgEAMGYGA1UdIARfMF0wWwYL
# YIZIAYb4RQEHFwMwTDAjBggrBgEFBQcCARYXaHR0cHM6Ly9kLnN5bWNiLmNvbS9j
# cHMwJQYIKwYBBQUHAgIwGRoXaHR0cHM6Ly9kLnN5bWNiLmNvbS9ycGEwLgYIKwYB
# BQUHAQEEIjAgMB4GCCsGAQUFBzABhhJodHRwOi8vcy5zeW1jZC5jb20wNgYDVR0f
# BC8wLTAroCmgJ4YlaHR0cDovL3Muc3ltY2IuY29tL3VuaXZlcnNhbC1yb290LmNy
# bDATBgNVHSUEDDAKBggrBgEFBQcDCDAoBgNVHREEITAfpB0wGzEZMBcGA1UEAxMQ
# VGltZVN0YW1wLTIwNDgtMzAdBgNVHQ4EFgQUr2PWyqNOhXLgp7xB8ymiOH+AdWIw
# HwYDVR0jBBgwFoAUtnf6aUhHn1MS1cLqBzJ2B9GXBxkwDQYJKoZIhvcNAQELBQAD
# ggEBAHXqsC3VNBlcMkX+DuHUT6Z4wW/X6t3cT/OhyIGI96ePFeZAKa3mXfSi2VZk
# hHEwKt0eYRdmIFYGmBmNXXHy+Je8Cf0ckUfJ4uiNA/vMkC/WCmxOM+zWtJPITJBj
# SDlAIcTd1m6JmDy1mJfoqQa3CcmPU1dBkC/hHk1O3MoQeGxCbvC2xfhhXFL1TvZr
# jfdKer7zzf0D19n2A6gP41P3CnXsxnUuqmaFBJm3+AZX4cYO9uiv2uybGB+queM6
# AL/OipTLAduexzi7D1Kr0eOUA2AKTaD+J20UMvw/l0Dhv5mJ2+Q5FL3a5NPD6ita
# s5VYVQR9x5rsIwONhSrS/66pYYEwggVLMIIEM6ADAgECAhB71OWvuswHP6EBIwQi
# QU0SMA0GCSqGSIb3DQEBCwUAMHcxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1h
# bnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29y
# azEoMCYGA1UEAxMfU3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTAeFw0x
# NzEyMjMwMDAwMDBaFw0yOTAzMjIyMzU5NTlaMIGAMQswCQYDVQQGEwJVUzEdMBsG
# A1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xHzAdBgNVBAsTFlN5bWFudGVjIFRy
# dXN0IE5ldHdvcmsxMTAvBgNVBAMTKFN5bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBp
# bmcgU2lnbmVyIC0gRzMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCv
# Doqq+Ny/aXtUF3FHCb2NPIH4dBV3Z5Cc/d5OAp5LdvblNj5l1SQgbTD53R2D6T8n
# SjNObRaK5I1AjSKqvqcLG9IHtjy1GiQo+BtyUT3ICYgmCDr5+kMjdUdwDLNfW48I
# HXJIV2VNrwI8QPf03TI4kz/lLKbzWSPLgN4TTfkQyaoKGGxVYVfR8QIsxLWr8mwj
# 0p8NDxlsrYViaf1OhcGKUjGrW9jJdFLjV2wiv1V/b8oGqz9KtyJ2ZezsNvKWlYEm
# LP27mKoBONOvJUCbCVPwKVeFWF7qhUhBIYfl3rTTJrJ7QFNYeY5SMQZNlANFxM48
# A+y3API6IsW0b+XvsIqbAgMBAAGjggHHMIIBwzAMBgNVHRMBAf8EAjAAMGYGA1Ud
# IARfMF0wWwYLYIZIAYb4RQEHFwMwTDAjBggrBgEFBQcCARYXaHR0cHM6Ly9kLnN5
# bWNiLmNvbS9jcHMwJQYIKwYBBQUHAgIwGRoXaHR0cHM6Ly9kLnN5bWNiLmNvbS9y
# cGEwQAYDVR0fBDkwNzA1oDOgMYYvaHR0cDovL3RzLWNybC53cy5zeW1hbnRlYy5j
# b20vc2hhMjU2LXRzcy1jYS5jcmwwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYD
# VR0PAQH/BAQDAgeAMHcGCCsGAQUFBwEBBGswaTAqBggrBgEFBQcwAYYeaHR0cDov
# L3RzLW9jc3Aud3Muc3ltYW50ZWMuY29tMDsGCCsGAQUFBzAChi9odHRwOi8vdHMt
# YWlhLndzLnN5bWFudGVjLmNvbS9zaGEyNTYtdHNzLWNhLmNlcjAoBgNVHREEITAf
# pB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtNjAdBgNVHQ4EFgQUpRMBqZ+F
# zBtuFh5fOzGqeTYAex0wHwYDVR0jBBgwFoAUr2PWyqNOhXLgp7xB8ymiOH+AdWIw
# DQYJKoZIhvcNAQELBQADggEBAEaer/C4ol+imUjPqCdLIc2yuaZycGMv41UpezlG
# Tud+ZQZYi7xXipINCNgQujYk+gp7+zvTYr9KlBXmgtuKVG3/KP5nz3E/5jMJ2aJZ
# EPQeSv5lzN7Ua+NSKXUASiulzMub6KlN97QXWZJBw7c/hub2wH9EPEZcF1rjpDvV
# aSbVIX3hgGd+Yqy3Ti4VmuWcI69bEepxqUH5DXk4qaENz7Sx2j6aescixXTN30cJ
# hsT8kSWyG5bphQjo3ep0YG5gpVZ6DchEWNzm+UgUnuW/3gC9d7GYFHIUJN/HESwf
# AD/DSxTGZxzMHgajkF9cVIs+4zNbgg/Ft4YCTnGf6WZFP3YxggJaMIICVgIBATCB
# izB3MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24x
# HzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsxKDAmBgNVBAMTH1N5bWFu
# dGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0ECEHvU5a+6zAc/oQEjBCJBTRIwCwYJ
# YIZIAWUDBAIBoIGkMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAcBgkqhkiG
# 9w0BCQUxDxcNMTkxMTIwMTUzODQ0WjAvBgkqhkiG9w0BCQQxIgQggHqiHahV9MAI
# Fm1gM1RIHn/8QTRkt648/5BQ/NMGvv8wNwYLKoZIhvcNAQkQAi8xKDAmMCQwIgQg
# xHTOdgB9AjlODaXk3nwUxoD54oIBPP72U+9dtx/fYfgwCwYJKoZIhvcNAQEBBIIB
# AE8cvTFabKD0VznqtS+te8NM5BF3sJYywTd2oNp3AkEBfG6ct6WyPCkiFTHfb11H
# 5lYF88/weG9C5f/nTogVKE5P0x4scgFs/SCVUsl+pBF3w3B39E6w3J7T9RcDgTR8
# s4tNl3Tvw8JuYdRJP8FaOTSQ7EXwr1NgeQut3Gmcrogj21ehipc9KZPOUpY0HdYV
# LmDi+T5jQxpifInevhXlCWugIS2KsxJQSiKvRshgpLUcrsmvrbGDasBTber8XPwr
# lcnRxdfnt4Jur155z0jJFEu/T3NeMUGS8bhoWDTfYD3UXC4pG+88xPdtByIIHwET
# EgF0+w2a4DIq9VZcRM5uQY4=
# SIG # End signature block
