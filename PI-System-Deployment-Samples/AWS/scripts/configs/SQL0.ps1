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
    Import-Module -Name SqlServer -RequiredVersion '21.0.17279'

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
# MIIbywYJKoZIhvcNAQcCoIIbvDCCG7gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAoTKj3FRBkluPl
# ilmquk5L87l3thsXYpgd+TFrJi3vNqCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFRZ7FsI0zdw
# nj4N0CjfS793dzRxXUdswp3L8WjgGm9yMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQB6
# Ur02vqz7cpoIBX0gVcJnETjG6U3QRzoB8rCsJG0I4y/GoN+b7W31sfIltNf6mtVi
# 4U3VplEw72cUf2evLUlQeHoYypksmkIUVm5Zigcr0iOA/mqNg25UkAj1vB7FR4ch
# KzvtMTPIS7q2oaVu7Vctlg84wvi0hyl6AFh3MBx51kXLhExTbdpsx1ZX986qTXUs
# PTGVf8urPxxU5d94w6B+KjYE9AyZlc2kCTo14nn4LSL4TqArAPq3R9g/xTReK3K7
# amVRg4f2eM/UWGV+YzL97wDK3x8rmI1btsbHARJrLLw6yIU4Q3CucpCQ4YV5Oypd
# ZrcQXV5lrjeDibfVTCpKoYIOPDCCDjgGCisGAQQBgjcDAwExgg4oMIIOJAYJKoZI
# hvcNAQcCoIIOFTCCDhECAQMxDTALBglghkgBZQMEAgEwggEOBgsqhkiG9w0BCRAB
# BKCB/gSB+zCB+AIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgUz4c
# xtWdMSgwQd/5rZt9+Pa6nG0YN095K7LlUlaUiogCFAdQ30qNzbB8z4KmlQsGSfSJ
# 6gaQGA8yMDE5MDgwODE0NTc1N1owAwIBHqCBhqSBgzCBgDELMAkGA1UEBhMCVVMx
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
# AQkFMQ8XDTE5MDgwODE0NTc1N1owLwYJKoZIhvcNAQkEMSIEIGTSklIUcJlL+bk1
# hNbS+QDYghVH2VHzfG7YNuwdkkmYMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMR0
# znYAfQI5Tg2l5N58FMaA+eKCATz+9lPvXbcf32H4MAsGCSqGSIb3DQEBAQSCAQBm
# 3hqSRJ25aK6GkbUTnOC+4tUHGL6ZNPTC2gvgMi4OJaUBIust3Q3KrT4brOB3VYij
# lbj7972PNkCet7+lLXY0qis40RDVuLMgsdtWz90MyFre4GwpogGzIPPOT8AfNQOJ
# HZKob+dg2CDbl/cPwFi7PNJP1sAJyT5RnDacCEG+Yk4UbSOrVGapid0nwjZwoXZG
# QI8RuuPNYht0QoxOdwQLBDt9rgBG3StiD4qXH3LKUgelBLCMB3iSGJ8Xv3RePoWB
# cp7WtudeabeLSANIl73KXhvO4gU/Zs1wyIhhz3Te7YN3WXkhhVpqUmJL7yShNBqd
# O2zkomkmBccoCaW9iFOt
# SIG # End signature block
