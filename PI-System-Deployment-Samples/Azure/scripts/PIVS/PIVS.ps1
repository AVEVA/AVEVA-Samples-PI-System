Configuration PIVS
{
    param(
    [string]$PIVisionPath = 'D:\PI Vision_2019 Patch 1_.exe',
    # Used to run installs. Account must have rights to AD and SQL to conduct successful installs/configs.
    [Parameter(Mandatory)]
    [pscredential]$runAsCredential,
    # Service account used to run PI Vision and PI Web API.
    [pscredential]$svcCredential,
    # AD group mapped to correct privileges on the PI Data Archive, need to add above svc acct to this
    [String]$PIWebAppsADGroup = 'PIWebApps',

    # PI AF Server Install settings
    [string]$PIHOME = 'F:\Program Files (x86)\PIPC',
    [string]$PIHOME64 = 'F:\Program Files\PIPC',
    [string]$VisionDBName = "PIVisionDB",

    # Switch to indicate highly available deployment
    [string]$namePrefix,
    [string]$nameSuffix,

    # Primary domain controller for AD Group manipulation
    [String]$PrimaryDomainController = ($namePrefix+'-dc-vm'+$nameSuffix),

    # SQL Server to install PI Vision database. This should be the primary SQL server hostname.
    [string]$DefaultSqlServer = ($namePrefix+'-sql-vm'+$nameSuffix),
    [string]$SQLSecondary = ($namePrefix+'-sql-vm1'),

    [string]$DefaultPIAFServer = ($namePrefix+'-piaf-vm'+$nameSuffix),

    [string]$DefaultPIDataArchive = ($namePrefix+'-pida-vm'+$nameSuffix),

    [string]$sqlAlwaysOnAvailabilityGroupName = ($namePrefix+'-sqlag'+$nameSuffix),

    # Name used to identify VS load balanced endpoint for HA deployments. Used to create DNS CName record.
    [string]$VSLoadBalancedName = 'PIVS',
    [string]$VSLoadBalancerIP,

    # PI Vision server names
    [string]$VSPrimary,
    [string]$VSSecondary,

    # SQL Server Always On Listener.
    [string]$SqlServerAOListener = 'AG0-Listener',
    
    # Switch to indicate highly available deployment
    [Parameter(Mandatory)]
    [string]$deployHA
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName cchoco
    Import-DscResource -ModuleName PSDSSupportPIVS
    Import-DscResource -ModuleName xWebAdministration
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName xStorage
    Import-DscResource -ModuleName xDnsServer
    Import-DscResource -ModuleName SqlServerDsc

    Import-Module -Name SqlServer

    # Under HA deployment senarios, subsitute the primary SQL Server hostname for the SQL Always On Listner Name.
    # This is used in the installation arguements for PI Vision. This value get's cofigured in the PIVision\Admin specifying which SQL intance to connect to.
    if($deployHA -eq "true"){
        Write-Verbose -Message "HA deployment detected. PI Vision install will use the following SQL target: $SqlServerAOListener" -Verbose
        $FDSQLDBSERVER = $SqlServerAOListener

        Write-Verbose -Message "HA deployment detected. PI AF Server will point to AF load balanced name 'PIAF'." -Verbose
        Write-Verbose -Message "'PIAF' is an internal DNS CName record pointing to the AWS internal load balancer for AF. See PIAF deployment." -Verbose
        $DefaultPIAFServer = 'PIAF'

    } else {
        Write-Verbose -Message "Single instance deployment detected. PI Vision install will use the following SQL target: $DefaultSqlServer" -Verbose
        $FDSQLDBSERVER = $DefaultSqlServer
    }

    # Lookup Domain names (FQDN and NetBios). Assumes VM is already domain joined.
    $DomainNetBiosName = ((Get-WmiObject -Class Win32_NTDomain -Filter "DnsForestName = '$((Get-WmiObject -Class Win32_ComputerSystem).Domain)'").DomainName)
    $DomainDNSName = (Get-WmiObject Win32_ComputerSystem).Domain

    # Extracts username only (no domain net bios name) for domain runas account
    $runAsAccountUsername = $runAsCredential.UserName
    # Create credential with Domain Net Bios Name included.
    $domainRunAsCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$runAsAccountUsername", $runAsCredential.Password)

    # Extracts username only (no domain net bios name)
    $PIVSSvcAccountUsername = $svcCredential.UserName
    # Create credential with Domain Net Bios Name included.
    $domainSvcCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$PIVSSvcAccountUsername", $svcCredential.Password)

    # Agreggate parameters used for PI Vision configuration settings
    [string]$allowedDAServers = $DefaultPIDataArchive
    [string]$visionScriptPath = "$PIHOME64\PIVision\Admin\SQL"
    [string]$svcRunAsDomainAccount = $PIVSSvcAccountUsername

    Node localhost {

        # Necessary if reboots are needed during DSC application/program installations
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }

        #region ### 1. VM PREPARATION ###
        # 1A. Check for new volumes. The uninitialized disk number may vary depending on EC2 type (i.e. temp disk or no temp disk). This logic will test to find the disk number of an uninitialized disk.
        $disks = Get-Disk | Where-Object 'partitionstyle' -eq 'raw' | Sort-Object number
        if ($disks) {
            # Elastic Block Storage for Binary Files
            xWaitforDisk Volume_F {
                DiskID           = $disks[0].number
                retryIntervalSec = 30
                retryCount       = 20
            }
            xDisk Volume_F {
                DiskID      = $disks[0].number
                DriveLetter = 'F'
                FSFormat    = 'NTFS'
                FSLabel     = 'Apps'
                DependsOn   = '[xWaitforDisk]Volume_F'
            }
        }

        # 1B i.Open firewall rules for PI Vision
        xFirewall PIVSHttpFirewallRule {
            Direction   = 'Inbound'
            Name        = 'PI-System-PI-Vision-HTTP-TCP-In'
            DisplayName = 'PI System PI Vision HTTP (TCP-In)'
            Description = 'Inbound rule for PI Vision to allow HTTP traffic.'
            Group       = 'PI Systems'
            Enabled     = 'True'
            Action      = 'Allow'
            Protocol    = 'TCP'
            LocalPort   = '80'
            Ensure      = 'Present'
        }

        # 1B ii. Open firewall rules for PI Vision
        xFirewall PIVSHttpsFirewallRule {
            Direction   = 'Inbound'
            Name        = 'PI-System-PI-Vision-HTTPS-TCP-In'
            DisplayName = 'PI System PI Vision HTTPS (TCP-In)'
            Description = 'Inbound rule for PI Vision to allow HTTPS traffic.'
            Group       = 'PI Systems'
            Enabled     = 'True'
            Action      = 'Allow'
            Protocol    = 'TCP'
            LocalPort   = '443'
            Ensure      = 'Present'
        }
        #endregion ### 1. VM PREPARATION ###


        #region ### 2. INSTALL AND SETUP ###
        # 2A i. Used for PI Vision Service account creation.
        WindowsFeature ADPS {
            Name   = 'RSAT-AD-PowerShell'
            Ensure = 'Present'
        }

        # 2B i. Install IIS Web Server Features
        WindowsFeature IIS {
            Ensure = "Present"
            Name = "Web-Server"
        }

        # 2B ii. Install IIS Tools
        WindowsFeature IISManagementTools {
            Ensure = "Present"
            Name = "Web-Mgmt-Tools"
            DependsOn='[WindowsFeature]IIS'
        }

        # 2C i. Installing Chocolatey to facilitate package installs.
        cChocoInstaller installChoco {
            InstallDir = 'C:\ProgramData\chocolatey'
        }

        # 2C ii. Need 7zip to exact files from PI Vision executable for installation.
        cChocoPackageInstaller '7zip' {
            Name = '7zip'
            DependsOn = "[cChocoInstaller]installChoco"
        }

        # 2D i. Install .NET Framework 4.8.
        cChocoPackageInstaller 'dotnetfx' {
            Name     = 'netfx-4.8-devpack'
            Ensure   = 'Present'
            Version  = '4.8.0.20190930'
            DependsOn = '[cChocoInstaller]installChoco'
        }

        # 2D ii. Reboot to complete .NET installation.
        xPendingReboot RebootDotNet {
            Name      = 'RebootDotNet'
            DependsOn = '[cChocoPackageInstaller]dotnetfx'
        }

        # If a load balancer DNS record is passed, then this will generate a DNS CName. This entry is used as the PIVS load balanced endpoint.
        if ($deployHA -eq 'true') {
            # Tools needed to write DNS Records
            WindowsFeature DNSTools {
                Name   = 'RSAT-DNS-Server'
                Ensure = 'Present'
            }

            # Adds a CName DSN record used to point to internal Elastic Load Balancer DNS record
            xDnsRecord VSLoadBanacedEndPoint {
                Name                 = $VSLoadBalancedName
                Target               = $VSLoadBalancerIP
                Type                 = 'CName'
                Zone                 = $DomainDNSName
                DnsServer            = $PrimaryDomainController
                DependsOn            = '[WindowsFeature]DnsTools'
                Ensure               = 'Present'
                PsDscRunAsCredential = $runAsCredential
            }
        }

        # 2E i. Custom DSC resource to install PI Vision.
        # This resource helps update silent installation files to facilitate unattended install.
        xPIVisionInstall 'InstallPIVision' {
            InstallKitPath       = $PIVisionPath
            AFServer             = $DefaultPIAFServer
            PIServer             = $DefaultPIDataArchive
            ConfigInstance       = $env:COMPUTERNAME
            ConfigAssetServer    = $DefaultPIAFServer
            PIHOME               = $PIHOME
            PIHOME64             = $PIHOME64
            Ensure               = 'Present'
            PSDscRunAsCredential = $domainRunAsCredential
            DependsOn            = '[xPendingReboot]RebootDotNet'
        }

        # 2F i. Required to execute PI Vision SQL database install
        cChocoPackageInstaller 'sqlserver-odbcdriver' {
            Name = 'sqlserver-odbcdriver'
            DependsOn = "[cChocoInstaller]installChoco"
        }

        # 2F ii. Required to execute PI Vision SQL database install. Requires reboot to be functional.
        cChocoPackageInstaller 'sqlserver-cmdlineutils' {
            Name = 'sqlserver-cmdlineutils'
            DependsOn = "[cChocoInstaller]installChoco"
        }

        # 2G ii. Configure HTTP SPN on service account instead and setup Kerberos delegation.
        # We need to do this before modifications that will require this setup, specifically updating PI Web API Cralwer targets.
        xADServicePrincipalName 'SPN01'
        {
            ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + ":5985" )
            Account              = $($env:COMPUTERNAME + "$")
            PsDscRunAsCredential = $domainRunAsCredential
            DependsOn			 = '[WindowsFeature]ADPS'
        }
        xADServicePrincipalName 'SPN02'
        {
            ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + "." + $DomainDNSName + ":5985" )
            Account              = $($env:COMPUTERNAME + "$")
            PsDscRunAsCredential = $domainRunAsCredential
            DependsOn			 = '[WindowsFeature]ADPS'
        }

        xADServicePrincipalName 'SPN03'
        {
            ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + ":5986" )
            Account              = $($env:COMPUTERNAME + "$")
            PsDscRunAsCredential = $domainRunAsCredential
            DependsOn			 = '[WindowsFeature]ADPS'
        }
        xADServicePrincipalName 'SPN04'
        {
            ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + "." + $DomainDNSName + ":5986" )
            Account              = $($env:COMPUTERNAME + "$")
            PsDscRunAsCredential = $domainRunAsCredential
            DependsOn			 = '[WindowsFeature]ADPS'
        }

        xADServicePrincipalName 'SPN05'
        {
            ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME)
            Account              = $PIVSSvcAccountUserName
            PsDscRunAsCredential = $domainRunAsCredential
            DependsOn			 = '[WindowsFeature]ADPS'
        }
        xADServicePrincipalName 'SPN06'
        {
            ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + "." + $DomainDNSName)
            Account              = $PIVSSvcAccountUserName
            PsDscRunAsCredential = $domainRunAsCredential
            DependsOn			 = '[WindowsFeature]ADPS'
        }

        if($deployHA -eq 'true' -and $env:COMPUTERNAME -eq $VSPrimary){
            xADServicePrincipalName 'SPN07'
            {
                ServicePrincipalName = $("HTTP/" + $VSLoadBalancedName)
                Account              = $PIVSSvcAccountUserName
                PsDscRunAsCredential = $domainRunAsCredential
                DependsOn			 = '[WindowsFeature]ADPS'
            }
            xADServicePrincipalName 'SPN08'
            {
                ServicePrincipalName = $("HTTP/" + $VSLoadBalancedName + "." + $DomainDNSName)
                Account              = $PIVSSvcAccountUserName
                PsDscRunAsCredential = $domainRunAsCredential
                DependsOn			 = '[WindowsFeature]ADPS'
            }
        }

        Script ConfigSPN {
            # Must return a hashtable with at least one key named 'Result' of type String
            GetScript            = {
                return @{
                    Value = 'ConfigSPN'
                }
            }

            # Must return a boolean: $true or $false
            TestScript			= {
                $File = 'C:\ConfigSPNExecuted.txt'
                $Content = 'ConfigSPN Executed'
 
                If ((Test-path $File) -and (Select-String -Path $File -SimpleMatch $Content -Quiet)) {
                    $True
                }
                Else {
                    $False
                }
            }

            # Returns nothing. Configures Kerberos delegation
            SetScript            = {
                $VerbosePreference = $Using:VerbosePreference

                'ConfigSPN Executed' | Out-File C:\ConfigSPNExecuted.txt

                # THE KERB DELEGATION DID NOT GET IMPLEMENTED
                Write-Verbose -Message "2. Setting Kerberos Constrained Delegation on ""$using:svcRunAsDomainAccount"" for AF Server ""$($using:DefaultPIAFServer)"", PI Data Archive ""$($using:DefaultPIDataArchive)"", and SQL Server instance ""$($using:DefaultSqlServer)""."

                # THE BELOW DELEGATIONS ALSO DID NOT GET CREATED
                $delgationAf = 'AFSERVER/' + "$using:DefaultPIAFServer"
                $delgationAfFqdn = 'AFSERVER/' + $using:DefaultPIAFServer + '.' + $using:DomainDNSName
                $delgationPi = 'PISERVER/' + $using:DefaultPIDataArchive
                $delgationPiFqdn = 'PISERVER/' + $using:DefaultPIDataArchive + '.' + $using:DomainDNSName
                $delgationSqlFqdn = 'MSSQLSvc/' + $using:DefaultSqlServer + '.' + $using:DomainDNSName
                $delgationSqlFqdnPort = 'MSSQLSvc/' + $using:DefaultSqlServer + '.' + $using:DomainDNSName + ':1433'

                Set-ADUser -Identity $using:PIVSSvcAccountUserName -add @{'msDS-AllowedToDelegateTo' = $delgationAf, $delgationAfFqdn, $delgationPi, $delgationPiFqdn, $delgationSqlFqdn, $delgationSqlFqdnPort} -Verbose

                # Note that -TrustedToAuthForDelegation == "Use any authentication protocol" and -TrustedForDelegation == "Use Kerberos Only".
                Write-Verbose -Message "3. Setting delegation to 'Use any authentication protocol'."
                Set-ADAccountControl -TrustedToAuthForDelegation $true -Identity $using:PIVSSvcAccountUserName -Verbose
            }

            # Script must execute under an domain creds with permissions to add/remove SPNs.
            PsDscRunAsCredential = $domainRunAsCredential
            DependsOn = '[WindowsFeature]ADPS'
        }

        # 2H. Trips any outstanding reboots due to installations.
        xPendingReboot 'Reboot1' {
            Name      = 'PostInstall'
            DependsOn = '[xPIVisionInstall]InstallPIVision','[cChocoPackageInstaller]sqlserver-cmdlineutils'
        }
        #endregion ### 2. INSTALL AND SETUP ###


        #region ### 3. IMPLEMENT POST INSTALL CONFIGURATION ###
        # 3A i. Executes batch scripts used to install the SQL database used by PI Vision
        xPIVisionSQLConfig InstallPIVSDB {
            SQLServerName        = $DefaultSqlServer
            PIVisionDBName       = $VisionDBName
            ServiceAccountName   = "$DomainNetBiosName\$PIVSSvcAccountUsername"
            PIHOME64             = $PIHOME64
            Ensure               = 'Present'
            PsDscRunAsCredential = $domainRunAsCredential
            DependsOn            = "[xPIVisionInstall]InstallPIVision"
        }

        # 3A ii. If a load balancer DNS record is passed, then will initiate replication of PIVision to SQL Secondary.
        if($deployHA -eq 'true' -and $env:COMPUTERNAME -eq $VSPrimary){

            # Need to added PI Vision service account login on secondary. When the scripts to create the PIVS database are run, this login is only added to the SQL primary.
            # The SQL login for the service account does not get replicated when added to the AG, therefore need to manually add the login on the SQL secondary.
            SqlServerLogin AddPIVisionSvc {
                Ensure               = 'Present'
                Name                 = "$DomainNetBiosName\$PIVSSvcAccountUsername"
                LoginType            = 'WindowsUser'
                ServerName           = $SQLSecondary
                InstanceName         = 'MSSQLSERVER'
                PsDscRunAsCredential = $domainRunAsCredential
            }

            # Required when placed in an AG
            SqlDatabaseRecoveryModel $VisionDBName {
                InstanceName          = 'MSSQLServer'
                Name                  = $VisionDBName
                RecoveryModel         = 'Full'
                ServerName            = $DefaultSqlServer
                PsDscRunAsCredential  = $domainRunAsCredential
                DependsOn             = '[xPIVisionInstall]InstallPIVision'
            }

            # Adds PIVision Database to AG and replicas to secondary SQL Server.
            SqlAGDatabase AddPIDatabaseReplicas {
                AvailabilityGroupName   = $sqlAlwaysOnAvailabilityGroupName
                BackupPath              = "\\$DefaultSqlServer\Backup"
                DatabaseName            = $VisionDBName
                InstanceName            = 'MSSQLSERVER'
                ServerName              = $DefaultSqlServer
                Ensure                  = 'Present'
                PsDscRunAsCredential    = $domainRunAsCredential
                DependsOn               = '[xPIVisionInstall]InstallPIVision',"[SqlDatabaseRecoveryModel]$VisionDBName"
            }
        }

        # 3B. Update PI Vision web.config (Set target PI Data Archive used by PI Vision)
        xWebConfigKeyValue ConfigAllowedPIDataArchives {
            ConfigSection = 'AppSettings'
            Key           = 'PIServersAllowed'
            WebsitePath   = "IIS:\Sites\Default Web Site\PIVision\"
            Value         = $allowedDAServers
            Ensure        = 'Present'
            IsAttribute   = $false
            DependsOn     = "[xPIVisionInstall]InstallPIVision"
        }

        # 3C. Updates PI Vision configuration with target SQL server and database.
        xPIVisionConfigFile UpdateSqlForVision {
            SQLServerName  = $FDSQLDBSERVER
            PIVisionDBName = $VisionDBName
            PIHOME64       = $PIHOME64
            Ensure         = 'Present'
            DependsOn      = "[xPIVisionInstall]InstallPIVision"
        }

        # 3D i. Post Install Configuration - Update App Pool service account for Admin site.
        # Known issue with App Pool failing to start: https://github.com/PowerShell/xWebAdministration/issues/301
        # (Suspect passwords with double quote characters break this resource with version 1.18.0.0.)
        xWebAppPool PIVisionAdminAppPool {
            Name         = 'PIVisionAdminAppPool'
            autoStart    = $true
            startMode    = 'AlwaysRunning'
            identityType = 'SpecificUser'
            Credential   = $domainSvcCredential
            Ensure       = 'Present'
            #State        = 'Started'
            DependsOn    = "[xPIVisionInstall]InstallPIVision"
        }

        # 3D ii.Post Install Configuration - Update App Pool service account for Service.
        # Known issue with App Pool failing to start: https://github.com/PowerShell/xWebAdministration/issues/301
        # (Suspect passwords with double quote characters break this resource with version 1.18.0.0.)
        xWebAppPool PIVisionServiceAppPool {
            Name         = 'PIVisionServiceAppPool'
            autoStart    = $true
            startMode    = 'AlwaysRunning'
            identityType = 'SpecificUser'
            Credential   = $domainSvcCredential
            Ensure       = 'Present'
            #State       = 'Started'
            DependsOn    = "[xPIVisionInstall]InstallPIVision"
        }

        # 3D iii.Post Install Configuration - Update App Pool service account for Service.
        # Known issue with App Pool failing to start: https://github.com/PowerShell/xWebAdministration/issues/301
        # (Suspect passwords with double quote characters break this resource with version 1.18.0.0.)
        xWebAppPool PIVisionUtilityAppPool {
            Name         = 'PIVisionUtilityAppPool'
            autoStart    = $true
            startMode    = 'AlwaysRunning'
            identityType = 'SpecificUser'
            Credential   = $domainSvcCredential
            Ensure       = 'Present'
            #State       = 'Started'
            DependsOn    = "[xPIVisionInstall]InstallPIVision"
        }

        # 3F ii. xWebAppPool resource throws error when 'state = started' and account us updated. Need script resource to start it if it's stopped. Issuing IIS reset to start all services.
        # See: https://github.com/PowerShell/xWebAdministration/issues/230
        [string[]]$appPools = @('PIVisionAdminAppPool', 'PIVisionServiceAppPool', 'PIVisionUtilityAppPool')
        ForEach ($pool in $appPools) {
            Script "Start$pool" {
                GetScript  = {
                    $state = (Get-WebAppPoolState -Name $using:pool).Value
                    return @{
                        Result = $state
                    }
                }
                TestScript = {
                    $state = (Get-WebAppPoolState -Name $using:pool).Value
                    if ($state -ne 'Started') {
                        Write-Verbose -Message "The AppPool $using:pool is stopped. $pool needs starting."
                        $false
                    }
                    else {
                        Write-Verbose -Message "AppPool $using:pool is running."
                        $true
                    }
                }
                SetScript  = {
                    Write-Verbose -Message "Starting AppPool $using:pool"
                    Start-sleep -Seconds 3
                    $result = Start-Process -FilePath "$env:windir\system32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList "iisreset" -WorkingDirectory "$env:windir\system32\WindowsPowerShell\v1.0\" -RedirectStandardOutput "C:\IisResetOutput.txt" -RedirectStandardError "C:\IisError.txt"
                    $exitCode = $result.ExitCode
                    Write-Verbose -Message "Exit Code: $exitCode"
                    Write-Verbose -Message "AppPool $using:pool is now running."
                    Start-Sleep -Seconds 3
                }
                DependsOn = "[xPIVisionInstall]InstallPIVision"
            }
        }

        ## 3F iii. Set Authentication - Commands to set Kernel Mode configuration and use AppPool Cred to true.
        # While PI Vision documentation states to disable kernel mode, the better practice is to leave it enabled to improve performance.
        # To do this, we need to allow the use of the AppPoolCreds for authentication. This can be done using the cmdline tool appcmd.exe and the config shown below.
        Script EnableKernelModeAndUseAppPoolCreds {

            GetScript  = {
                # Use appcmd.exe to check if entries are present.
                $cmd = "$env:windir\system32\inetsrv\appcmd.exe"
                $useKernelMode = &$cmd list config "Default Web Site/PIVision" -section:windowsAuthentication /text:useKernelMode
                $useAppPoolCredentials = &$cmd list config "Default Web Site/PIVision" -section:windowsAuthentication /text:useAppPoolCredentials
                return @{
                    Result = "KernelMode=$useKernelMode and useAppPoolCreds=$useAppPoolCredentials."
                }
            }

            TestScript = {
                # Use appcmd.exe to check if entries are present and set to true.
                Write-Verbose -Message "Checking 'useKernelMode' and 'useAppPoolCredentials' are set to true."
                [int]$inState = $null
                $cmd = "$env:windir\system32\inetsrv\appcmd.exe"
                &$cmd list config 'Default Web Site/PIVision' -section:windowsAuthentication /text:* |
                ForEach-Object -Process {
                    if ($_ -match 'useKernelMode:"true"') {
                        # Entry found and set to TRUE. Increment counter.
                        Write-Verbose -Message "Match Found: $_" -Verbose
                        $inState++
                    }
                    elseif ($_ -match 'useAppPoolCredentials:"true"') {
                        # Entry found and set to TRUE. Increment counter.
                        Write-Verbose -Message "Match Found: $_" -Verbose
                        $inState++
                    }
                    elseif ($_ -match 'useKernelMode:"false"') {
                        # Entry found but set to FALSE.
                        Write-Verbose -Message "Match Found: $_" -Verbose
                    }
                    elseif ($_ -match 'useAppPoolCredentials:"false"') {
                        # Entry found but set to FALSE.
                        Write-Verbose -Message "Match Found: $_" -Verbose
                    }
                }

                switch ($inState) {
                    2 { Write-Verbose -Message 'BOTH useKernelMode AND useAppPoolCredentials = TRUE.'; return $true }
                    1 { Write-Verbose -Message 'ONLY useKernelMode OR useAppPoolCrednetial = TRUE'; return $false }
                    0 { Write-Verbose -Message 'BOTH useKernelMode AND useAppPoolCrednetial = FALSE or ABSENT'; return $false }
                }
                [int]$inState = $null

            }

            SetScript  = {
                Write-Verbose -Message "Setting 'useKernelMode' to true."
                Start-Process -FilePath "$env:windir\system32\inetsrv\appcmd.exe" -ArgumentList 'set config "Default Web Site/PIVision" -section:windowsAuthentication /useKernelMode:"True" /commit:apphost' -WorkingDirectory "$env:windir\system32\inetsrv" -RedirectStandardOutput 'C:\KernelModeSetOutput.txt' -RedirectStandardError 'C:\KernelModeSetError.txt'
                Write-Verbose -Message "Setting 'useKernelMode' to true completed"

                Start-Sleep -Seconds 3

                Write-Verbose -Message "Setting 'useAppPoolCredentials' to true."
                Start-Process -FilePath "$env:windir\system32\inetsrv\appcmd.exe" -ArgumentList 'set config "Default Web Site/PIVision" -section:windowsAuthentication /useAppPoolCredentials:"True" /commit:apphost' -WorkingDirectory "$env:windir\system32\inetsrv" -RedirectStandardOutput 'C:\KernelModeSetOutput.txt' -RedirectStandardError 'C:\KernelModeSetError.txt'
                Write-Verbose -Message "Setting 'useAppPoolCredentials' to true completed."

                Start-Sleep -Seconds 3
            }
        }
        #endregion ### 3. IMPLEMENT POST INSTALL CONFIGURATION ###

        #region 4. Deployment Test Firewall Rules
        xFirewall RSMForTestsEPMAP {
            Group   = 'Remote Service Management'
            Name    = 'Remote Service Management (RPC-EPMAP)'
            Ensure  = 'Present'
            Enabled = 'True'
        }

        xFirewall RSMForTestsRPC {
            Group   = 'Remote Service Management'
            Name    = 'Remote Service Management (RPC)'
            Ensure  = 'Present'
            Enabled = 'True'
        }
        xFirewall RSMForTestsNP {
            Group   = 'Remote Service Management'
            Name    = 'Remote Service Management (NP-In)'
            Ensure  = 'Present'
            Enabled = 'True'
        }

        xFirewall PingForTests {
            Name    = 'File and Printer Sharing (Echo Request - ICMPv4-In)'
            Ensure  = 'Present'
            Enabled = 'True'
        }   
        #endregion
    }
}
# SIG # Begin signature block
# MIIcVwYJKoZIhvcNAQcCoIIcSDCCHEQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAx4czOynJHo7QP
# kY7yALufN+tMbu4+owI24vp/XqvADqCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# Q+9sIKX0AojqBVLFUNQpzelOdjGWNzdcMMSu8p0pNw4xeAbuCEHfMYIRIDCCERwC
# AQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBB
# c3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQBlb6upLHhoprGBiRrHb6WzANBglg
# hkgBZQMEAgEFAKCBnjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgt2HkNqqvI2vn
# /aTKiMVB0B7qNa8C5/rl1I7TGiQD81UwMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAANw
# a7jS3CvtcbjQIclz4VGuSOd6MogHgudoIsud2P6GDB+UIwLPzL34xZSowoa4siVh
# clraa1YLU0EMRj6ah6XZEYE+O4piS9K7gWkfK4/FylLVGN9HfQHPaZLXUaYZ/4uW
# ySFRkLVGqfpFoRaH33joQ/pXCdWlG/NkPzQVFlyezmjjTh4qivWhuW4MDdjZnPXh
# nvD7eXmQ7/y4dAdzE4mjHA+iKr1jUFcjOFr0x7tLGt2Xg70YY75/OASXrf8zvSy3
# FGlXd+5Y/h3fLl67qdr367HAJPI4lBIvQVF+N/wxBCpU4G27cVpeqgMahwBoWZBa
# UJ0RLIbcnDpnDGcPxm+hgg7JMIIOxQYKKwYBBAGCNwMDATGCDrUwgg6xBgkqhkiG
# 9w0BBwKggg6iMIIOngIBAzEPMA0GCWCGSAFlAwQCAQUAMHgGCyqGSIb3DQEJEAEE
# oGkEZzBlAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQgc7OAxhphXlwT
# 7kN6BWoT5TLv25zLn4kyJG+OQ5aP0x8CEQDzmPZxCdbuXqqimqSs+Y7lGA8yMDIw
# MTEyNDIwMDgyMVqgggu7MIIGgjCCBWqgAwIBAgIQBM0/hWiudsYbsP5xYMynbTAN
# BgkqhkiG9w0BAQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2Vy
# dCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTE5MTAwMTAwMDAw
# MFoXDTMwMTAxNzAwMDAwMFowTDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMSQwIgYDVQQDExtUSU1FU1RBTVAtU0hBMjU2LTIwMTktMTAtMTUw
# ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDpZDWc+qmYZWQb5BfcuCk2
# zGcJWIVNMODJ/+U7PBEoUK8HMeJdCRjC9omMaQgEI+B3LZ0V5bjooWqO/9Su0noW
# 7/hBtR05dcHPL6esRX6UbawDAZk8Yj5+ev1FlzG0+rfZQj6nVZvfWk9YAqgyaSIT
# vouCLcaYq2ubtMnyZREMdA2y8AiWdMToskiioRSl+PrhiXBEO43v+6T0w7m9FCzr
# DCgnJYCrEEsWEmALaSKMTs3G1bJlWSHgfCwSjXAOj4rK4NPXszl3UNBCLC56zpxn
# ejh3VED/T5UEINTryM6HFAj+HYDd0OcreOq/H3DG7kIWUzZFm1MZSWKdegKblRSj
# AgMBAAGjggM4MIIDNDAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNV
# HSUBAf8EDDAKBggrBgEFBQcDCDCCAb8GA1UdIASCAbYwggGyMIIBoQYJYIZIAYb9
# bAcBMIIBkjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQ
# UzCCAWQGCCsGAQUFBwICMIIBVh6CAVIAQQBuAHkAIAB1AHMAZQAgAG8AZgAgAHQA
# aABpAHMAIABDAGUAcgB0AGkAZgBpAGMAYQB0AGUAIABjAG8AbgBzAHQAaQB0AHUA
# dABlAHMAIABhAGMAYwBlAHAAdABhAG4AYwBlACAAbwBmACAAdABoAGUAIABEAGkA
# ZwBpAEMAZQByAHQAIABDAFAALwBDAFAAUwAgAGEAbgBkACAAdABoAGUAIABSAGUA
# bAB5AGkAbgBnACAAUABhAHIAdAB5ACAAQQBnAHIAZQBlAG0AZQBuAHQAIAB3AGgA
# aQBjAGgAIABsAGkAbQBpAHQAIABsAGkAYQBiAGkAbABpAHQAeQAgAGEAbgBkACAA
# YQByAGUAIABpAG4AYwBvAHIAcABvAHIAYQB0AGUAZAAgAGgAZQByAGUAaQBuACAA
# YgB5ACAAcgBlAGYAZQByAGUAbgBjAGUALjALBglghkgBhv1sAxUwHwYDVR0jBBgw
# FoAU9LbhIB3+Ka7S5GGlsqIlssgXNW4wHQYDVR0OBBYEFFZTD8HGB6dN19huV3KA
# UEzk7J7BMHEGA1UdHwRqMGgwMqAwoC6GLGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9zaGEyLWFzc3VyZWQtdHMuY3JsMDKgMKAuhixodHRwOi8vY3JsNC5kaWdpY2Vy
# dC5jb20vc2hhMi1hc3N1cmVkLXRzLmNybDCBhQYIKwYBBQUHAQEEeTB3MCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wTwYIKwYBBQUHMAKGQ2h0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJBc3N1cmVkSURU
# aW1lc3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggEBAC6DoUQFSgTjuTJS
# +tmB8Bq7+AmNI7k92JKh5kYcSi9uejxjbjcXoxq/WCOyQ5yUg045CbAs6Mfh4szt
# y3lrzt4jAUftlVSB4IB7ErGvAoapOnNq/vifwY3RIYzkKYLDigtgAAKdH0fEn7QK
# aFN/WhCm+CLm+FOSMV/YgoMtbRNCroPBEE6kJPRHnN4PInJ3XH9P6TmYK1eSRNfv
# bpPZQ8cEM2NRN1aeRwQRw6NYVCHY4o5W10k/V/wKnyNee/SUjd2dGrvfeiqm0kWm
# VQyP9kyK8pbPiUbcMbKRkKNfMzBgVfX8azCsoe3kR04znmdqKLVNwu1bl4L4y6kI
# bFMJtPcwggUxMIIEGaADAgECAhAKoSXW1jIbfkHkBdo2l8IVMA0GCSqGSIb3DQEB
# CwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQg
# SUQgUm9vdCBDQTAeFw0xNjAxMDcxMjAwMDBaFw0zMTAxMDcxMjAwMDBaMHIxCzAJ
# BgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5k
# aWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBU
# aW1lc3RhbXBpbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC9
# 0DLuS82Pf92puoKZxTlUKFe2I0rEDgdFM1EQfdD5fU1ofue2oPSNs4jkl79jIZCY
# vxO8V9PD4X4I1moUADj3Lh477sym9jJZ/l9lP+Cb6+NGRwYaVX4LJ37AovWg4N4i
# Pw7/fpX786O6Ij4YrBHk8JkDbTuFfAnT7l3ImgtU46gJcWvgzyIQD3XPcXJOCq3f
# QDpct1HhoXkUxk0kIzBdvOw8YGqsLwfM/fDqR9mIUF79Zm5WYScpiYRR5oLnRlD9
# lCosp+R1PrqYD4R/nzEU1q3V8mTLex4F0IQZchfxFwbvPc3WTe8GQv2iUypPhR3E
# HTyvz9qsEPXdrKzpVv+TAgMBAAGjggHOMIIByjAdBgNVHQ4EFgQU9LbhIB3+Ka7S
# 5GGlsqIlssgXNW4wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wEgYD
# VR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYB
# BQUHAwgweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5k
# aWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4
# oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dEFzc3VyZWRJRFJvb3RDQS5jcmwwUAYDVR0gBEkwRzA4BgpghkgBhv1sAAIEMCow
# KAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCwYJYIZI
# AYb9bAcBMA0GCSqGSIb3DQEBCwUAA4IBAQBxlRLpUYdWac3v3dp8qmN6s3jPBjdA
# hO9LhL/KzwMC/cWnww4gQiyvd/MrHwwhWiq3BTQdaq6Z+CeiZr8JqmDfdqQ6kw/4
# stHYfBli6F6CJR7Euhx7LCHi1lssFDVDBGiy23UC4HLHmNY8ZOUfSBAYX4k4YU1i
# RiSHY4yRUiyvKYnleB/WCxSlgNcSR3CzddWThZN+tpJn+1Nhiaj1a5bA9FhpDXzI
# AbG5KHW3mWOFIoxhynmUfln8jA/jb7UBJrZspe6HUSHkWGCbugwtK22ixH67xCUr
# RwIIfEmuE7bhfEJCKMYYVs9BNLZmXbZ0e/VWMyIvIjayS6JKldj1po5SMYICTTCC
# AkkCAQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZ
# MBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hB
# MiBBc3N1cmVkIElEIFRpbWVzdGFtcGluZyBDQQIQBM0/hWiudsYbsP5xYMynbTAN
# BglghkgBZQMEAgEFAKCBmDAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJ
# KoZIhvcNAQkFMQ8XDTIwMTEyNDIwMDgyMVowKwYLKoZIhvcNAQkQAgwxHDAaMBgw
# FgQUAyW9UF7aljAtwi9PoB5MKL4oNMUwLwYJKoZIhvcNAQkEMSIEICRpeIR45cfZ
# jGjPPk2yFrpNDDwb0NTg6VvcstYF03w0MA0GCSqGSIb3DQEBAQUABIIBAEY8sz7L
# 37SU5mvbgjHarYeSbLZgFcToyTA5L3jxypSm9JoR4B2ZVgrbVc45yi1U4VZkBF4M
# Chy9g6wL8Y0SD7tsBB+GyUmzumSDDn23pbtzOZmTkmTVLqD/nItvtnszdyhFOE4+
# Kej9clnuvj2g6L+mNFMdCHJoYytuWBd4z0OnqR3TY9Xdwua2ROJXpO7UqHaPOYl1
# MnYxOg7HghGuo/FKFIY2lLNx7LZIXi4X5YwoiHmOD1Nq5XmJ6PtdEuH9u3DWWBua
# 4/VRjfRYFbnofsIBh92LyN7LkpymbpGvhY9jnvHHHZHQqvhHDWdFTgNSwdOJ5teS
# PV5ZSNXjJ99JVVg=
# SIG # End signature block
