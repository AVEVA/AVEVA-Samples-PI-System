[CmdletBinding()]
param(
    # Domain Net BIOS Name, e.g. 'mypi'.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainNetBiosName,

    # Username of domain admin account.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainAdminUserName,

    # Username of the SQL service account.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$SqlServiceAccountName,

    # "Fully qualified domain name (FQDN) of the forest root domain e.g. mypi.int"
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DomainDNSName,

    # Default SQL Server Name
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$SQLServerPrimaryName,

    # IP Addresses for SQL Listener on Sql Primary
    [Parameter()]
    [ValidateNotNullorEmpty()]
    $SqlAgListenerPrimaryIP,

    # Default PI Data Archive
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$SQLServerSecondaryName,


    # IP Addresses for SQL Listener on Sql Secondary
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    $SqlAgListenerSecondaryIP,

    # Primary domain controller targeted for service account creation.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PrimaryDomainController,

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix
)

try {
    # Set to enable catch to Write-AWSQuickStartException
    $ErrorActionPreference = "Stop"

    Import-Module $psscriptroot\IPHelper.psm1
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

    # Get exisitng service account password from AWS System Manager Parameter Store.
    $DomainAdminPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$DomainAdminUserName" -WithDecryption $True).Parameters[0].Value
    
    # Generate credential object for domain admin account.
    $secureDomainAdminPassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $domainCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$DomainAdminUserName", $secureDomainAdminPassword)

    # Specify the FQDN for each SQL Server used in Always On Setup and SQL Service account.
    $SqlServerPrimaryFQDN = "$SQLServerPrimaryName" + '.' + "$DomainDNSName"
    $SqlServerSecondaryFQDN = "$SQLServerSecondaryName" + '.' + "$DomainDNSName"
    $SqlServiceFQDN = "$DomainNetBiosName\$SqlServiceAccountName"

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

    # EC2 Configuration
    Configuration SQL0Config {

        param()

        Import-DscResource -ModuleName PSDesiredStateConfiguration
        Import-DscResource -ModuleName SqlServerDsc -ModuleVersion 13.2.0.0         ## Used in SQL Always On Configuration
        Import-DscResource -ModuleName xActiveDirectory -ModuleVersion 3.0.0.0     ## Used to Create and add 'AFSERVERS' domain group.
        Import-DscResource -ModuleName xNetworking -ModuleVersion 5.7.0.0           ## Used to create firewall rules
        Import-DscResource -ModuleName cNtfsAccessControl -ModuleVersion 1.4.1      ## Used for setting permissions on Backup folder
        Import-DscResource -ModuleName xSmbShare -ModuleVersion 2.1.0.0             ## Used for setting permissions on Backup folder


        Node $env:COMPUTERNAME {

            #region ### 1. VM PREPARATION ###
            # 1 a. Install AD cmdlets for User and Group creation.
            WindowsFeature ADPS {
                Name   = 'RSAT-AD-PowerShell'
                Ensure = 'Present'
            }

            #Open SQL Specific Firewall Ports
            xFirewall DatabaseEngineFirewallRule {
                Direction   = 'Inbound'
                Name        = 'SQL-Server-Database-Engine-TCP-In'
                DisplayName = 'SQL Server Database Engine (TCP-In)'
                Description = 'Inbound rule for SQL Server to allow TCP traffic for the Database Engine.'
                Group       = 'SQL Server'
                Enabled     = 'True'
                Protocol    = 'TCP'
                LocalPort   = '1433'
                Ensure      = 'Present'
            }

            xFirewall DatabaseMirroringFirewallRule {
                Direction   = 'Inbound'
                Name        = 'SQL-Server-Database-Mirroring-TCP-In'
                DisplayName = 'SQL Server Database Mirroring (TCP-In)'
                Description = 'Inbound rule for SQL Server to allow TCP traffic for the Database Mirroring.'
                Group       = 'SQL Server'
                Enabled     = 'True'
                Protocol    = 'TCP'
                LocalPort   = '5022'
                Ensure      = 'Present'
            }
            #endregion ### 1. VM PREPARATION ###


            #region ### 2. INSTALL AND SETUP ###
            # 2A: Enable AG and add endpoint
            if ( $env:COMPUTERNAME -eq $SQLServerPrimaryName ) {
                SqlDatabase EmptyDB {
                    Ensure       = 'Present'
                    ServerName   = $SqlServerPrimaryFQDN
                    Name         = 'EmptyDB'
                    InstanceName = 'MSSQLServer'
                }

                # 2B: AG Databases need to be set to Full Recovery Model
                SqlDatabaseRecoveryModel EmptyDBFullRecovery {
                    Name                 = 'EmptyDB'
                    RecoveryModel        = 'Full'
                    ServerName           = $SqlServerPrimaryFQDN
                    InstanceName         = 'MSSQLServer'
                    PsDscRunAsCredential = $domainCredential
                    DependsOn            = '[SqlDatabase]EmptyDB'
                }
            }

            # 2C. Ensure SQL Always On feature is enabled.
            SqlAlwaysOnService EnableAlwaysOn {
                Ensure         = 'Present'
                ServerName     = $env:COMPUTERNAME
                InstanceName   = 'MSSQLSERVER'
                RestartTimeout = 120
            }

            SqlServerLogin AddSqlSvc {
                Ensure               = 'Present'
                Name                 = $SqlServiceFQDN
                LoginType            = 'WindowsUser'
                ServerName           = $env:COMPUTERNAME
                InstanceName         = 'MSSQLSERVER'
                PsDscRunAsCredential = $domainCredential
            }

            SqlServerPermission AddSqlSvcPermissions {
                Ensure               = 'Present'
                ServerName           = $env:COMPUTERNAME
                InstanceName         = 'MSSQLSERVER'
                Principal            = $SqlServiceFQDN
                Permission           = 'ConnectSql'
                PsDscRunAsCredential = $domainCredential
                DependsOn            = '[SqlServerLogin]AddSqlSvc'
            }

            # 2D i. # Adding the required service account to allow the cluster to log into SQL
            SqlServerLogin AddNTServiceClusSvc {
                Ensure               = 'Present'
                Name                 = 'NT SERVICE\ClusSvc'
                LoginType            = 'WindowsUser'
                ServerName           = $env:COMPUTERNAME
                InstanceName         = 'MSSQLSERVER'
                PsDscRunAsCredential = $domainCredential
            }

            # 2 D ii.Add the required permissions to the cluster service login
            SqlServerPermission AddNTServiceClusSvcPermissions {
                Ensure               = 'Present'
                ServerName           = $env:COMPUTERNAME
                InstanceName         = 'MSSQLSERVER'
                Principal            = 'NT SERVICE\ClusSvc'
                Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
                PsDscRunAsCredential = $domainCredential
                DependsOn            = '[SqlServerLogin]AddNTServiceClusSvc'
            }

            # 2E i - To have the PI AF SQL Database work with SQL Always On, we use a domain group "AFSERVERS" instead of a local group.
            # This requires a modification to the AF Server install scripts per documentation: 
            # This maps the SQL User 'AFServers' maps to this domain group instead of the local group, providing security mapping consistency across SQL nodes.
            xADGroup CreateAFServersGroup {
                GroupName        = 'AFServers'
                Description      = 'Service Accounts with Access to PIFD databases'
                Category         = 'Security'
                Ensure           = 'Present'
                GroupScope       = 'Global'
                DomainController = $PrimaryDomainController
                Credential       = $domainCredential
                DependsOn        = '[WindowsFeature]ADPS'
            }

            # 2E ii - Add Domain AFSERVERS group as Sql Login
            SQLServerLogin AddAFServersGroupToPublicServerRole {
                Name                 = "$DomainNetBiosName\AFServers"
                LoginType            = 'WindowsGroup'
                ServerName           = $env:COMPUTERNAME
                InstanceName         = 'MSSQLSERVER'
                Ensure               = 'Present'
                PsDscRunAsCredential = $domainCredential
                DependsOn            = '[xADGroup]CreateAFServersGroup'
            }

            # 2F. Create a DatabaseMirroring endpoint
            SqlServerEndpoint HADREndpoint {
                EndPointName         = 'HADR'
                Ensure               = 'Present'
                Port                 = 5022
                ServerName           = $env:COMPUTERNAME
                InstanceName         = 'MSSQLSERVER'
                DependsOn            = '[SqlAlwaysOnService]EnableAlwaysOn'
                PsDscRunAsCredential = $domainCredential
            }

            # Need to add SQL Server Service Account with permissions to access HADR, otherwise replication will fail.
            SqlServerEndpointPermission SQLConfigureEndpointPermission {
                Ensure               = 'Present'
                ServerName           = $env:COMPUTERNAME
                InstanceName         = 'MSSQLSERVER'
                Name                 = 'HADR'
                Principal            = $SqlServiceFQDN
                Permission           = 'CONNECT'
                PsDscRunAsCredential = $domainCredential
            }

            # Set SQL Server Service Account permissions on transfer folder.
            cNtfsPermissionEntry TransferFolderPermissions {
                Ensure                   = 'Present'
                Path                     = 'F:\MSSQL\Backup'
                Principal                = $SqlServiceFQDN
                AccessControlInformation = @(
                    cNtfsAccessControlInformation {
                        AccessControlType  = 'Allow'
                        FileSystemRights   = 'FullControl'
                        Inheritance        = 'ThisFolderSubfoldersAndFiles'
                        NoPropagateInherit = $false
                    }
                )
            }

            # Make Backup Folder an SMB Share so DB can be transferred when setting up Always On.
            xSmbShare CreateBackupShare {
                Name        = 'Backup'
                Path        = 'F:\MSSQL\Backup'
                Description = 'Used for DB backups and transfers setting up AG'
                Ensure      = 'Present'
                FullAccess  = @('Domain Admins', $SqlServiceAccountName)
                DependsOn   = '[cNtfsPermissionEntry]TransferFolderPermissions'
            }


            if ( $env:COMPUTERNAME -eq $SQLServerPrimaryName ) {
                # 2G a. PRIMARY: Create the availability group on the instance tagged as the primary replica
                SqlAG CreateAG {
                    Ensure               = 'Present'
                    Name                 = 'SQLAG0'
                    InstanceName         = 'MSSQLSERVER'
                    ServerName           = $SqlServerPrimaryFQDN
                    AvailabilityMode     = 'SynchronousCommit'
                    FailoverMode         = 'Automatic'
                    DependsOn            = '[SqlServerEndpoint]HADREndpoint', '[SqlServerLogin]AddNTServiceClusSvc', '[SqlServerPermission]AddNTServiceClusSvcPermissions'
                    PsDscRunAsCredential = $domainCredential
                }

                SqlAGListener CreateSqlAgListener {
                    Ensure               = 'Present'
                    ServerName           = $SqlServerPrimaryFQDN
                    InstanceName         = 'MSSQLSERVER'
                    AvailabilityGroup    = 'SQLAG0'
                    Name                 = 'AG0-Listener'
                    IpAddress            = @("$SqlAgListenerPrimaryIP/255.255.255.0", "$SqlAgListenerSecondaryIP/255.255.255.0")
                    Port                 = 1433
                    DependsOn            = '[SqlAG]CreateAG'
                    PsDscRunAsCredential = $domainCredential
                }
            }
            else {
                # 2G b i. SECONDARY: Waiting for the Availability Group role to be present.
                SqlWaitForAG WaitAG {
                    Name                 = 'SQLAG0'
                    RetryIntervalSec     = 60
                    RetryCount           = 30
                    PsDscRunAsCredential = $domainCredential
                    DependsOn            = '[SqlAlwaysOnService]EnableAlwaysOn'
                }

                # 2G b ii. Add replica to the availability group already create on the primary node.
                SqlAGReplica AddReplica {
                    Ensure                     = 'Present'
                    Name                       = $env:COMPUTERNAME
                    AvailabilityGroupName      = 'SQLAG0'
                    ServerName                 = $env:COMPUTERNAME
                    InstanceName               = 'MSSQLSERVER'
                    PrimaryReplicaServerName   = $SqlServerPrimaryFQDN
                    PrimaryReplicaInstanceName = 'MSSQLSERVER'
                    AvailabilityMode           = 'SynchronousCommit'
                    FailoverMode               = 'Automatic'
                    PsDscRunAsCredential       = $domainCredential
                    DependsOn                  = '[SqlServerEndpoint]HADREndpoint', '[SqlServerLogin]AddNTServiceClusSvc', '[SqlServerPermission]AddNTServiceClusSvcPermissions', '[SqlWaitForAG]WaitAG'
                }
            }
            #endregion ### 2. INSTALL AND SETUP ###


            #region ### 3. IMPLEMENT OSISOFT FIELD SERVICE TECHNICAL STANDARDS ###
            #endregion ### 3. IMPLEMENT OSISOFT FIELD SERVICE TECHNICAL STANDARDS ###


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
                DependsOn  = if ($env:COMPUTERNAME -eq $SQLServerPrimaryName) {'[SqlAGListener]CreateSqlAgListener'} else {'[SqlAGReplica]AddReplica'}
            }
            #endregion ### 4. SIGNAL WAITCONDITION ###
        }
    }

    # Compile and Execute Configuration
    SQL0Config -ConfigurationData $ConfigurationData
    Start-DscConfiguration -Path .\SQL0Config -Wait -Verbose -Force -ErrorVariable ev
}

catch {
    # If any expectations are thrown, output to CloudFormation Init.
    $_ | Write-AWSQuickStartException
}
# SIG # Begin signature block
# MIIcVgYJKoZIhvcNAQcCoIIcRzCCHEMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDTiXWZTY49eaj9
# KKKRDhIs7I8TDlJYbY5GSPGTAc/LEaCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgP7qvbWBO5rvV
# e6NF7r8JbDLa26XpL+8j5yYk5tzdUgYwMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAHhB
# DELu5tyAMpSKLK/WrgRbxqnLmkK4NKNzpBomC0r9hvTEQ3OoqRoK6A2GoMWG1Px5
# 1YO6m4DyUBYSTX0r8eA4rIv/+Z7O9DOeYcLwO4V0+e9Uy49B7dSE4HeosbiDWzOb
# yddzP2mhGcRYs9p4wkNU+o6PjmFpn8S5yvtUZ/yhEmRKrYgkzNLiMN+IlYbacDgw
# raBPE3MTDFI6xToHkVvATJpcySiKvHzR5hkMF7gasIvD/LojSrigXWysyeGX2PEz
# cUODUbFfJlUFavzbK8bpAM5O0l+408b6VwRXMyd2Mq1A7d0Ksy2TsZUANrTY5f/3
# oTPVHxSXxdGvHIOX2Dahgg7IMIIOxAYKKwYBBAGCNwMDATGCDrQwgg6wBgkqhkiG
# 9w0BBwKggg6hMIIOnQIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEE
# oGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQg1woWZF2tRfJz
# ACS2/a1DJoosqDHAIf0xXRWJNNZ5SzUCEAOpO9VSNe5HxYn4lQKtgsYYDzIwMjAx
# MTExMTcyNzMwWqCCC7swggaCMIIFaqADAgECAhAEzT+FaK52xhuw/nFgzKdtMA0G
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
# hkiG9w0BCQUxDxcNMjAxMTExMTcyNzMwWjArBgsqhkiG9w0BCRACDDEcMBowGDAW
# BBQDJb1QXtqWMC3CL0+gHkwovig0xTAvBgkqhkiG9w0BCQQxIgQgzDErE6pOmFjp
# wb4M/ZzpuEz1S3sss0rTpYYGcPboC+UwDQYJKoZIhvcNAQEBBQAEggEAWxA/fmkV
# 8KGCJjfUzKTa0g1Y42t1iuCS0Y3DkWIt+KoJdpCz9JX+154qtjOj7KBmINpfmcHs
# eLk56QgIpKgcUlaXlu3iuJShtRkbf00bXDcTt6nCIoKJGEXA3KNLk93rbxELc5eN
# 1nnBMdJmdehhhuTTTEtRDXigH8stiWLwgmcPQChbomEZPwC5oIqy/991RLHTYis8
# F99t/4xIfIUGq8xpzo/hvIazoLImV39ZAeahiaH4lyxvAWQ7YtrstTPoFseXxtol
# R/vFHBeCV9ie+wIIpQJUsiV+/kh1MfaOfx6AHw4kxUJgkXaS7vrlUo5QrsDi45eO
# nUY6n4T2KxFsIA==
# SIG # End signature block
