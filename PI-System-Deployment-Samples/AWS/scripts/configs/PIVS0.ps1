[CmdletBinding()]
param(
    # NetBIOS name of the domain
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainNetBiosName,

    # Fully qualified domain name (FQDN) of the forest root domain e.g. example.com
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainDNSName,

    # Username of domain admin account.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainAdminUserName,

    # PI Vision service account name. Also the AWS SSM Parameter Store parameter name. Used to retrieve the account password.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIVSServiceAccountName,

    # Primary domain controller targeted for service account creation.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PrimaryDomainController,

    # Default PI Data Archive
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DefaultPIDataArchive,

    # Default PI AF Server
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DefaultPIAFServer,

    # SQL Server to install PIFD database (Primary)
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DefaultSqlServer,

    # SQL Server Secondary. (Used to create SQL login for PI Vision service account.)
    [Parameter()]
    [ValidateNotNullorEmpty()]
    [String]$SecondarySqlServer,

    # SQL Server Always On Listener.
    [Parameter()]
    [ValidateNotNullorEmpty()]
    [String]$SqlServerAOListener = 'AG0-Listener',

    # DNS record of internal Elastic Load Balancer. Used for PI Vision load balancer endpoint.
    [Parameter()]
    $ElasticLoadBalancerDnsRecord,

    # Name used to identify PI Vision load balanced endpoint.
    [Parameter()]
    $VSLoadBalancedName = 'PIVS',

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix
)

try{
    # Set to enable catch to Write-AWSQuickStartException
    $ErrorActionPreference = "Stop"


    # Used for configuration
    Import-Module SQLServer -RequiredVersion 21.0.17279

    # Set Local Configuration Manager
    Configuration LCMConfig {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode  = 'ApplyOnly'
            CertificateID      = (Get-ChildItem Cert:\LocalMachine\My)[0].Thumbprint
        }
    }

    LCMConfig
    Set-DscLocalConfigurationManager -Path .\LCMConfig -Verbose

    # Set Configuration Data. Certificate used for credential encryption.
    $ConfigurationData = @{
        AllNodes = @(
        @{
            NodeName             = $env:COMPUTERNAME
            CertificateFile      = 'C:\dsc.cer'
            PSDscAllowDomainUser = $true
            DscCertThumbprint = (Get-ChildItem Cert:\LocalMachine\My)[0].Thumbprint
        }
        )
    }

    # Get existing service account password from AWS System Manager Parameter Store.
    $DomainAdminPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$DomainAdminUserName" -WithDecryption $True).Parameters[0].Value
    $PIVSServiceAccountPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$PIVSServiceAccountName" -WithDecryption $True).Parameters[0].Value

    # Generate credential for domain security group creation.
    $securePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $domainCred = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$DomainAdminUserName", $securePassword)


    Configuration PIVS0Config
    {
        param(
        [pscredential]$domainCredential = $domainCred,
        [string]$PIVSSvcAccountUserName = 'svc-pivs0',
        [string]$PIVSSvcAccountPassword = $PIVSServiceAccountPassword,
        [string]$PIHOME = 'F:\Program Files (x86)\PIPC',
        [string]$PIHOME64 = 'F:\Program Files\PIPC',
        [string]$PIWebAPIInstallDir = 'F:\Program Files\PIPC\WebAPI',
        [string]$PIWebAPIDataDir = 'F:\ProgramData\OSIsoft\WebAPI',
        [string]$SqlServer = $DefaultSqlServer,
        [string]$VisionDBName = "PIVisionDB",
        [string]$AFServer = $DefaultPIAFServer,
        [string]$PIServer = $DefaultPIDataArchive,
        [string]$PIWebAPIURI ="https://$env:COMPUTERNAME/piwebapi"
        )

        Import-DscResource -ModuleName PSDesiredStateConfiguration
        Import-DscResource -ModuleName cChoco -ModuleVersion 2.4.0.0
        Import-DscResource -ModuleName PSDSSupportPIVS
        Import-DscResource -ModuleName xWebAdministration -ModuleVersion 2.8.0.0
        Import-DscResource -ModuleName xNetworking -ModuleVersion 5.7.0.0
        Import-DscResource -ModuleName xActiveDirectory -ModuleVersion 3.0.0.0
        Import-DscResource -ModuleName xPendingReboot -ModuleVersion 0.4.0.0
        Import-DscResource -ModuleName xStorage -ModuleVersion 3.4.0.0
        Import-DscResource -ModuleName xDnsServer -ModuleVersion 1.15.0.0
        Import-DscResource -ModuleName SqlServerDsc -ModuleVersion 13.2.0.0

        # Under HA deployment senarios, subsitute the primary SQL Server hostname for the SQL Always On Listner Name.
        # This is used in the installation arguements for PI Vision. This value get's cofigured in the PIVision\Admin specifying which SQL intance to connect to.
        if($ElasticLoadBalancerDnsRecord){
            Write-Verbose -Message "HA deployment detected. PI Vision install will use the following SQL target: $SqlServerAOListener" -Verbose
            $FDSQLDBSERVER = $SqlServerAOListener

            Write-Verbose -Message "HA deployment detected. PI AF Server will point to AF load balanced name 'PIAF'." -Verbose
            Write-Verbose -Message "'PIAF' is an internal DNS CName record pointing to the AWS internal load balancer for AF. See PIAF deployment." -Verbose
            $AFServer = 'PIAF'

        } else {
            Write-Verbose -Message "Single instance deployment detected. PI Vision install will use the following SQL target: $DefaultSqlServer" -Verbose
            $FDSQLDBSERVER = $DefaultSqlServer
        }

        # Generate credential for domain service account.
        $serviceSecurePassword = ConvertTo-SecureString $PIVSSvcAccountPassword -AsPlainText -Force
        $serviceAccountCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$PIVSSvcAccountUsername", $serviceSecurePassword)

        # Agreggate parameters used for PI Vision configuration settings
        [string]$allowedDAServers = $PIServer
        [string]$visionScriptPath = "$PIHOME64\PIVision\Admin\SQL"
        [string]$tempJsonPath = Join-Path $env:temp 'piwebapiconfigtemp.json'
        [string]$svcRunAsDomainAccount = $serviceAccountCredential.UserName

        Node $env:COMPUTERNAME {

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
            }

            # If a load balancer DNS record is passed, then this will generate a DNS CName. This entry is used as the PIVS load balanced endpoint.
            if($ElasticLoadBalancerDnsRecord){
                # Tools needed to write DNS Records
                WindowsFeature DNSTools {
                    Name = 'RSAT-DNS-Server'
                    Ensure = 'Present'
                }

                # Adds a CName DSN record used to point to internal Elastic Load Balancer DNS record
                xDnsRecord PIVSLoadBanacedEndPoint
                {
                    Name = $VSLoadBalancedName
                    Target = $ElasticLoadBalancerDnsRecord
                    Type = 'CName'
                    Zone = $DomainDNSName
                    DependsOn = '[WindowsFeature]DnsTools'
                    DnsServer = $PrimaryDomainController
                    Ensure = 'Present'
                    PsDscRunAsCredential = $domainCredential
                }
            }

            # 2D i. Custom DSC resource to install PI Vision.
            # This resource helps update silent installation files to facilitate unattended install.
            xPIVisionInstall 'InstallPIVision' {
                InstallKitPath       = 'C:\media\PIVision\PIVisionInstaller.exe'
                AFServer             = $AFServer
                PIServer             = $PIServer
                ConfigInstance       = $env:COMPUTERNAME
                ConfigAssetServer    = $AFServer
                PIHOME               = $PIHOME
                PIHOME64             = $PIHOME64
                Ensure               = 'Present'
                PSDscRunAsCredential = $domainCredential
            }

            # 2E i. Required to execute PI Vision SQL database install
            cChocoPackageInstaller 'sqlserver-odbcdriver' {
                Name = 'sqlserver-odbcdriver'
            }

            # 2E ii. Required to execute PI Vision SQL database install. Requires reboot to be functional.
            cChocoPackageInstaller 'sqlserver-cmdlineutils' {
                Name = 'sqlserver-cmdlineutils'
            }

            # 2F i. Configure HTTP SPN on service account instead and setup Kerberos delegation.
			xADServicePrincipalName 'SPN01'
			{
				ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + ":5985" )
				Account              = $($env:COMPUTERNAME + "$")
				PsDscRunAsCredential = $domainCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}
			xADServicePrincipalName 'SPN02'
			{
				ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + "." + $DomainDNSName + ":5985" )
				Account              = $($env:COMPUTERNAME + "$")
				PsDscRunAsCredential = $domainCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}

			xADServicePrincipalName 'SPN03'
			{
				ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + ":5986" )
				Account              = $($env:COMPUTERNAME + "$")
				PsDscRunAsCredential = $domainCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}
			xADServicePrincipalName 'SPN04'
			{
				ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + "." + $DomainDNSName + ":5986" )
				Account              = $($env:COMPUTERNAME + "$")
				PsDscRunAsCredential = $domainCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}

			xADServicePrincipalName 'SPN05'
			{
				ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME)
				Account              = $PIVSSvcAccountUserName
				PsDscRunAsCredential = $domainCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}
			xADServicePrincipalName 'SPN06'
			{
				ServicePrincipalName = $("HTTP/" + $env:COMPUTERNAME + "." + $DomainDNSName)
				Account              = $PIVSSvcAccountUserName
				PsDscRunAsCredential = $domainCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}

			if($ElasticLoadBalancerDnsRecord){
				xADServicePrincipalName 'SPN07'
				{
					ServicePrincipalName = $("HTTP/" + $VSLoadBalancedName)
					Account              = $PIVSSvcAccountUserName
					PsDscRunAsCredential = $domainCredential
 					DependsOn			 = '[WindowsFeature]ADPS'
				}
				xADServicePrincipalName 'SPN08'
				{
					ServicePrincipalName = $("HTTP/" + $VSLoadBalancedName + "." + $DomainDNSName)
					Account              = $PIVSSvcAccountUserName
					PsDscRunAsCredential = $domainCredential
 					DependsOn			 = '[WindowsFeature]ADPS'
				}
			}

            # We need to do this before modifications that will require this setup, specifically updating PI Web API Cralwer targets.
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

                # Returns nothing. Configures service account HTTP Service Principal Name and  Kerberos delegation
                SetScript            = {
                    $VerbosePreference = $Using:VerbosePreference

					'ConfigSPN Executed' | Out-File C:\ConfigSPNExecuted.txt

                    Write-Verbose -Message "2. Setting Kerberos Constrained Delegation on ""$using:svcRunAsDomainAccount"" for AF Server ""$($using:afServer)"", PI Data Archive ""$($using:PIServer)"", and SQL Server instance ""$($using:sqlServer)""."

                    $delgationAf = 'AFSERVER/' + "$using:afServer"
                    $delgationAfFqdn = 'AFSERVER/' + $using:afServer + '.' + $using:DomainDNSName
                    $delgationPi = 'PISERVER/' + $using:PIServer
                    $delgationPiFqdn = 'PISERVER/' + $using:PIServer + '.' + $using:DomainDNSName
                    $delgationSqlFqdn = 'MSSQLSvc/' + $using:sqlServer + '.' + $using:DomainDNSName
                    $delgationSqlFqdnPort = 'MSSQLSvc/' + $using:sqlServer + '.' + $using:DomainDNSName + ':1433'

                    Set-ADUser -Identity $using:PIVSSvcAccountUserName -add @{'msDS-AllowedToDelegateTo' = $delgationAf, $delgationAfFqdn, $delgationPi, $delgationPiFqdn, $delgationSqlFqdn, $delgationSqlFqdnPort} -Verbose

                    # Note that -TrustedToAuthForDelegation == "Use any authentication protocol" and -TrustedForDelegation == "Use Kerberos Only".
                    Write-Verbose -Message "3. Setting delegation to 'Use any authentication protocol'."
                    Set-ADAccountControl -TrustedToAuthForDelegation $true -Identity $using:PIVSSvcAccountUserName -Verbose
                }

                # Script must execute under an domain creds with permissions to add/remove SPNs.
                PsDscRunAsCredential = $domainCredential
                DependsOn = '[WindowsFeature]ADPS'
            }

            # 2G. Trips any outstanding reboots due to installations.
            xPendingReboot 'Reboot1' {
                Name      = 'PostInstall'
                DependsOn = '[xPIVisionInstall]InstallPIVision','[cChocoPackageInstaller]sqlserver-cmdlineutils'
            }
			
            #region ### Set firewall rules ###
			Script SetNetFirewallRule {
                GetScript = {
                    return @{
                        Value = 'SetNetFirewallRule'
                    }
                }

                # Forces SetScript execution everytime
                TestScript = {
                    return $false
                }

                SetScript = {
                    Try {
						# Enable remote service management for COTS
						Set-NetFirewallRule -DisplayGroup "Remote Service Management" -Enabled True
						Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -Enabled True
                    }
                    Catch {
                        $CheckSource = Get-EventLog -LogName Application -Source AWSQuickStartStatus -ErrorAction SilentlyContinue
                        if (!$CheckSource) {New-EventLog -LogName Application -Source 'AWSQuickStartStatus' -Verbose}  # Check for source to avoid throwing exception if already present.

                        Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message  $_
                    }
                }
				PsDscRunAsCredential = $domainCredential
                DependsOn  = '[xPIVisionInstall]InstallPIVision'
            }
            #endregion Set firewall rules ###

            #endregion ### 2. INSTALL AND SETUP ###


            #region ### 3. IMPLEMENT POST INSTALL CONFIGURATION ###
            # 3A i. Executes batch scripts used to install the SQL database used by PI Vision
            xPIVisionSQLConfig InstallPIVSDB {
                SQLServerName        = $SqlServer
                PIVisionDBName       = $VisionDBName
                ServiceAccountName   = $svcRunAsDomainAccount
                PIHOME64             = $PIHOME64
                Ensure               = 'Present'
                PsDscRunAsCredential = $domainCredential
                DependsOn            = "[xPIVisionInstall]InstallPIVision"
            }

            # 3A ii. If a load balancer DNS record is passed, then will initiate replication of PIVision to SQL Secondary.
            if($ElasticLoadBalancerDnsRecord){

                # Need to added PI Vision service account login on secondary. When the scripts to create the PIVS database are run, this login is only added to the SQL primary.
                # The SQL login for the service account does not get replicated when added to the AG, therefore need to manually add the login on the SQL secondary.
                SqlServerLogin AddPIVisionSvc {
                    Ensure               = 'Present'
                    Name                 = $svcRunAsDomainAccount
                    LoginType            = 'WindowsUser'
                    ServerName           = $SecondarySqlServer
                    InstanceName         = 'MSSQLSERVER'
                    PsDscRunAsCredential = $domainCredential
                }

                # Required when placed in an AG
                SqlDatabaseRecoveryModel $VisionDBName {
                    InstanceName          = 'MSSQLServer'
                    Name                  = $VisionDBName
                    RecoveryModel         = 'Full'
                    ServerName            = $DefaultSqlServer
                    PsDscRunAsCredential  = $domainCredential
                    DependsOn             = '[xPIVisionInstall]InstallPIVision'
                }

                # Adds PIVision Database to AG and replicas to secondary SQL Server.
                SqlAGDatabase AddPIDatabaseReplicas {
                    AvailabilityGroupName   = 'SQLAG0'
                    BackupPath              = "\\$DefaultSqlServer\Backup"
                    DatabaseName            = $VisionDBName
                    InstanceName            = 'MSSQLSERVER'
                    ServerName              = $DefaultSqlServer
                    Ensure                  = 'Present'
                    PsDscRunAsCredential    = $domainCredential
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
                Credential   = $serviceAccountCredential
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
                Credential   = $serviceAccountCredential
                Ensure       = 'Present'
                #State       = 'Started'
                DependsOn    = "[xPIVisionInstall]InstallPIVision"
            }

            # 3E i. Updates Service Account for PI Services
            Service UpdatePIWebAPIServiceAccount {
                Name        = 'piwebapi'
                Credential  = $serviceAccountCredential
                State       = 'Running'
                StartupType = 'Automatic'
                DependsOn   = "[xPIVisionInstall]InstallPIVision"
            }

            # 3E ii. Updates Service Account for PI Services
            Service UpdatePIWebAPICrawlerServiceAccount {
                Name        = 'picrawler'
                Credential  = $serviceAccountCredential
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
                PsDscRunAsCredential = $domainCredential
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

            # 3G i. PI Web API needs an AF and PI Data Archive source added as targets for the PI Crawler
            # The index generated by the Crawler is used by PI Vision and determines what is visible via PI Vision
            xPIWebAPISource AddPISource {
                PIWebAPIURI = $PIWebAPIURI
                SourceName  = "PI:$PIServer"
                CrawlerHost = $env:COMPUTERNAME
                Ensure      = 'Present'
                Credential  = $domainCredential
                DependsOn   = '[xPIVisionInstall]InstallPIVision', '[Script]ConfigSPN'
            }
            #endregion ### 3. IMPLEMENT POST INSTALL CONFIGURATION ###
        }
    }

    PIVS0Config -ConfigurationData $ConfigurationData
    Start-DSCConfiguration .\PIVS0Config -Wait -Verbose -Force -ErrorVariable ev
}

catch{
    # If any expectations are thrown, output to CloudFormation Init.
    $_ | Write-AWSQuickStartException
}
# SIG # Begin signature block
# MIIbywYJKoZIhvcNAQcCoIIbvDCCG7gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCUJOZsd7ooA19B
# P8zeyvdwcfm9XaS5Y28hz77xzrbWZKCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# dAbq5BqlYz1Fr8UrWeR3KIONPNtkm2IFHNMdpsgmKwC/Xh3nC3b27DGCEJMwghCP
# AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIg
# QXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAVNNVk3TJ+08xyzMPnTxD8wDQYJ
# YIZIAWUDBAIBBQCggZ4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEID9xMyqeLX+k
# ennsoy+CN3Wt6H5WgN2uaUvIe7quMiZ8MDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQCS
# zfJ4Nkv7v04twkhWxgjMZqWWeEYE5mepuyYqHksl6ma4UOWojUfspo4Ylh1sn/KD
# 6WOhtUHjnHZ5DocAKpAL+xUpfPfb/QO8pp46+hmMDR54KMp5RC9GVeCg4c2ncEmZ
# Ahk+EXcG9kpeBhdZ5PtGKGv9g8oa2rX5UzDa2MGyDfMPsCRlnP6Te+CCbIQ6Zmck
# pwakWmLcdOqYBvrjKehlMALkc3HB0mlrYXO67izObjLgibIFOAEs04ouBOa7imqT
# j4p7szdJgBp4PoZWyAG7NBY0DOqzEbnBmfCzrQWnkr8WTPyGvsevQW6tQVp4xMMM
# IZNkHFV1YCLRlBT3iy/foYIOPDCCDjgGCisGAQQBgjcDAwExgg4oMIIOJAYJKoZI
# hvcNAQcCoIIOFTCCDhECAQMxDTALBglghkgBZQMEAgEwggEOBgsqhkiG9w0BCRAB
# BKCB/gSB+zCB+AIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgwpJ+
# zzx18kYrBrrdogjJIQb7Y6O8cMqfwJ3upq3ipCUCFCObJX5z1ooaZmAG+pweSlpt
# VkS1GA8yMDIwMDEyMzIwMjAyNFowAwIBHqCBhqSBgzCBgDELMAkGA1UEBhMCVVMx
# HTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRl
# YyBUcnVzdCBOZXR3b3JrMTEwLwYDVQQDEyhTeW1hbnRlYyBTSEEyNTYgVGltZVN0
# YW1waW5nIFNpZ25lciAtIEczoIIKizCCBTgwggQgoAMCAQICEHsFsdRJaFFE98mJ
# 0pwZnRIwDQYJKoZIhvcNAQELBQAwgb0xCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5W
# ZXJpU2lnbiwgSW5jLjEfMB0GA1UECxMWVmVyaVNpZ24gVHJ1c3QgTmV0d29yazE6
# MDgGA1UECxMxKGMpIDIwMDggVmVyaVNpZ24sIEluYy4gLSBGb3IgYXV0aG9yaXpl
# ZCB1c2Ugb25seTE4MDYGA1UEAxMvVmVyaVNpZ24gVW5pdmVyc2FsIFJvb3QgQ2Vy
# dGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTYwMTEyMDAwMDAwWhcNMzEwMTExMjM1
# OTU5WjB3MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRp
# b24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsxKDAmBgNVBAMTH1N5
# bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQC7WZ1ZVU+djHJdGoGi61XzsAGtPHGsMo8Fa4aaJwAyl2pN
# yWQUSym7wtkpuS7sY7Phzz8LVpD4Yht+66YH4t5/Xm1AONSRBudBfHkcy8utG7/Y
# lZHz8O5s+K2WOS5/wSe4eDnFhKXt7a+Hjs6Nx23q0pi1Oh8eOZ3D9Jqo9IThxNF8
# ccYGKbQ/5IMNJsN7CD5N+Qq3M0n/yjvU9bKbS+GImRr1wOkzFNbfx4Dbke7+vJJX
# cnf0zajM/gn1kze+lYhqxdz0sUvUzugJkV+1hHk1inisGTKPI8EyQRtZDqk+scz5
# 1ivvt9jk1R1tETqS9pPJnONI7rtTDtQ2l4Z4xaE3AgMBAAGjggF3MIIBczAOBgNV
# HQ8BAf8EBAMCAQYwEgYDVR0TAQH/BAgwBgEB/wIBADBmBgNVHSAEXzBdMFsGC2CG
# SAGG+EUBBxcDMEwwIwYIKwYBBQUHAgEWF2h0dHBzOi8vZC5zeW1jYi5jb20vY3Bz
# MCUGCCsGAQUFBwICMBkaF2h0dHBzOi8vZC5zeW1jYi5jb20vcnBhMC4GCCsGAQUF
# BwEBBCIwIDAeBggrBgEFBQcwAYYSaHR0cDovL3Muc3ltY2QuY29tMDYGA1UdHwQv
# MC0wK6ApoCeGJWh0dHA6Ly9zLnN5bWNiLmNvbS91bml2ZXJzYWwtcm9vdC5jcmww
# EwYDVR0lBAwwCgYIKwYBBQUHAwgwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRp
# bWVTdGFtcC0yMDQ4LTMwHQYDVR0OBBYEFK9j1sqjToVy4Ke8QfMpojh/gHViMB8G
# A1UdIwQYMBaAFLZ3+mlIR59TEtXC6gcydgfRlwcZMA0GCSqGSIb3DQEBCwUAA4IB
# AQB16rAt1TQZXDJF/g7h1E+meMFv1+rd3E/zociBiPenjxXmQCmt5l30otlWZIRx
# MCrdHmEXZiBWBpgZjV1x8viXvAn9HJFHyeLojQP7zJAv1gpsTjPs1rSTyEyQY0g5
# QCHE3dZuiZg8tZiX6KkGtwnJj1NXQZAv4R5NTtzKEHhsQm7wtsX4YVxS9U72a433
# Snq+8839A9fZ9gOoD+NT9wp17MZ1LqpmhQSZt/gGV+HGDvbor9rsmxgfqrnjOgC/
# zoqUywHbnsc4uw9Sq9HjlANgCk2g/idtFDL8P5dA4b+ZidvkORS92uTTw+orWrOV
# WFUEfcea7CMDjYUq0v+uqWGBMIIFSzCCBDOgAwIBAgIQe9Tlr7rMBz+hASMEIkFN
# EjANBgkqhkiG9w0BAQsFADB3MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50
# ZWMgQ29ycG9yYXRpb24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsx
# KDAmBgNVBAMTH1N5bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwHhcNMTcx
# MjIzMDAwMDAwWhcNMjkwMzIyMjM1OTU5WjCBgDELMAkGA1UEBhMCVVMxHTAbBgNV
# BAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVz
# dCBOZXR3b3JrMTEwLwYDVQQDEyhTeW1hbnRlYyBTSEEyNTYgVGltZVN0YW1waW5n
# IFNpZ25lciAtIEczMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArw6K
# qvjcv2l7VBdxRwm9jTyB+HQVd2eQnP3eTgKeS3b25TY+ZdUkIG0w+d0dg+k/J0oz
# Tm0WiuSNQI0iqr6nCxvSB7Y8tRokKPgbclE9yAmIJgg6+fpDI3VHcAyzX1uPCB1y
# SFdlTa8CPED39N0yOJM/5Sym81kjy4DeE035EMmqChhsVWFX0fECLMS1q/JsI9Kf
# DQ8ZbK2FYmn9ToXBilIxq1vYyXRS41dsIr9Vf2/KBqs/SrcidmXs7DbylpWBJiz9
# u5iqATjTryVAmwlT8ClXhVhe6oVIQSGH5d600yaye0BTWHmOUjEGTZQDRcTOPAPs
# twDyOiLFtG/l77CKmwIDAQABo4IBxzCCAcMwDAYDVR0TAQH/BAIwADBmBgNVHSAE
# XzBdMFsGC2CGSAGG+EUBBxcDMEwwIwYIKwYBBQUHAgEWF2h0dHBzOi8vZC5zeW1j
# Yi5jb20vY3BzMCUGCCsGAQUFBwICMBkaF2h0dHBzOi8vZC5zeW1jYi5jb20vcnBh
# MEAGA1UdHwQ5MDcwNaAzoDGGL2h0dHA6Ly90cy1jcmwud3Muc3ltYW50ZWMuY29t
# L3NoYTI1Ni10c3MtY2EuY3JsMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1Ud
# DwEB/wQEAwIHgDB3BggrBgEFBQcBAQRrMGkwKgYIKwYBBQUHMAGGHmh0dHA6Ly90
# cy1vY3NwLndzLnN5bWFudGVjLmNvbTA7BggrBgEFBQcwAoYvaHR0cDovL3RzLWFp
# YS53cy5zeW1hbnRlYy5jb20vc2hhMjU2LXRzcy1jYS5jZXIwKAYDVR0RBCEwH6Qd
# MBsxGTAXBgNVBAMTEFRpbWVTdGFtcC0yMDQ4LTYwHQYDVR0OBBYEFKUTAamfhcwb
# bhYeXzsxqnk2AHsdMB8GA1UdIwQYMBaAFK9j1sqjToVy4Ke8QfMpojh/gHViMA0G
# CSqGSIb3DQEBCwUAA4IBAQBGnq/wuKJfoplIz6gnSyHNsrmmcnBjL+NVKXs5Rk7n
# fmUGWIu8V4qSDQjYELo2JPoKe/s702K/SpQV5oLbilRt/yj+Z89xP+YzCdmiWRD0
# Hkr+Zcze1GvjUil1AEorpczLm+ipTfe0F1mSQcO3P4bm9sB/RDxGXBda46Q71Wkm
# 1SF94YBnfmKst04uFZrlnCOvWxHqcalB+Q15OKmhDc+0sdo+mnrHIsV0zd9HCYbE
# /JElshuW6YUI6N3qdGBuYKVWeg3IRFjc5vlIFJ7lv94AvXexmBRyFCTfxxEsHwA/
# w0sUxmcczB4Go5BfXFSLPuMzW4IPxbeGAk5xn+lmRT92MYICWjCCAlYCAQEwgYsw
# dzELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8w
# HQYDVQQLExZTeW1hbnRlYyBUcnVzdCBOZXR3b3JrMSgwJgYDVQQDEx9TeW1hbnRl
# YyBTSEEyNTYgVGltZVN0YW1waW5nIENBAhB71OWvuswHP6EBIwQiQU0SMAsGCWCG
# SAFlAwQCAaCBpDAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcN
# AQkFMQ8XDTIwMDEyMzIwMjAyNFowLwYJKoZIhvcNAQkEMSIEIOWZZ8TFYGbw7IAx
# Xyr3mWWEibI3ANArl2bVbuOEJ6jJMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMR0
# znYAfQI5Tg2l5N58FMaA+eKCATz+9lPvXbcf32H4MAsGCSqGSIb3DQEBAQSCAQCV
# LxUMn7/2ZHbP+Wwn/JoFjdtKj6YJ32yEQmx+rhZL4NejRvZoTBkz+w9V5ilzMOWJ
# GvstjWRMJAZvJG5eA7kJcqh9Ie5NykTH5QBMieMKaaSsiIa+ZdBzxPFlD74TZ/1j
# YRyuNmSCjmcxRLMvFMikF7qEE4IOCw8YvlebHaBLxYpcSkz140/8gDX4oJbw+Hc5
# qux5iGC+PVhCfMTO/HInjL1xQ7SZMs6nr73iyzLGAXWZqnF4IDv/FKvXuH/zUwjd
# pWdpznXawfO5rzIIGmQForaJtv5mFDokcUdSMkNgLw/wMYkrpF060vVYDEcD0N3I
# 0kVcgBNEkOWgONe7Idvl
# SIG # End signature block
