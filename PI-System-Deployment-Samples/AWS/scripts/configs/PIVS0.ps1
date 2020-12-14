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
    Import-Module SqlServer -RequiredVersion 21.1.18218

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
        [string]$SqlServer = $DefaultSqlServer,
        [string]$VisionDBName = "PIVisionDB",
        [string]$AFServer = $DefaultPIAFServer,
        [string]$PIServer = $DefaultPIDataArchive
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
        Import-DscResource -ModuleName xWindowsUpdate

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
                DependsOn = "[cChocoInstaller]installChoco"
            }

            #2D i. Install .NET Framework 4.8
            xHotFix NETFramework {
                Path = 'C:\media\NETFramework\windows10.0-kb4486129.msu'
                Id = 'KB4486129'
                Ensure = 'Present'
            }
            
            # 2D ii. Reboot to complete .NET installation.
            xPendingReboot RebootNETFramework {
                Name      = 'RebootNETFramework'
                DependsOn = '[xHotFix]NETFramework'
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
                DependsOn = '[xHotFix]NETFramework', '[xPendingReboot]RebootNETFramework'
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

            # We need to do this before modifications that will require this setup.
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

            # 3D iii.Post Install Configuration - Update App Pool service account for Service.
            # Known issue with App Pool failing to start: https://github.com/PowerShell/xWebAdministration/issues/301
            # (Suspect passwords with double quote characters break this resource with version 1.18.0.0.)
            xWebAppPool PIVisionUtilityAppPool {
                Name         = 'PIVisionUtilityAppPool'
                autoStart    = $true
                startMode    = 'AlwaysRunning'
                identityType = 'SpecificUser'
                Credential   = $serviceAccountCredential
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
# MIIcVgYJKoZIhvcNAQcCoIIcRzCCHEMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDvC2WKY2d9wiW3
# NGvkr71ywq0mvcHvUGvrDhF2SJupI6CCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# Q+9sIKX0AojqBVLFUNQpzelOdjGWNzdcMMSu8p0pNw4xeAbuCEHfMYIRHzCCERsC
# AQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBB
# c3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQBlb6upLHhoprGBiRrHb6WzANBglg
# hkgBZQMEAgEFAKCBnjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgN+KxsyT4v9Du
# 4JTCnPnUp0HPybuBAL01aYHYDbYELYowMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBADgb
# eY+MnMKgzh3HDecJJ6Elp6Vu7Lf7oBwFiCa/4ZjYdz2aoQjkkCPsrA3wT7ksMxBy
# GkB/l5Fj6wdgQEY3OlvgmPSAq3XNo4gEKNvGLRXkI86XPBqmEO5jTWhYzCt4jrnd
# V0Uv+mS3Oo3WiprHBeATenJHxj6AP3s2xKymUIfPBT1x8Kat+BB85+X6F5W/e9FF
# tK5gSI0FPolFuDwMcljKfWN2WWIQcSgEFScXoU79xN87JTbuBgLC7Uqq18hk0uNe
# Dq5a+YOhP06prXMTO/ToT1O0OOOAWwqq21XNRSi9lN4wdb3uzc29jX9xe/QqQcLJ
# OIYtc/85UMnon4nFRzuhgg7IMIIOxAYKKwYBBAGCNwMDATGCDrQwgg6wBgkqhkiG
# 9w0BBwKggg6hMIIOnQIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEE
# oGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQgbcZvjA4bDksK
# S2yCxrr2Yo1wD7272xZTgy90ujJVe8gCECMdwg2vpa/Ud66FFMxe4AsYDzIwMjAx
# MTExMTcyNzI5WqCCC7swggaCMIIFaqADAgECAhAEzT+FaK52xhuw/nFgzKdtMA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0EwHhcNMTkxMDAxMDAwMDAw
# WhcNMzAxMDE3MDAwMDAwWjBMMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xJDAiBgNVBAMTG1RJTUVTVEFNUC1TSEEyNTYtMjAxOS0xMC0xNTCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOlkNZz6qZhlZBvkF9y4KTbM
# ZwlYhU0w4Mn/5Ts8EShQrwcx4l0JGML2iYxpCAQj4HctnRXluOihao7/1K7Sehbv
# +EG1HTl1wc8vp6xFfpRtrAMBmTxiPn56/UWXMbT6t9lCPqdVm99aT1gCqDJpIhO+
# i4Itxpira5u0yfJlEQx0DbLwCJZ0xOiySKKhFKX4+uGJcEQ7je/7pPTDub0ULOsM
# KCclgKsQSxYSYAtpIoxOzcbVsmVZIeB8LBKNcA6Pisrg09ezOXdQ0EIsLnrOnGd6
# OHdUQP9PlQQg1OvIzocUCP4dgN3Q5yt46r8fcMbuQhZTNkWbUxlJYp16ApuVFKMC
# AwEAAaOCAzgwggM0MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMIIBvwYDVR0gBIIBtjCCAbIwggGhBglghkgBhv1s
# BwEwggGSMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BT
# MIIBZAYIKwYBBQUHAgIwggFWHoIBUgBBAG4AeQAgAHUAcwBlACAAbwBmACAAdABo
# AGkAcwAgAEMAZQByAHQAaQBmAGkAYwBhAHQAZQAgAGMAbwBuAHMAdABpAHQAdQB0
# AGUAcwAgAGEAYwBjAGUAcAB0AGEAbgBjAGUAIABvAGYAIAB0AGgAZQAgAEQAaQBn
# AGkAQwBlAHIAdAAgAEMAUAAvAEMAUABTACAAYQBuAGQAIAB0AGgAZQAgAFIAZQBs
# AHkAaQBuAGcAIABQAGEAcgB0AHkAIABBAGcAcgBlAGUAbQBlAG4AdAAgAHcAaABp
# AGMAaAAgAGwAaQBtAGkAdAAgAGwAaQBhAGIAaQBsAGkAdAB5ACAAYQBuAGQAIABh
# AHIAZQAgAGkAbgBjAG8AcgBwAG8AcgBhAHQAZQBkACAAaABlAHIAZQBpAG4AIABi
# AHkAIAByAGUAZgBlAHIAZQBuAGMAZQAuMAsGCWCGSAGG/WwDFTAfBgNVHSMEGDAW
# gBT0tuEgHf4prtLkYaWyoiWyyBc1bjAdBgNVHQ4EFgQUVlMPwcYHp03X2G5XcoBQ
# TOTsnsEwcQYDVR0fBGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNlcnQuY29t
# L3NoYTItYXNzdXJlZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0
# LmNvbS9zaGEyLWFzc3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcwJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcwAoZDaHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJRFRp
# bWVzdGFtcGluZ0NBLmNydDANBgkqhkiG9w0BAQsFAAOCAQEALoOhRAVKBOO5MlL6
# 2YHwGrv4CY0juT3YkqHmRhxKL256PGNuNxejGr9YI7JDnJSDTjkJsCzox+HizO3L
# eWvO3iMBR+2VVIHggHsSsa8Chqk6c2r++J/BjdEhjOQpgsOKC2AAAp0fR8SftApo
# U39aEKb4Iub4U5IxX9iCgy1tE0Kug8EQTqQk9Eec3g8icndcf0/pOZgrV5JE1+9u
# k9lDxwQzY1E3Vp5HBBHDo1hUIdjijlbXST9X/AqfI1579JSN3Z0au996KqbSRaZV
# DI/2TIryls+JRtwxspGQo18zMGBV9fxrMKyh7eRHTjOeZ2ootU3C7VuXgvjLqQhs
# Uwm09zCCBTEwggQZoAMCAQICEAqhJdbWMht+QeQF2jaXwhUwDQYJKoZIhvcNAQEL
# BQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UE
# CxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJ
# RCBSb290IENBMB4XDTE2MDEwNzEyMDAwMFoXDTMxMDEwNzEyMDAwMFowcjELMAkG
# A1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRp
# Z2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIFRp
# bWVzdGFtcGluZyBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAL3Q
# Mu5LzY9/3am6gpnFOVQoV7YjSsQOB0UzURB90Pl9TWh+57ag9I2ziOSXv2MhkJi/
# E7xX08PhfgjWahQAOPcuHjvuzKb2Mln+X2U/4Jvr40ZHBhpVfgsnfsCi9aDg3iI/
# Dv9+lfvzo7oiPhisEeTwmQNtO4V8CdPuXciaC1TjqAlxa+DPIhAPdc9xck4Krd9A
# Oly3UeGheRTGTSQjMF287DxgaqwvB8z98OpH2YhQXv1mblZhJymJhFHmgudGUP2U
# Kiyn5HU+upgPhH+fMRTWrdXyZMt7HgXQhBlyF/EXBu89zdZN7wZC/aJTKk+FHcQd
# PK/P2qwQ9d2srOlW/5MCAwEAAaOCAc4wggHKMB0GA1UdDgQWBBT0tuEgHf4prtLk
# YaWyoiWyyBc1bjAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzASBgNV
# HRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEF
# BQcDCDB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRp
# Z2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHoweDA6oDig
# NoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNybDBQBgNVHSAESTBHMDgGCmCGSAGG/WwAAgQwKjAo
# BggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzALBglghkgB
# hv1sBwEwDQYJKoZIhvcNAQELBQADggEBAHGVEulRh1Zpze/d2nyqY3qzeM8GN0CE
# 70uEv8rPAwL9xafDDiBCLK938ysfDCFaKrcFNB1qrpn4J6JmvwmqYN92pDqTD/iy
# 0dh8GWLoXoIlHsS6HHssIeLWWywUNUMEaLLbdQLgcseY1jxk5R9IEBhfiThhTWJG
# JIdjjJFSLK8pieV4H9YLFKWA1xJHcLN11ZOFk362kmf7U2GJqPVrlsD0WGkNfMgB
# sbkodbeZY4UijGHKeZR+WfyMD+NvtQEmtmyl7odRIeRYYJu6DC0rbaLEfrvEJStH
# Agh8Sa4TtuF8QkIoxhhWz0E0tmZdtnR79VYzIi8iNrJLokqV2PWmjlIxggJNMIIC
# SQIBATCBhjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkw
# FwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEy
# IEFzc3VyZWQgSUQgVGltZXN0YW1waW5nIENBAhAEzT+FaK52xhuw/nFgzKdtMA0G
# CWCGSAFlAwQCAQUAoIGYMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAcBgkq
# hkiG9w0BCQUxDxcNMjAxMTExMTcyNzI5WjArBgsqhkiG9w0BCRACDDEcMBowGDAW
# BBQDJb1QXtqWMC3CL0+gHkwovig0xTAvBgkqhkiG9w0BCQQxIgQgShThgNdO0bz5
# 2iON36nDEqfQW6Z979G1s0/vNOPB6QgwDQYJKoZIhvcNAQEBBQAEggEAf22wEMfe
# nVUJDzujig8iVVtFsXgsuDFvKlyu78UPOK4qDalXcOykxXuMn4GdHf2BhSKUKoc6
# 1MrHg9rF8pGkhWsicVSOMLDzTnNRVK0qYHpCjmMCGvGZaKzXJi+O02L2I0SgkkG2
# SVoK4XKMY34jpMjzaZwgzrFSdbr9K7ly4pUYPm5qJ1/IRT70N/YTKuVmzH4cIRnb
# 7hxDjvw4HBcEuWbCX1Tj6bzBiTvStq+ncNL/t1Mnz4kXUHJyN/pqbU07hwjplSHv
# ftYI41/bXCk9FRDukh9Kz6UnUeyoVvNqu3kEMu5lZq8YFFFUNqr1lKQhmUtZAym6
# XePbvS/a3cnsAA==
# SIG # End signature block
