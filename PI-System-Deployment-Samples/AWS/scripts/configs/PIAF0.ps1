[CmdletBinding()]
param(
    # Domain Net BIOS Name, e.g. 'mypi'.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainNetBiosName,

    # "Fully qualified domain name (FQDN) of the forest root domain e.g. mypi.int"
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DomainDNSName,

    # Username of domain admin account. Also the AWS SSM Parameter Store parameter name. Used to retrieve the account password.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainAdminUserName,
    
    # AF Server service account name. Also the AWS SSM Parameter Store parameter name. Used to retrieve the account password.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIAFServiceAccountName,

    # Default PI Data Archive
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DefaultPIDataArchive,

    # Setup Kit PI Installer Product ID
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$SetupKitsS3PIProductID,

    # Default AF Server
    [Parameter()]
    [ValidateNotNullorEmpty()]
    [String]$DefaultPIAFServer = $env:COMPUTERNAME,

    # Name used to identify AF load balanced endpoint for HA deployments. Used to create DNS CName record.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$AFLoadBalancedName = 'PIAF',

    # SQL Server to install PIFD database. This should be the primary SQL server hostname.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DefaultSqlServer,

    # SQL Server Always On Listener.
    [Parameter()]
    [ValidateNotNullorEmpty()]
    [String]$SqlServerAOListener = 'AG0-Listener',

    # Primary domain controller targeted for service account creation.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PrimaryDomainController,

    # DNS record of internal Elastic Load Balancer. Used for AF HA endpoint.
    [Parameter()]
    $ElasticLoadBalancerDnsRecord,

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix
)


try {
    # Set to enable catch to Write-AWSQuickStartException
    $ErrorActionPreference = "Stop"

    Import-Module $psscriptroot\IPHelper.psm1
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
    Set-DscLocalConfigurationManager -Path .\LCMConfig


    # Set Configuration Data. Certificate used for credential encryption.
    $ConfigurationData = @{
        AllNodes = @(
            @{
                NodeName             = $env:COMPUTERNAME
                CertificateFile      = 'C:\dsc.cer'
                PSDscAllowDomainUser = $true
            }
        )
    }

    # Get exisitng service account password from AWS System Manager Parameter Store.
    $DomainAdminPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$DomainAdminUserName" -WithDecryption $True).Parameters[0].Value
	$PIAFServiceAccountPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$PIAFServiceAccountName" -WithDecryption $True).Parameters[0].Value

    # Generate credential object for domain admin account.
    $secureDomainAdminPassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $domainCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$DomainAdminUserName", $secureDomainAdminPassword)


    # EC2 Configuration
    Configuration PIAF0Config {

        param(
            # PI AF Server Install settings
            [string]$afServer = $env:COMPUTERNAME,
            [string]$piServer = $DefaultPIDataArchive,
            [string]$PIHOME = 'F:\Program Files (x86)\PIPC',
            [string]$PIHOME64 = 'F:\Program Files\PIPC',
            [string]$PI_INSTALLDIR = 'F:\PI',
            [string]$PIAFSvcAccountUsername = $PIAFServiceAccountName,
            [string]$PIAFSvcAccountPassword = $PIAFServiceAccountPassword,
            [string]$PIAFSqlDB = "PIFD"
        )

        Import-DscResource -ModuleName PSDesiredStateConfiguration
        Import-DscResource -ModuleName xStorage -ModuleVersion 3.4.0.0
        Import-DscResource -ModuleName xNetworking -ModuleVersion 5.7.0.0
        Import-DscResource -ModuleName xPendingReboot -ModuleVersion 0.4.0.0
        Import-DscResource -ModuleName xActiveDirectory -ModuleVersion 3.0.0.0
        Import-DscResource -ModuleName xDnsServer -ModuleVersion 1.15.0.0
        Import-DscResource -ModuleName SqlServerDsc -ModuleVersion 13.2.0.0
        Import-DscResource -ModuleName xWindowsUpdate

        # Generate credential for AF Server service account.
        $securePIAFServiceAccountPassword = ConvertTo-SecureString $PIAFSvcAccountPassword -AsPlainText -Force
        $domainServiceAccountCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$PIAFSvcAccountUsername", $securePIAFServiceAccountPassword)

        # Under HA deployment scenarios, substitute the primary SQL Server hostname for the SQL Always On Listener Name.
        # This is used in the installation arguments for PI AF. This value gets configured in the AFService.exe.config specifying which SQL instance to connect to.
        if ($ElasticLoadBalancerDnsRecord) {
            Write-Verbose -Message "HA deployment detected. PIAF install will use the following SQL target: $SqlServerAOListener" -Verbose
            $FDSQLDBSERVER = $SqlServerAOListener
        }
        else {
            Write-Verbose -Message "Single instance deployment detected. PIAF install will use the following SQL target: $DefaultSqlServer" -Verbose
            $FDSQLDBSERVER = $DefaultSqlServer
        }

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

            # 1B. Create Rules to open PI AF Ports
            xFirewall PIAFSDKClientFirewallRule {
                Direction   = 'Inbound'
                Name        = 'PI-System-PI-AFSDK-Client-TCP-In'
                DisplayName = 'PI System PI AFSDK Client (TCP-In)'
                Description = 'Inbound rule for PI AFSDK to allow TCP traffic for access to the AF Server.'
                Group       = 'PI Systems'
                Enabled     = 'True'
                Action      = 'Allow'
                Protocol    = 'TCP'
                LocalPort   = '5457'
                Ensure      = 'Present'
            }

            xFirewall PISQLClientFirewallRule {
                Direction   = 'Inbound'
                Name        = 'PI-System-PI-SQL-Client-TCP-In'
                DisplayName = 'PI System PI SQL AF Client (TCP-In)'
                Description = 'Inbound rule for PI SQL for AF Clients to allow TCP traffic for access to the AF Server.'
                Group       = 'PI Systems'
                Enabled     = 'True'
                Action      = 'Allow'
                Protocol    = 'TCP'
                LocalPort   = '5459'
                Ensure      = 'Present'
            }
            #endregion ### 1. VM PREPARATION ###


            #region ### 2. INSTALL AND SETUP ###
            # 2A i. Used for PI AF Service account creation.
            WindowsFeature ADPS {
                Name   = 'RSAT-AD-PowerShell'
                Ensure = 'Present'
            }

            xADUser ServiceAccount_PIAF {
                DomainName                    = $DomainNetBiosName
                UserName                      = $PIAFSvcAccountUsername
                CannotChangePassword          = $true
                Description                   = 'PI AF Server service account.'
                DomainAdministratorCredential = $domainCredential
                Enabled                       = $true
                Ensure                        = 'Present'
                Password                      = $domainServiceAccountCredential
                DomainController              = $PrimaryDomainController
                DependsOn                     = '[WindowsFeature]ADPS'
            }

            # 2A ii - To have the PI AF SQL Database work with SQL Always On, we use a domain group "AFSERVERS" instead of a local group.
            # This requires a modification to the AF Server install scripts per documentation: 
            # This maps the SQL User 'AFServers' maps to this domain group instead of the local group, providing security mapping consistency across SQL nodes.
            xADGroup CreateAFServersGroup {
                GroupName        = 'AFServers'
                Description      = 'Service Accounts with Access to PIFD databases'
                Category         = 'Security'
                Ensure           = 'Present'
                GroupScope       = 'Global'
                MembersToInclude = $PIAFSvcAccountUsername
                Credential       = $domainCredential
                DomainController = $PrimaryDomainController
                DependsOn        = '[WindowsFeature]ADPS'
            }

            # If a load balancer DNS record is passed, then this will generate a DNS CName. This entry is used as the AF Server load balanced endpoint.
            if ($ElasticLoadBalancerDnsRecord) {
                # Tools needed to write DNS Records
                WindowsFeature DNSTools {
                    Name   = 'RSAT-DNS-Server'
                    Ensure = 'Present'
                }

                # Adds a CName DSN record used to point to internal Elastic Load Balancer DNS record
                xDnsRecord AFLoadBanacedEndPoint {
                    Name                 = 'PIAF'
                    Target               = $ElasticLoadBalancerDnsRecord
                    Type                 = 'CName'
                    Zone                 = $DomainDNSName
                    DependsOn            = '[WindowsFeature]DnsTools'
                    DnsServer            = $PrimaryDomainController
                    Ensure               = 'Present'
                    PsDscRunAsCredential = $domainCredential
                }
            }

            #2B. Install .NET Framework 4.8
            xHotFix NETFramework {
                Path = 'C:\media\NETFramework\windows10.0-kb4486129.msu'
                Id = 'KB4486129'
                Ensure = 'Present'
            }
            
            # 2C. Initiate any outstanding reboots.
            xPendingReboot RebootNETFramework {
                Name      = 'PostNETFrameworkInstall'
                DependsOn = '[xHotFix]NETFramework'
            }

            #2D. Install PI AF Server with Client Tools
            Package PISystem {
                Name                 = 'PI Server 2018 Installer'
                Path                 = 'C:\media\PIServer\PIServerInstaller.exe'
                ProductId            = $SetupKitsS3PIProductID
                Arguments            = "/silent ADDLOCAL=FD_SQLServer,FD_SQLScriptExecution,FD_AppsServer,FD_AFExplorer,FD_AFAnalysisMgmt,FD_AFDocs,PiPowerShell PIHOME=""$PIHOME"" PIHOME64=""$PIHOME64"" AFSERVER=""$afServer"" PISERVER=""$piServer"" SENDTELEMETRY=""0"" AFSERVICEACCOUNT=""$DomainNetBiosName\$PIAFSvcAccountUsername"" AFSERVICEPASSWORD=""$PIAFServiceAccountPassword"" FDSQLDBNAME=""PIFD"" FDSQLDBSERVER=""$FDSQLDBSERVER"" AFACKNOWLEDGEBACKUP=""1"" PI_ARCHIVESIZE=""1024"""
                Ensure               = 'Present'
                LogPath              = "$env:ProgramData\PISystem_install.log"
                PsDscRunAsCredential = $domainCredential   # Cred with access to SQL. Necessary for PIFD database install.
                ReturnCode           = 0, 3010
                DependsOn            = '[xHotFix]NETFramework', '[xPendingReboot]RebootNETFramework'
            }

            # This updates the AFSerers user in SQL from a local group to the domain group
            Script UpdateAFServersUser {
                GetScript            = {
                    return @{
                        'Resource' = 'UpdateAFServersUser'
                    }
                }

                # Forces SetScript execution everytime
                TestScript           = {
                    return $false
                }

                SetScript            = {
                    Write-Verbose -Message "Setting Server account to remove for existing AFServers role: ""serverAccount=$using:DefaultSqlServer\AFServers"""
                    Write-Verbose -Message "Setting Domain account to set for AFServers role:             ""domainAccount=[$using:DomainNetBIOSName\AFServers]"""

                    # Arguments to pass as a variable to SQL script. These are the account to remove and the one to update with.
                    $accounts = "domainAccount=[$using:DomainNetBIOSName\AFServers]", "serverAccount=$using:DefaultSqlServer\AFServers"
                    
                    Write-Verbose -Message "Executing SQL command to invoke script 'c:\media\PIAF\UpdateAFServersUser.sql' to update AFServers user on SQL Server ""$using:DefaultSqlServer"""
                    Invoke-Sqlcmd -InputFile 'c:\media\PIAF\UpdateAFServersUser.sql' -Variable $accounts -Serverinstance $using:DefaultSqlServer -Verbose -ErrorAction Stop
                }
                DependsOn            = '[Package]PISystem'
                PsDscRunAsCredential = $domainCredential   # Cred with access to SQL. Necessary for alter SQL settings.
            }

            # If a load balancer DNS record is passed, then will initiate replication of PIFD to SQL Secondary.
            if ($ElasticLoadBalancerDnsRecord) {

                # Required when placed in an AG
                SqlDatabaseRecoveryModel PIFD {
                    InstanceName         = 'MSSQLServer'
                    Name                 = 'PIFD'
                    RecoveryModel        = 'Full'
                    ServerName           = $DefaultSqlServer
                    PsDscRunAsCredential = $domainCredential
                    DependsOn            = '[Package]PISystem'
                }

                # Adds PIFD to AG and replicas to secondary SQL Server.
                SqlAGDatabase AddPIDatabaseReplicas {
                    AvailabilityGroupName = 'SQLAG0'
                    BackupPath            = "\\$DefaultSqlServer\Backup"
                    DatabaseName          = $PIAFSqlDB
                    InstanceName          = 'MSSQLSERVER'
                    ServerName            = $DefaultSqlServer
                    Ensure                = 'Present'
                    PsDscRunAsCredential  = $domainCredential
                    DependsOn             = '[Package]PISystem', '[SqlDatabaseRecoveryModel]PIFD'
                }

                # Script resource to rename the AF Server so that it takes on the Load Balanced endpoint name.
                # This is necessary so PI Vision web.config can point to AF load balanced endpoint whose AF Server name must match the AF LB DNS name.
                Script RenameAfServer {
                    GetScript            = {
                        return @{
                            Value = 'RenameAfServer'
                        }
                    }

                    # Tests whether the default AF Server's name already matches the load balancer name.
                    TestScript           = {
                        try {
                            $afServerName = (Get-AfServer -Default -ErrorAction Stop -Verbose | Connect-AFServer -ErrorAction Stop -Verbose).Name
                            if ($afServerName -eq $using:AFLoadBalancedName) {
                                Write-Verbose -Message "AF Server name '$afServerName' already matches AF load balancer name '$($using:AFLoadBalancedName)'. Skipping RenameAfServer." -Verbose
                                return $true
                            }
                            else {
                                Write-Verbose -Message "AF Server name '$afServerName' does NOT matches AF load balancer name '$($using:AFLoadBalancedName)'. Executing RenameAfServer." -Verbose
                                return $false
                            }
                        }

                        catch {
                            Write-Error $_
                            throw 'Failed to test AF Server with AF load balancer name.'
                        }
                    }

                    SetScript            = {
                        Try {
                            $VerbosePreference = $using:VerbosePreference

                            # Load assemblies necessary to use AFSDK
                            $null = [System.Reflection.Assembly]::LoadWithPartialName('OSIsoft.AFSDKCommon')
                            $null = [System.Reflection.Assembly]::LoadWithPartialName('OSIsoft.AFSDK')

                            # Create AF Server object.
                            $PISystems = New-Object -TypeName OSIsoft.AF.PISystems -Verbose
                            Write-Verbose -Message "New PISystem object created. Default PISystem: '$($PISystems.DefaultPISystem.Name)'" -Verbose

                            # Connect to AF Server.
                            $AfServerConnection = $PISystems.Item($($PISystems.DefaultPISystem.Name))
                            Write-Verbose -Message "OLD AF Server Name: '$($AfServerConnection.Name)'" -Verbose

                            # Rename AF Server. Must happen while connected to AF Server.
                            $AfServerConnection.PISystem.Name = $($using:AFLoadBalancedName)
                            Write-Verbose -Message "NEW AF Server Name: '$($AfServerConnection.Name)'" -Verbose

                            # Apply and CheckIn. The change should take effect immediately from line above, but applied for good measure.
                            $AfServerConnection.ApplyChanges()
                            $AfServerConnection.CheckIn()
                        }

                        Catch {
                            Write-Error $_
                            throw 'Failed to rename AF Server.'
                        }
                    }
                    # NB - Must use PsDscRunAsCredential and not Credential to execute under correct context and privileges.
                    PsDscRunAsCredential = $domainCredential
                }
            }

            # 2C. Set AFSERVER SPN on service account.
			xADServicePrincipalName 'SPN01'
			{
				ServicePrincipalName = $("AFSERVER/" + $env:COMPUTERNAME)
				Account              = $PIAFSvcAccountUsername 
				PsDscRunAsCredential = $domainCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}
			xADServicePrincipalName 'SPN02'
			{
				ServicePrincipalName = $("AFSERVER/" + $env:COMPUTERNAME + "." + $DomainDNSName)
				Account              = $PIAFSvcAccountUsername 
				PsDscRunAsCredential = $domainCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}

			if($ElasticLoadBalancerDnsRecord){
				xADServicePrincipalName 'SPN03'
				{
					ServicePrincipalName = $("HTTP/" + $AFLoadBalancedName)
					Account              = $PIAFSvcAccountUsername 
					PsDscRunAsCredential = $domainCredential
 					DependsOn			 = '[WindowsFeature]ADPS'
				}
				xADServicePrincipalName 'SPN04'
				{
					ServicePrincipalName = $("HTTP/" + $AFLoadBalancedName + "." + $DomainDNSName)
					Account              = $PIAFSvcAccountUsername 
					PsDscRunAsCredential = $domainCredential
 					DependsOn			 = '[WindowsFeature]ADPS'
				}
			}

            # 2E. Initiate any outstanding reboots.
            xPendingReboot RebootPISystem {
                Name      = 'PostPIInstall'
                DependsOn = '[Package]PISystem'
            }
            #endregion ### 2. INSTALL AND SETUP ###
			
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
                DependsOn  = '[Package]PISystem'
            }
            #endregion Set firewall rules ###

            #region ### 4. SIGNAL WAITCONDITION ###

            # Writes output to the AWS CloudFormation Init Wait Handle (Indicating script completed)
            # To ensure it triggers only at the end of the script, set DependsOn to include all resources.
            Script Write-AWSQuickStartStatus {
                GetScript  = {@( Value = 'WriteAWSQuickStartStatus' )}
                TestScript = {$false}
                SetScript  = {

                    # Ping WaitHandle to increment Count and indicate DSC has completed.
                    # Note: Manually passing a unique ID (used DSC Configuation ane 'pida0config') to register as a unique signal. See Ref for details.
                    # Ref: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-signal.html
                    Write-Verbose "Getting Handle" -Verbose
                    $handle = Get-AWSQuickStartWaitHandle -ErrorAction SilentlyContinue
                    Invoke-Expression "cfn-signal.exe -e 0 -i 'piaf0config' '$handle'"

                    # Write to Application Log to record status update.
                    $CheckSource = Get-EventLog -LogName Application -Source AWSQuickStartStatus -ErrorAction SilentlyContinue
                    if (!$CheckSource) {New-EventLog -LogName Application -Source 'AWSQuickStartStatus' -Verbose}  # Check for source to avoid throwing exception if already present.
                    Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message "Write-AWSQuickStartStatus function was triggered."
                }
                DependsOn  = '[xFirewall]PIAFSDKClientFirewallRule', '[xFirewall]PISQLClientFirewallRule', '[WindowsFeature]ADPS', '[xADUser]ServiceAccount_PIAF', '[Package]PISystem', '[xPendingReboot]RebootPISystem'
            }
            #endregion ### 4. SIGNAL WAITCONDITION ###
        }
    }

    # Compile and Execute Configuration
    PIAF0Config -ConfigurationData $ConfigurationData
    Start-DscConfiguration -Path .\PIAF0Config -Wait -Verbose -Force -ErrorVariable ev
}

catch {
    # If any expectations are thrown, output to CloudFormation Init.
    $_ | Write-AWSQuickStartException
}
# SIG # Begin signature block
# MIIbzAYJKoZIhvcNAQcCoIIbvTCCG7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDPlrbIYfdnpO7l
# QZggDbHne1qMl6ozYNQlNLtzlwfHuqCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIGUOZUKpC6Qu
# B6UJ8D27giqgK5xpBuala2e3WwOl277IMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQA9
# iRAWjbU8TJBYJDFjWHUG5xR4jKWUYOx3QtDbSTCwHzvEGABdc214kW1V0PvX1ER7
# cleQIX36TOHWt6Dnj2kOYayA2qU5aX5FdmXAZM8k5znwDk+IuKRimLaQzs97CmGi
# 7EVs/Avq14ZiC69RTS355j8mCQsdWtHwcJ4W2EDKg8Lt96/cVTFgWzcoNT/NTKwW
# vsfAiD7ju/CzK8zZe6w6WxkcHf714a118fUh4mYz7XAtUPc3COpO7AuMfeWl7OgV
# QOkKHrMiArVlzv+dDgu6a0IRnr5deYlzOxsolp96kA4ffb3P/Mm+Awk2H/Ob6rM8
# s1qyWkJ2H90MuazA704goYIOPTCCDjkGCisGAQQBgjcDAwExgg4pMIIOJQYJKoZI
# hvcNAQcCoIIOFjCCDhICAQMxDTALBglghkgBZQMEAgEwggEPBgsqhkiG9w0BCRAB
# BKCB/wSB/DCB+QIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQg3cJW
# pyGswn5opOqr+CtvASSpu4QyIJnXK1oNS2qLreACFQDseSQ8lQ+p8JoBShLkCJ66
# GL2KMRgPMjAxOTA4MDgxNDU3NTBaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
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
# DQEJBTEPFw0xOTA4MDgxNDU3NTBaMC8GCSqGSIb3DQEJBDEiBCD9zn1PSVbP1E4V
# bdQ1Ro4yhEsP0r/Bx9+LhPVwmmMEOjA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# fBixUjyOmszsYA89BU/A4JWBR1AYs89USOcmf/HI2635PTtxkCQZAXjF5o/fy7pU
# 2txdKJSbzqBa+8XLdSh34i4c6J+CJpyDj7xVFKbdIFKC1hnWR+9TZH7x5gpuarqL
# Yc4mput3lZG6q2LtzQsh7zK4agUxzlrPY7npGCf1Y1kgYaea8rf9DoJKuJM7uVUz
# Jq2ymcTf3d8dJ4GoNjGgsUKDZVPLt2Jf/zA6N8QOzUK9kALrvjs/a9PwvGhoS+hd
# RUOU3QFFvXITmeZg+LY6k79lBhsyOoxKyJJe+fs2mckgNQCW/oE2Zl2/gsjF7XuK
# xonGfqTwU8LYypxDv3joIA==
# SIG # End signature block
