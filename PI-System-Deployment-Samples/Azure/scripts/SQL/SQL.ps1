Configuration SQL
{
    param(
    [Parameter(Mandatory = $true)]
    [pscredential]$Credential,

    [Parameter(Mandatory = $true)]
    [pscredential]$SQLCredential,

    [Parameter(Mandatory = $true)]
    [string]$namePrefix,

    [Parameter(Mandatory = $true)]
    [string]$nameSuffix,

    [Parameter(Mandatory = $true)]
    [string]$SQLPrimary,

    [Parameter(Mandatory = $true)]
    [string]$SQLSecondary,

    [Parameter(Mandatory = $true)]
    [string]$deployHA,

    [Parameter(Mandatory = $true)]
    [string]$PrimaryDomainController,

    [Parameter(Mandatory = $true)]
    [string]$DomainNetBiosName,

    # Used by Cluster Resource (i.e. AG Listener)
    [Parameter(Mandatory = $true)]
    [String]$lbIP,

    # Used by Cluster Cloud Witness
    [Parameter(Mandatory = $true)]
    [String]$witnessStorageAccount,

    # Used by Cluster Cloud Witness
    [Parameter(Mandatory = $true)]
    [String]$witnessStorageAccountKey
    <#
    Array of hashtables in the form:
    @(@{Name='domain\myuser';LoginType='WindowsUser'},@{Name='domain\mygroup';LoginType='WindowsGroup'})
    #>
    )
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'StorageDsc'
    Import-DscResource -ModuleName 'xStorage'
    Import-DscResource -ModuleName 'xNetworking'
    Import-DscResource -ModuleName 'SqlServerDsc'
    Import-DscResource -ModuleName 'xPSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xActiveDirectory'
    Import-DscResource -ModuleName 'xFailOverCluster'
    Import-DscResource -ModuleName 'cNtfsAccessControl'
    Import-DscResource -ModuleName 'xSmbShare'

    $SQLAdminLogin = @(@{Name="$($namePrefix)\$($Credential.UserName)";LoginType='WindowsUser';ServerRole='sysadmin'})
    $ClusterOwnerNode = $SQLSecondary
    $ClusterName = $namePrefix + "-sqlclstr" + $nameSuffix
    $sqlAlwaysOnAvailabilityGroupName = $namePrefix + '-sqlag' + $nameSuffix
    $defaultEmptyDb = 'EmptyDB'

    [System.Management.Automation.PSCredential]$RunCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ("$namePrefix\$($Credential.UserName)", $Credential.Password)
    [System.Management.Automation.PSCredential]$SqlDomainCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ("$namePrefix\$($SQLCredential.UserName)", $SQLCredential.Password)

    Node localhost
    {
    #region ### 1. VM PREPARATION ###
    # Wait for Data Disk availability
    xWaitforDisk Volume_F {
        DiskID           = 2
        retryIntervalSec = 30
        retryCount       = 20
    }

    # Format Data Disk
    xDisk Volume_F {
        DiskID      = 2
        DriveLetter = 'F'
        FSFormat    = 'NTFS'
        FSLabel     = 'Data'
        DependsOn   = '[xWaitforDisk]Volume_F'
    }

	File DataDirectory {
        Type = 'Directory'
        DestinationPath = 'F:\Data'
        Ensure = "Present"
        DependsOn   = '[xDisk]Volume_F'
    }

    # Wait for Data Disk availability
    xWaitforDisk Volume_G {
        DiskID           = 3
        retryIntervalSec = 30
        retryCount       = 20
    }

    # Format Data Disk
    xDisk Volume_G {
        DiskID      = 3
        DriveLetter = 'G'
        FSFormat    = 'NTFS'
        FSLabel     = 'Logs'
        DependsOn   = '[xWaitforDisk]Volume_G'
    }

	File LogDirectory {
        Type = 'Directory'
        DestinationPath = 'G:\Log'
        Ensure = "Present"
        DependsOn   = '[xDisk]Volume_G'
    }

    # Wait for Data Disk availability
    xWaitforDisk Volume_H {
        DiskID           = 4
        retryIntervalSec = 30
        retryCount       = 20
    }

    # Format Data Disk
    xDisk Volume_H {
        DiskID      = 4
        DriveLetter = 'H'
        FSFormat    = 'NTFS'
        FSLabel     = 'Backups'
        DependsOn   = '[xWaitforDisk]Volume_H'
    }

	File BackupDirectory {
        Type = 'Directory'
        DestinationPath = 'H:\Backup'
        Ensure = "Present"
        DependsOn   = '[xDisk]Volume_H'
    }

    # Opening up ports 1433 and 1434 for SQL
    xFirewall DatabaseEngineFirewallRule
    {
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

    # Opening up ports 1433 and 1434 for SQL
    xFirewall SQLBrowserFirewallRule
    {
        Direction   = 'Inbound'
        Name        = 'SQL-Browser-Service-UDP-In'
        DisplayName = 'SQL Browser Service (UDP-In)'
        Description = 'Inbound rule for SQL Server to allow the use of the SQL Browser service'
        Group       = 'SQL Server'
        Enabled     = 'True'
        Protocol    = 'UDP'
        LocalPort   = '1434'
        Ensure      = 'Present'
    }

    xFirewall WMIFirewallRule
    {
        Direction = 'Inbound'
        Name = 'Windows Management Instrumentation (DCOM-In)'
        Enabled     = 'True'
    }
    #endregion ### 1. VM PREPARATION ###

    #region ### 2. INSTALL, SETUP, and LOGINS ###
    SqlServerNetwork 'EnableTcpStaticPort'
    {
        InstanceName = 'MSSQLSERVER' #used to be 'SQLEXPRESS' - Alex Oct 9 2018 14:43
        ProtocolName = 'tcp'
        IsEnabled = $true
        TcpDynamicPort = $false
        TcpPort = '1433'
        RestartService = $true
    }

    xService 'BrowserService'
    {
        Name = 'SQLBrowser'
        StartupType = 'Automatic'
        State = 'Running'
    }

    WindowsFeature ADPS {
        Name   = 'RSAT-AD-PowerShell'
        Ensure = 'Present'
    }

    if ($env:COMPUTERNAME -eq $SQLPrimary) {
        # 2A ii - To have the PI AF SQL Database work with SQL Always On, we use a domain group "AFSERVERS" instead of a local group.
        # This requires a modification to the AF Server install scripts per documentation:
        # This maps the SQL User 'AFServers' maps to this domain group instead of the local group, providing security mapping consistency across SQL nodes.
        xADGroup CreateAFServersGroup {
            GroupName   = 'AFServers'
            Description = 'Service Accounts with Access to PIFD databases'
            Category    = 'Security'
            Ensure      = 'Present'
            GroupScope  = 'Global'
            Credential  = $RunCredential
            DomainController = $PrimaryDomainController
            DependsOn   = '[WindowsFeature]ADPS'
        }

        Script WaitForADGroup
        {
            GetScript = {$false}
            TestScript = {$false}
            SetScript = {
                #Wait for AD to create the group
                Start-Sleep -s 60
            }
            DependsOn = '[xADGroup]CreateAFServersGroup'
        }

        # 2E ii - Add Domain AFSERVERS group as Sql Login
        SQLServerLogin AddAFServersGroupToPublicServerRole {
            Name                 = "$namePrefix\AFServers"
            LoginType            = 'WindowsGroup'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = 'MSSQLSERVER'
            Ensure               = 'Present'
            PsDscRunAsCredential = $Credential
            DependsOn            = '[Script]WaitForADGroup'
        }
    }
    else {
        # 2E ii - Add Domain AFSERVERS group as Sql Login
        SQLServerLogin AddAFServersGroupToPublicServerRole {
            Name                 = "$namePrefix\AFServers"
            LoginType            = 'WindowsGroup'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = 'MSSQLSERVER'
            Ensure               = 'Present'
            PsDscRunAsCredential = $Credential
        }
    }

    # Adding domain sysadmin to SQL
    SQLServerLogin 'AdminLogin'
    {
        ServerName = 'localhost'
        InstanceName = 'MSSQLSERVER'
        Name = $SQLAdminLogin.Name
        LoginType = $SQLAdminLogin.LoginType
        PsDscRunAsCredential = $Credential
    }

    SQLServerRole 'AdminRole' {
        ServerRoleName       = $SQLAdminLogin.ServerRole
        MembersToInclude     = $SQLAdminLogin.Name
        ServerName           = 'localhost'
        InstanceName         = 'MSSQLSERVER'
        PsDscRunAsCredential = $Credential
    }

	SqlDatabaseDefaultLocation Set_SqlDatabaseDefaultDirectory_Data
    {
        ServerName              = $env:COMPUTERNAME
        InstanceName			= 'MSSQLSERVER'
        ProcessOnlyOnActiveNode = $true
        Type                    = 'Data'
        Path                    = 'F:\DATA'
        PsDscRunAsCredential    = $RunCredential
		DependsOn   = '[File]DataDirectory'
    }

	SqlDatabaseDefaultLocation Set_SqlDatabaseDefaultDirectory_Log
    {
        ServerName              = $env:COMPUTERNAME
        InstanceName			= 'MSSQLSERVER'
        ProcessOnlyOnActiveNode = $true
        Type                    = 'Log'
        Path                    = 'G:\LOG'
        PsDscRunAsCredential    = $RunCredential
		DependsOn   = '[File]LogDirectory'
    }

	SqlDatabaseDefaultLocation Set_SqlDatabaseDefaultDirectory_Backup
    {
        ServerName              = $env:COMPUTERNAME
        InstanceName			= 'MSSQLSERVER'
		ProcessOnlyOnActiveNode = $true
		RestartService			= $true
        Type                    = 'Backup'
        Path                    = 'H:\BACKUP'
        PsDscRunAsCredential    = $RunCredential
		DependsOn   = '[File]BackupDirectory'
    }

    if ($env:COMPUTERNAME -eq $SQLPrimary) {
        SqlDatabase EmptyDB {
            Ensure       = 'Present'
            ServerName   = $env:COMPUTERNAME
            Name         = $defaultEmptyDb
            InstanceName = 'MSSQLServer'
        }

        # 2B: AG Databases need to be set to Full Recovery Model
        SqlDatabaseRecoveryModel EmptyDBFullRecovery {
            Name                 = $defaultEmptyDb
            RecoveryModel        = 'Full'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = 'MSSQLServer'
            PsDscRunAsCredential = $RunCredential
            DependsOn            = '[SqlDatabase]EmptyDB'
        }
    }

    SqlServerLogin AddNTServiceClusSvc {
        Ensure               = 'Present'
        Name                 = ($namePrefix+'\'+$SQLCredential.UserName)
        LoginType            = 'WindowsUser'
        ServerName           = $env:COMPUTERNAME
        InstanceName         = 'MSSQLSERVER'
        PsDscRunAsCredential = $Credential
    }

    # 2 D ii.Add the required permissions to the cluster service login
    SqlServerPermission AddNTServiceClusSvcPermissions {
        Ensure               = 'Present'
        ServerName           = $env:COMPUTERNAME
        InstanceName         = 'MSSQLSERVER'
        Principal            = $SqlDomainCredential.UserName
        Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
        PsDscRunAsCredential = $RunCredential
        DependsOn            = '[SqlServerLogin]AddNTServiceClusSvc'
    }


    # Need to add SQL Server Service Account with permissions to access HADR, otherwise replication will fail.
    SqlServerEndpointPermission SQLConfigureEndpointPermission {
        Ensure               = 'Present'
        ServerName           = $env:COMPUTERNAME
        InstanceName         = 'MSSQLSERVER'
        Name                 = 'Microsoft SQL VM HA Container Mirroring Endpoint'
        Principal            = $SqlDomainCredential.UserName
        Permission           = 'CONNECT'
        PsDscRunAsCredential = $RunCredential
    }

    Script RefreshFileSystem
    {
        GetScript = {$false}
        TestScript = {$false}
        SetScript = {Get-PSDrive -PSProvider FileSystem}
    }

    # Set SQL Server Service Account permissions on transfer folder.
    cNtfsPermissionEntry TransferFolderPermissions {
        Ensure                   = 'Present'
        Path                     = 'H:\BACKUP'
        Principal                = $SqlDomainCredential.UserName
        AccessControlInformation = @(
            cNtfsAccessControlInformation {
                AccessControlType  = 'Allow'
                FileSystemRights   = 'FullControl'
                Inheritance        = 'ThisFolderSubfoldersAndFiles'
                NoPropagateInherit = $false
            }
        )
        PsDscRunAsCredential = $RunCredential
        DependsOn   = '[File]BackupDirectory', '[Script]RefreshFileSystem'
    }

    # Make Backup Folder an SMB Share so DB can be transferred when setting up Always On.
    xSmbShare CreateBackupShare {
        Name        = 'Backup'
        Path        = 'H:\BACKUP'
        Description = 'Used for DB backups and transfers setting up AG'
        Ensure      = 'Present'
        FullAccess  = @('Domain Admins', $SQLAdminLogin.Name, $SqlDomainCredential.UserName)
        DependsOn   = '[cNtfsPermissionEntry]TransferFolderPermissions'
    }


    if ( $env:COMPUTERNAME -eq $SQLPrimary ) {
        # 2G a. PRIMARY: Create the availability group on the instance tagged as the primary replica
        SqlAG CreateAG {
            Ensure               = 'Present'
            Name                 = $sqlAlwaysOnAvailabilityGroupName
            InstanceName         = 'MSSQLSERVER'
            ServerName           = $SQLPrimary
            AvailabilityMode     = 'SynchronousCommit'
            FailoverMode         = 'Automatic'
            PsDscRunAsCredential = $RunCredential
        }

            SqlAGListener CreateSqlAgListener {
                Ensure               = 'Present'
                ServerName           = $SQLPrimary
                InstanceName         = 'MSSQLSERVER'
                AvailabilityGroup    = $sqlAlwaysOnAvailabilityGroupName
                Name                 = 'AG0-Listener'
                IpAddress            = "$lbIP/255.255.255.128"
                Port                 = 1433
                DependsOn            = '[SqlAG]CreateAG'
                PsDscRunAsCredential = $RunCredential
            }
        }
        else {
                # 2G b i. SECONDARY: Waiting for the Availability Group role to be present.
                SqlWaitForAG WaitAG {
                    Name                 = $sqlAlwaysOnAvailabilityGroupName
                    RetryIntervalSec     = 60
                    RetryCount           = 30
                    PsDscRunAsCredential = $RunCredential
                    #DependsOn            = '[SqlAlwaysOnService]EnableAlwaysOn'
                }

                # 2G b ii. Add replica to the availability group already create on the primary node.
                SqlAGReplica AddReplica {
                    Ensure                     = 'Present'
                    Name                       = $env:COMPUTERNAME
                    AvailabilityGroupName      = $sqlAlwaysOnAvailabilityGroupName
                    ServerName                 = $env:COMPUTERNAME
                    InstanceName               = 'MSSQLSERVER'
                    PrimaryReplicaServerName   = $SQLPrimary
                    PrimaryReplicaInstanceName = 'MSSQLSERVER'
                    AvailabilityMode           = 'SynchronousCommit'
                    FailoverMode               = 'Automatic'
                    PsDscRunAsCredential       = $RunCredential
                    DependsOn                  = '[SqlServerLogin]AddNTServiceClusSvc', '[SqlServerPermission]AddNTServiceClusSvcPermissions', '[SqlWaitForAG]WaitAG'
                }
            }

            If ($env:COMPUTERNAME -eq $SQLPrimary) {
                Script SetListenerProbePort {
                    GetScript = {
                        Return @{$ProbeIP = (Get-ClusterResource | Where-Object {$_.Name -eq "$using:sqlAlwaysOnAvailabilityGroupName`_$using:lbIP"} | Get-ClusterParameter | Where-Object {$_.Name -eq "ProbePort"}).Value}
                    }

                    TestScript = {
                        if ($ProbeIP -eq '59999') {
                            Write-Verbose -Message "The listener associated with $using:sqlAlwaysOnAvailabilityGroupName already uses the correct port - 59999"
                            return $true
                        }
                        else {
                            Write-Verbose -Message "The listener associated with $using:sqlAlwaysOnAvailabilityGroupName is not using the correct port - 59999"
                            return $false
                        }
                    }

                    SetScript = {
                        (Get-ClusterResource | Where-Object {$_.Name -eq "$using:sqlAlwaysOnAvailabilityGroupName`_$using:lbIP"}) | Set-ClusterParameter -Name "ProbePort" -Value 59999
                        Restart-Service -Name ClusSvc
                    }

                PsDscRunAsCredential = $RunCredential
                DependsOn            = '[SqlAGListener]CreateSqlAgListener'
                }
            }

            If ($env:COMPUTERNAME -eq $SQLSecondary) {
                SqlAGDatabase AddPIDatabaseReplicas {
                    AvailabilityGroupName = $sqlAlwaysOnAvailabilityGroupName
                    BackupPath            = "\\$SQLPrimary\BACKUP"
                    DatabaseName          = $defaultEmptyDb
                    InstanceName          = 'MSSQLSERVER'
                    ServerName            = $SQLPrimary
                    Ensure                = 'Present'
                    PsDscRunAsCredential  = $RunCredential
                }
        }
    }
}
# SIG # Begin signature block
# MIIbzAYJKoZIhvcNAQcCoIIbvTCCG7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDAImGNr8TcuLnV
# j3EFNe+g78PlPAMwuVjhh+qrnUwXQaCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIB/v95sMTZsm
# gMuUkWqBonwt2Oy2hm2ZtYMaoeD7KtOtMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQCk
# 79Yp5hADgRB0i7nMM9DaIvv6so9byWPFFVYy2TlRHEkq+OuKlaTTH/NVgM7oduK+
# CiOfo2mgcJyyaSWOS7dSePDh9pPwf8QLi/AJLrZSpEatweGrTJRtR64EMviQz5Xn
# U4CyG29qJw+gWnSH/FwW9O4ScZmUKnSo1R6OMz7XkDRJhPHekMAxWS2FH9oL7MqR
# iJJAMOpfW+Hd5aOzexIZoZ4qs9pbJWQSYQJv8v7Jx3qsbKqUlMFEpy35K4lOPuwz
# +wMYdniUuJtFU3dOJwV+5/qSGss3r2Ui4HsIQVnCFZ6YKnseja3XPE8KaBbK/q/v
# TW4IMTmSEbsOZaaehtYBoYIOPTCCDjkGCisGAQQBgjcDAwExgg4pMIIOJQYJKoZI
# hvcNAQcCoIIOFjCCDhICAQMxDTALBglghkgBZQMEAgEwggEPBgsqhkiG9w0BCRAB
# BKCB/wSB/DCB+QIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgwig1
# lf8Y4UNSJppj4MUCPTnufU5IPIi5IwitLdqxQdACFQDj382m9PeuP17eDnkObbSu
# adUHtRgPMjAyMDAzMjAxOTIzMzFaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
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
# DQEJBTEPFw0yMDAzMjAxOTIzMzFaMC8GCSqGSIb3DQEJBDEiBCBF8mgx+RGjAL1d
# N1g0KGu309cxg0kw5U60837utXuzoTA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# BgcRyEszreaHM7a8enEAvNmqNpYs5XUWwnZ2O1UQFONyq0cjKu8atBKgyG0HYUH9
# 76lrvSPIjdVPX+ylzEs1GN8DkbU4U1HikWvDBKgdFsgM66sAJhWRBSIgO7KjVw95
# ACocJXxhms+8uUYE0KBjnCu862f7EeWIr7Q093ziuC3RvwmAU7YeKUXFwT2Axqma
# hkKP0JTioyvO45jw0hMUC13k4ZxlujYP86/hvG6zDbT/qiICYVJYMrMHqJE6EyA+
# vMBWMYWReo1G0yfxGME4e5LSzb9seScIKWHGkn9/95dMxy85zTdJA5uwpfo1aHYc
# DDQ9OQMjU1zqPBYiAOd/oA==
# SIG # End signature block
