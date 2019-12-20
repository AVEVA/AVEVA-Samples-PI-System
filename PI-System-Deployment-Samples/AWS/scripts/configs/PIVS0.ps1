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
# MIIbzAYJKoZIhvcNAQcCoIIbvTCCG7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBBjFYbu57/t2mS
# mDt2DTmzO/JM1GklUjUG7EBEV23mWKCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEICY0lYDV+0vG
# BsPBdbdokTx46KjWWB6vcVl/An+y8e6YMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQAo
# rHcK85e4uaD+8VrhDiqI90JwmvrhMFSgTmU6tmH1GKf6YfP6qxFVnwBVZ2IdaPmn
# fV6citb1J53r0LDbM8Ju/p3Pbwfm/qI6BmgcP0pPnIO9cLxxw87s9hgk9Kgu0zBu
# pQ4mxlsT9JCUfzjDAP1awzmO+d5/pWUX2zfqnyBBHZH0KlRSgJ/oo7AOLraM70QM
# 3fyoYVTi4XQOJtBnmq6UINYS3qCzrLUQXpiv9P7biDtLTtxx3yUlbaY2VFLrneWO
# VUlV1OxRKGFBVGp8bvjklfGh5szYKJHooKVBWBG1Jzd+FnqhmIe7M6EULbgCYi18
# XSw0skkrAcl3wiZx/gdNoYIOPTCCDjkGCisGAQQBgjcDAwExgg4pMIIOJQYJKoZI
# hvcNAQcCoIIOFjCCDhICAQMxDTALBglghkgBZQMEAgEwggEPBgsqhkiG9w0BCRAB
# BKCB/wSB/DCB+QIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgXyu2
# 9yIIjUgnStfnL6lNixLv7qpylxvJ1rY1eU9NIskCFQDLWT53TcyuFZSQnX3t8vQj
# PghGFhgPMjAxOTA4MDgxNDU3NTNaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
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
# DQEJBTEPFw0xOTA4MDgxNDU3NTNaMC8GCSqGSIb3DQEJBDEiBCAcp8Ve8TFzoTZW
# dX8NB2x3LBBTbAX0DveSjKFF7+2r2TA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# C7RLPs0fZ98HsUCNW5hxx0uHk6Es7o3GD2R1ldgS3BRQo4vGpJjSg/k1Wcg0eCDl
# NK0dGKjV7UP/F6g99BOnkfRuMgQaGhVGnfx3HcfSK/xkpEXjKR15oEBoWNdXxLs1
# hRciFgC0Wub5Q/xwJkB5gK2R6hHrZZrtDhWeOvAWoqsOY46E6z8rRgI+JBMcoTr2
# p/CBYVD7Bz62oGUdOZKGhCj7aSleGwNwNexKOxVKfTgGnGLVXZsgsSSGhGFPPTb2
# xKc2rAwxIuEDske1CikaRemZTk1XzlIVSBypN/o/3I2ph59iI/S3M+QByp7TPEcV
# 1b1MFXo56xKVYxaKINEYPg==
# SIG # End signature block
