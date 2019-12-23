Configuration PIVS
{
    param(
	[string]$PIVisionPath = 'D:\PI-Vision_2017-R2-SP1_.exe',
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
    [string]$PIWebAPIInstallDir = 'F:\Program Files\PIPC\WebAPI',
    [string]$PIWebAPIDataDir = 'F:\ProgramData\OSIsoft\WebAPI',
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
	[string]$deployHA,

	# PI Web API URI address
    [string]$PIWebAPIURI ="https://$env:COMPUTERNAME/piwebapi"
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
    [string]$tempJsonPath = Join-Path $env:temp 'piwebapiconfigtemp.json'
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

        # 2D i. Custom DSC resource to install PI Vision.
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
        }

        # 2E i. Required to execute PI Vision SQL database install
        cChocoPackageInstaller 'sqlserver-odbcdriver' {
            Name = 'sqlserver-odbcdriver'
			DependsOn = "[cChocoInstaller]installChoco"
        }

        # 2E ii. Required to execute PI Vision SQL database install. Requires reboot to be functional.
        cChocoPackageInstaller 'sqlserver-cmdlineutils' {
            Name = 'sqlserver-cmdlineutils'
			DependsOn = "[cChocoInstaller]installChoco"
        }

		if($env:COMPUTERNAME -eq $VSPrimary){
			# 2F i. Create domain service account to run PI Web API + PI Web API Crawler
			xADUser ServiceAccount_PIVS {
				DomainName                    = $DomainNetBiosName
				UserName                      = $PIVSSvcAccountUsername
				CannotChangePassword          = $true
				Description                   = 'PI Web API + Crawler service account.'
				DomainAdministratorCredential = $domainRunAsCredential
				Enabled                       = $true
				Ensure                        = 'Present'
				Password                      = $svcCredential
				DependsOn                     = '[WindowsFeature]ADPS'
			}

			# 2G ii. Add domain service account to run PI Web API + PI Web API Crawler to AD Group that has correct permissions on PI DA
			xADGroup AddSvcAcctToPIWebApps {
				GroupName        = $PIWebAppsADGroup
				GroupScope       = 'Global'
				Category         = 'Security'
				Ensure           = 'Present'
				Description      = $Group.Description
				DomainController = $PrimaryDomainController
				Credential       = $domainRunAsCredential
				MembersToInclude = $PIVSSvcAccountUsername
				DependsOn        = '[WindowsFeature]ADPS'
			}
		}

        # 2F ii. Configure HTTP SPN on service account instead and setup Kerberos delegation.
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

        # 2G. Trips any outstanding reboots due to installations.
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

        # 3E i. Updates Service Account for PI Services
        Service UpdatePIWebAPIServiceAccount {
            Name        = 'piwebapi'
            Credential  = $domainSvcCredential
            State       = 'Running'
            StartupType = 'Automatic'
            DependsOn   = "[xPIVisionInstall]InstallPIVision"
        }

        # 3E ii. Updates Service Account for PI Services
        Service UpdatePIWebAPICrawlerServiceAccount {
            Name        = 'picrawler'
            Credential  = $domainSvcCredential
            State       = 'Running'
            StartupType = 'Automatic'
            DependsOn   = "[xPIVisionInstall]InstallPIVision"
        }

        # 3F i. Updating RunAs accounts isn't sufficient. The Web API config tool must be ran to make adjustments to account for the change.
        # The following checks for the installed Web API and makes adjustments to the existing json file used for an unattended install.
        # Re-running the Web API setup honors the new RunAs accounts that are already set on the services. Updates this info wherever else this is needed.
        xPIWebAPIServiceAccountConfig UpdatePIWebAPIConfigServiceAccounts {
            ApiServiceAccountUsername = $svcRunAsDomainAccount
            CrawlerServiceAccountUsername = $svcRunAsDomainAccount
            Ensure = 'Present'
            PsDscRunAsCredential = $domainRunAsCredential
            DependsOn = '[Service]UpdatePIWebAPIServiceAccount', '[Service]UpdatePIWebAPICrawlerServiceAccount'
        }

        # 3F ii. xWebAppPool resource throws error when 'state = started' and account us updated. Need script resource to start it if it's stopped. Issuing IIS reset to start all services.
        # See: https://github.com/PowerShell/xWebAdministration/issues/230
        [string[]]$appPools = @('PIVisionAdminAppPool', 'PIVisionServiceAppPool')
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

        # 3G. PI Web API needs an AF and PI Data Archive source added as targets for the PI Crawler
        # The index generated by the Crawler is used by PI Vision and determines what is visible via PI Vision
        xPIWebAPISource AddPISource {
            PIWebAPIURI = $PIWebAPIURI
            SourceName  = "PI:$DefaultPIDataArchive"
            CrawlerHost = $env:COMPUTERNAME
            Ensure      = 'Present'
            Credential  = $domainRunAsCredential
            DependsOn   = '[xPIVisionInstall]InstallPIVision', '[Script]ConfigSPN'
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
# MIIbzAYJKoZIhvcNAQcCoIIbvTCCG7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAL/1opG5Ou8dAp
# /I4ofHaBozUH9e4vGJdmuoPgJptmD6CCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# dAbq5BqlYz1Fr8UrWeR3KIONPNtkm2IFHNMdpsgmKwC/Xh3nC3b27DGCEJQwghCQ
# AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIg
# QXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAVNNVk3TJ+08xyzMPnTxD8wDQYJ
# YIZIAWUDBAIBBQCggZ4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIA1jkMQz7f4z
# PjCJZll+tPFbCd2IQZwlxYgJXDODsUGLMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQA9
# vr09mayeL2zXOXG9hTxzcJSwDg9Op8wMhjw1MHOrkKF60bXs08XtMnulyixpqgj9
# KBWmU9UCmzEC6cR19/Xb23MM/rCn3medVCFP9Efq54+/a+S7lHBNPsp4yM3VjVLu
# SXB4fEvgp2cJI0P0eygz6dubTHk3YAcJoI15pzZe9fJ/rdKLh8A+iwKziYsJj6De
# /o00TNe6YepHBohkSLzFpohoGX8MgXujvlW79DwIsf6bTquKSAx5iqgJTuyAgvKt
# k00QnCDthCUGYMnbTBN/RvmRh47LCOsIceuYEgnK6/5sWpFNdiarP6RXoojDTnDZ
# npOUadk7obYqNa1wD4bSoYIOPTCCDjkGCisGAQQBgjcDAwExgg4pMIIOJQYJKoZI
# hvcNAQcCoIIOFjCCDhICAQMxDTALBglghkgBZQMEAgEwggEPBgsqhkiG9w0BCRAB
# BKCB/wSB/DCB+QIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgjvV1
# s62+Oysbi/pCcaEdDVML69iNW+wVFWEI68SZTxsCFQCvz/thKq9vejIrtbAiBEfk
# 6Z+r/xgPMjAxOTEwMDgxOTU2MTZaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
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
# DQEJBTEPFw0xOTEwMDgxOTU2MTZaMC8GCSqGSIb3DQEJBDEiBCCJYVk8QqmSz60j
# FvmJSpaNUwMr832B4NsEkRKQsOPGxzA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# BXuGRJ5w11TL76EI40U3tB8T5bq1av9fPGPruHLKCTdFe4xZHl5LYw9T+ZRyDFYX
# Go2efxA2ixcxAqqh0inQ2lA8tCf+Zt4wqUU0DkinUZZr1m5eWBC2KceSZ1ieDhYb
# eaFWyPA2j8RNMLerlDDnHePy1/sw097LK45D8cOfUbyseTTy6QlbT/rmLoJuFBbZ
# 1Sl5GwO2ZwI0s01JX3WA5iGw4jBryL7bFUhtgTJ7jAf+eFntn0s/UAjFVJ7kmKpa
# ABMM+dJQc5vkDN72rQXeGlnRrEZrOhuo+2dkcT3gt/E/5rv39245+LZtppVxcZhY
# dyecAMiuAKRyk7UNP6gF/A==
# SIG # End signature block
