    Configuration PIAF {
        param(
        # Used to run installs. Account must have rights to AD and SQL to conduct successful installs/configs.
        [Parameter(Mandatory)]
        [pscredential]$runAsCredential,

        # Service account used to run AF Server.
        [pscredential]$svcCredential,

        # PI AF Server Install settings
		[string]$PIPath,
		[string]$PIProductID,
        [string]$afServer = $env:COMPUTERNAME,
        [string]$piServer,
        [string]$PIHOME = 'F:\Program Files (x86)\PIPC',
        [string]$PIHOME64 = 'F:\Program Files\PIPC',
        [string]$PI_INSTALLDIR = 'F:\PI',
        [string]$PIAFSqlDB = 'PIFD',

        # SQL Server to install PIFD database. This should be the primary SQL server hostname.
        [Parameter(Mandatory)]
        [string]$DefaultSqlServer,

        # Switch to indicate highly available deployment
        [Parameter(Mandatory)]
        [string]$deployHA,

        [Parameter(Mandatory)]
        [string]$OSIsoftTelemetry,

        # AF server names
        [string]$AFPrimary,
        [string]$AFSecondary,

        # SQL Server Always On Listener.
        [string]$SqlServerAOListener = 'AG0-Listener',

        # SQL Server Always On Availability Group Name
        [string]$namePrefix,
        [string]$nameSuffix,
        [string]$sqlAlwaysOnAvailabilityGroupName = ($namePrefix+'-sqlag'+$nameSuffix),

        # Name of the primary domain controller used to create load balancer ARecord in HA deployment
        [string]$PrimaryDC = ($namePrefix+'-dc-vm'+$nameSuffix),

        # The two SQL servers in the SQL Always on Availability Group (note: $SQLSecondary should be owner of AG)
        [string]$SQLPrimary,
        [string]$SQLSecondary,

        # Name used to identify AF load balanced endpoint for HA deployments. Used to create DNS CName record.
        [string]$AFLoadBalancedName = 'PIAF',
        [string]$AFLoadBalancerIP
        )

        Import-DscResource -ModuleName PSDesiredStateConfiguration
        Import-DscResource -ModuleName xStorage
        Import-DscResource -ModuleName xNetworking
        Import-DscResource -ModuleName xPendingReboot
        Import-DscResource -ModuleName xActiveDirectory
        Import-DscResource -ModuleName xDnsServer
        Import-DscResource -ModuleName SqlServerDsc
		Import-DscResource -ModuleName cchoco

        # Under HA deployment scenarios, substitute the primary SQL Server hostname for the SQL Always On Listener Name.
        # This is used in the installation arguments for PI AF. This value gets configured in the AFService.exe.config specifying which SQL instance to connect to.
        if($deployHA -eq "true"){
            Write-Verbose -Message "HA deployment detected. PIAF install will use the following SQL target: $SqlServerAOListener" -Verbose
            $FDSQLDBSERVER = $SqlServerAOListener
        } else {
            Write-Verbose -Message "Single instance deployment detected. PIAF install will use the following SQL target: $DefaultSqlServer" -Verbose
            $FDSQLDBSERVER = $SQLPrimary
        }
        # Lookup Domain names (FQDN and NetBios). Assumes VM is already domain joined.
        $DomainNetBiosName = ((Get-WmiObject -Class Win32_NTDomain -Filter "DnsForestName = '$((Get-WmiObject -Class Win32_ComputerSystem).Domain)'").DomainName)
        $DomainDNSName = (Get-WmiObject Win32_ComputerSystem).Domain

        # Extracts username only (no domain net bios name) for service acct
        $PIAFSvcAccountUsername = $svcCredential.UserName
        # Create credential with Domain Net Bios Name included.
        $domainSvcCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$($svcCredential.UserName)", $svcCredential.Password)

        # Extracts username only (no domain net bios name) for domain runas account
        $runAsAccountUsername = $runAsCredential.UserName
        # Create credential with Domain Net Bios Name included.
        $domainRunAsCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$($runAsAccountUsername)", $runAsCredential.Password)

        Node localhost {

            # Necessary if reboots are needed during DSC application/program installations
            LocalConfigurationManager
            {
                RebootNodeIfNeeded = $true
            }

            #region ### 1. VM PREPARATION ###
            # Data Disk for Binary Files
            xWaitforDisk Volume_F {
                DiskID           = 2
                retryIntervalSec = 30
                retryCount       = 20
            }
            xDisk Volume_F {
                DiskID      = 2
                DriveLetter = 'F'
                FSFormat    = 'NTFS'
                FSLabel     = 'Apps'
                DependsOn   = '[xWaitforDisk]Volume_F'
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
                DomainAdministratorCredential = $domainRunAsCredential
                Enabled                       = $true
                Ensure                        = 'Present'
                Password                      = $svcCredential
                DependsOn                     = '[WindowsFeature]ADPS'
            }

            # Domain AFServers group created as part of SQL.ps1 DSC, this adds domain AF svc acct to that group
            xADGroup CreateAFServersGroup {
                GroupName   = 'AFServers'
                Description = 'Service Accounts with Access to PIFD databases'
                Category    = 'Security'
                Ensure      = 'Present'
                GroupScope  = 'Global'
                Credential  = $domainRunAsCredential
                MembersToInclude = $PIAFSvcAccountUsername
                DependsOn   = '[WindowsFeature]ADPS'
            }
            
            # If a load balancer DNS record is passed, then this will generate a DNS CName. This entry is used as the AF Server load balanced endpoint.
            if ($deployHA -eq 'true') {
                # Tools needed to write DNS Records
                WindowsFeature DNSTools {
                    Name   = 'RSAT-DNS-Server'
                    Ensure = 'Present'
                }

                # Adds a CName DSN record used to point to internal Elastic Load Balancer DNS record
                xDnsRecord AFLoadBanacedEndPoint {
                    Name                 = $AFLoadBalancedName
                    Target               = $AFLoadBalancerIP
                    Type                 = 'ARecord'
                    Zone                 = $DomainDNSName
                    DnsServer            = $PrimaryDC
                    DependsOn            = '[WindowsFeature]DnsTools'
                    Ensure               = 'Present'
                    PsDscRunAsCredential = $runAsCredential
                }
            }

			# 2B. Installing Chocolatey to facilitate package installs.
			cChocoInstaller installChoco {
				InstallDir = 'C:\ProgramData\chocolatey'
			}

			# 2C. Install .NET Framework 4.8
			cChocoPackageInstaller 'dotnetfx' {
				Name = 'dotnetfx'
				DependsOn = "[cChocoInstaller]installChoco"
			}

            xPendingReboot RebootDotNet {
                Name      = 'RebootDotNet'
                DependsOn = '[cChocoPackageInstaller]dotnetfx'
            }

            # 2D. Install PI AF Server with Client Tools
            Package PISystem {
                Name                 = 'PI Server 2018 Installer'
                Path                 = $PIPath
                ProductId            = $PIProductID
                Arguments            = "/silent ADDLOCAL=FD_SQLServer,FD_SQLScriptExecution,FD_AppsServer,FD_AFExplorer,FD_AFAnalysisMgmt,FD_AFDocs,PiPowerShell PIHOME=""$PIHOME"" PIHOME64=""$PIHOME64"" AFSERVER=""$afServer"" PISERVER=""$piServer"" SENDTELEMETRY=""$OSIsoftTelemetry"" AFSERVICEACCOUNT=""$($domainSvcCredential.username)"" AFSERVICEPASSWORD=""$($domainSvcCredential.GetNetworkCredential().Password)"" FDSQLDBNAME=""$PIAFSqlDB"" FDSQLDBSERVER=""$FDSQLDBSERVER"" AFACKNOWLEDGEBACKUP=""1"" PI_ARCHIVESIZE=""1024"""
                Ensure               = 'Present'
                PsDscRunAsCredential = $domainRunAsCredential   # Cred with access to SQL. Necessary for PIFD database install.
                ReturnCode           = 0, 3010, 1641
                DependsOn            = '[xDisk]Volume_F', '[xPendingReboot]RebootDotNet'
            }

            # This updates the AFServers user in SQL from a local group to the domain group
            if ($env:COMPUTERNAME -eq $AFPrimary) {
                Script UpdateAFServersUser {
                    GetScript = {
                        return @{
                            'Resource' = 'UpdateAFServersUser'
                        }
                    }
                    # Forces SetScript execution every time
                    TestScript = {
                        return $false
                    }

                    SetScript  = {
                        Write-Verbose -Message "Setting Server account to remove for existing AFServers role: ""serverAccount=$using:SQLPrimary\AFServers"""
                        Write-Verbose -Message "Setting Domain account to set for AFServers role:             ""domainAccount=[$using:DomainNetBIOSName\AFServers]"""

                        # Arguments to pass as a variable to SQL script. These are the account to remove and the one to update with.
                        $accounts = "domainAccount=[$using:DomainNetBIOSName\AFServers]","serverAccount=$using:SQLPrimary\AFServers"

                        Write-Verbose -Message "Executing SQL command to invoke script 'c:\UpdateAFServersUser.sql' to update AFServers user on SQL Server ""$using:SQLPrimary"""
                        Invoke-Sqlcmd -InputFile 'D:\UpdateAFServersUser.sql' -Variable $accounts -Serverinstance $using:SQLPrimary -Verbose -ErrorAction Stop

                    }
                    DependsOn = '[Package]PISystem'
                    PsDscRunAsCredential = $domainRunAsCredential   # Cred with access to SQL. Necessary for alter SQL settings.
                }
            }

            # If a load balancer DNS record is passed, then will initiate replication of PIFD to SQL Secondary.
            if($deployHA -eq 'true' -and $env:COMPUTERNAME -eq $AFPrimary){

                # Required when placed in an AG
                SqlDatabaseRecoveryModel PIFD {
                    InstanceName          = 'MSSQLServer'
                    Name                  = $PIAFSqlDB
                    RecoveryModel         = 'Full'
                    ServerName            = $DefaultSqlServer
                    PsDscRunAsCredential  = $domainRunAsCredential
                    DependsOn             = '[Package]PISystem'
                }
                # Adds PIFD to AG and replicas to secondary SQL Server.
                SqlAGDatabase AddPIDatabaseReplicas {
                    AvailabilityGroupName   = $sqlAlwaysOnAvailabilityGroupName
                    BackupPath              = "\\$SQLPrimary\Backup"
                    DatabaseName            = $PIAFSqlDB
                    InstanceName            = 'MSSQLSERVER'
                    ServerName              = $DefaultSqlServer
                    Ensure                  = 'Present'
                    PsDscRunAsCredential    = $domainRunAsCredential
                    DependsOn               = '[Package]PISystem','[SqlDatabaseRecoveryModel]PIFD'
                }
            }
            
            # Script resource to rename the AF Server so that it takes on the Load Balanced endpoint name.
            if ($deployHA -eq 'true') {
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
                    PsDscRunAsCredential = $domainRunAsCredential
                }
            }

            # 2E. Sets AFSERVER SPN on service account.
			xADServicePrincipalName 'SPN01'
			{
				ServicePrincipalName = $("AFSERVER/" + $env:COMPUTERNAME)
				Account              = $PIAFSvcAccountUsername 
				PsDscRunAsCredential = $domainRunAsCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}
			xADServicePrincipalName 'SPN02'
			{
				ServicePrincipalName = $("AFSERVER/" + $env:COMPUTERNAME + "." + $DomainDNSName)
				Account              = $PIAFSvcAccountUsername 
				PsDscRunAsCredential = $domainRunAsCredential
 				DependsOn			 = '[WindowsFeature]ADPS'
			}

			if($deployHA -eq 'true' -and $env:COMPUTERNAME -eq $AFPrimary){
				xADServicePrincipalName 'SPN03'
				{
					ServicePrincipalName = $("HTTP/" + $AFLoadBalancedName)
					Account              = $PIAFSvcAccountUsername 
					PsDscRunAsCredential = $domainRunAsCredential
 					DependsOn			 = '[WindowsFeature]ADPS'
				}
				xADServicePrincipalName 'SPN04'
				{
					ServicePrincipalName = $("HTTP/" + $AFLoadBalancedName + "." + $DomainDNSName)
					Account              = $PIAFSvcAccountUsername 
					PsDscRunAsCredential = $domainRunAsCredential
 					DependsOn			 = '[WindowsFeature]ADPS'
				}
			}

            # 2F. Initiate any outstanding reboots.
            xPendingReboot Reboot1 {
                Name      = 'PostInstall'
                DependsOn = '[Package]PISystem'
            }
            #endregion ### 2. INSTALL AND SETUP ###

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
# MIIbywYJKoZIhvcNAQcCoIIbvDCCG7gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBqh/4XZUt7O872
# xWTW4WvcONjieQBTqVwDONuSsXQUB6CCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIBqgJONY9aff
# WzpUqUUoE4pY0t0iIdHULBLXjycY/bdBMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQBY
# DCScwv3NeHfMZrjor0auC+Wg8qEEbZmTi5k1kx0hwHOr0RNkhD3wA/Ll0MxdPJUp
# UaKzeDkFWu2VKJugcpUbtn6NKYm1OftWSmzFnJWDttSXVoPQ8sx30HVosQ0aRO5M
# 1PpVeJ5fypfGWCpIuyz3dXkGQp8fRcKencUQX0Jq3ryaKMlXzViDX87OrSOtNyoB
# wQdOE/H+H+DVbFNUkBZ7EDJMBpqlgM96dASRzpkzKySEzddfM6beN7+x1dPfRgMp
# /Kzl0Jun8f3fb3rkEwy1nrNIJVWwqW+EoMvZxiyAJTMCkJ1kEtGLm8plaLI1sZMc
# CtgPN7923r6CV8MzWhAqoYIOPDCCDjgGCisGAQQBgjcDAwExgg4oMIIOJAYJKoZI
# hvcNAQcCoIIOFTCCDhECAQMxDTALBglghkgBZQMEAgEwggEOBgsqhkiG9w0BCRAB
# BKCB/gSB+zCB+AIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgtLx7
# wVsmr0tHfc1xYjiPdNxsgFESdM5nI9pDdssTmrYCFC6JcrCjduEdpErahs9fBVYK
# n48FGA8yMDE5MTAwODE5NTYxMFowAwIBHqCBhqSBgzCBgDELMAkGA1UEBhMCVVMx
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
# AQkFMQ8XDTE5MTAwODE5NTYxMFowLwYJKoZIhvcNAQkEMSIEINWnqL1XalgfuPvH
# YY8DsHSH3MdcZsi0rZ+WJVY7O3ZCMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMR0
# znYAfQI5Tg2l5N58FMaA+eKCATz+9lPvXbcf32H4MAsGCSqGSIb3DQEBAQSCAQBi
# jVqNS9aKNm2LENic96pK4SppaGbdmFN2s7PnLAWvhGC6e9GxclxacmUbRyQIqGzE
# CI4ht0Npk6tKyXWGFy0O1njVezdEzvSaNGZf7qLHoFlvOZmd4wCh4H+1PciLXX1w
# Uh/BScLpBpapu2hBR/FcWyrN7C4QmLWWue/xv8H70/+GSUjdLMvCK7v1PFC+Bm8B
# z7vEKiYIj1MuMOtIQ8/gG2YrOp84ulBDk5qAVCzH3glFWw9enknV1nAYRlqr0tYn
# 4CQfodg9JdFnb9XAZDwAUYDA3wJQgfvnNXOZKnJZhUbl2/nbT9dK5QW3yjzeuoot
# 4x/hM9wRTb5/s902sW1I
# SIG # End signature block
