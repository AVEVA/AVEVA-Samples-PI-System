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
# MIIcVgYJKoZIhvcNAQcCoIIcRzCCHEMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDJaU77oc0al6JG
# ta0kfpKNJyFxzZxYwNpKTN3e6t8y0qCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgpSdEMEIYQ7g8
# 3ypXHktmXiSxUGTtFM10gZa/u+k1sWQwMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAIjo
# DTNbrxnso+8ndjNaiJD8mutokiCIXqf56MiJnrIc0qbvsjMExi4KPPDVOld6oImc
# P48LqFVX9LZlFU1UaKDhn8u/bmRfadAnHfLBICmHMTFyEo0gvRfPXyt4XIhjDi+7
# aa7QzFRNzshhFAXnpvlHKUnEN11itwEOuXJVyNIriSvoM1gR9rr2UMdhiUXwN5Z5
# yOpb950QxAP8Qfq0kBtQXkBMhJUY8coh5B0P/PMPB+u6R0b3GdpMbBNg0G3fxrLy
# Ho012gk3HNZ6oSNegbPOjyh4UDcbK7cBPax9rKuMkk1bcE05zURAVS0R1nW5+z6L
# EA39+zRP8v4MoIiWChGhgg7IMIIOxAYKKwYBBAGCNwMDATGCDrQwgg6wBgkqhkiG
# 9w0BBwKggg6hMIIOnQIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEE
# oGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQgX7raa8+td0dI
# Q+OdeClhi7ifAZH5D97TW7iHyVp7Zg8CEFzM+R5nXQyoGRVMGEONUMIYDzIwMjAx
# MTI0MjAwODIwWqCCC7swggaCMIIFaqADAgECAhAEzT+FaK52xhuw/nFgzKdtMA0G
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
# hkiG9w0BCQUxDxcNMjAxMTI0MjAwODIwWjArBgsqhkiG9w0BCRACDDEcMBowGDAW
# BBQDJb1QXtqWMC3CL0+gHkwovig0xTAvBgkqhkiG9w0BCQQxIgQgqqjyG1TB8jIL
# +Yjqp9XY8BhhcEO89twlOD6ewLbmkR8wDQYJKoZIhvcNAQEBBQAEggEAhUSAHBFP
# mF/DqD2KKB4PQ6WC2Nv2mJEQQzcNvwJ1i6cnsKPlHWo94e/SUdZx14aKcx6tuyz6
# lqQ2XrEnmkLUy9fTekvR/qjzC1Cm5m2uolIN5MwY1xqhoPop8o2k9YsTe019zYXs
# /Bt6Kiv+Q3EGz6sS8tBynFd9+VcKSid5d/LBK2wr89zfvmzVIDKiqBetUWC+63GF
# gZO3//ALWkZjgkbmNduD5dT6AryGvj3ZBS/MFt3wfMu85NrYFeyc1aKmTekPhLi5
# 79cMQVZzBAqEvY1xWRf0Uxm/fP6lXQYzaIu/aoYr+n1R2SEoCBRvYlLmr+JyH1jb
# Oa6G7GZsGMXOVQ==
# SIG # End signature block
