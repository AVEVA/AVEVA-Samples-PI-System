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
# MIIcVwYJKoZIhvcNAQcCoIIcSDCCHEQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDJt9TA1l2QzBeW
# oZ53K/+VzDyviUmCvblu6KIKCssdsaCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# Q+9sIKX0AojqBVLFUNQpzelOdjGWNzdcMMSu8p0pNw4xeAbuCEHfMYIRIDCCERwC
# AQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBB
# c3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQBlb6upLHhoprGBiRrHb6WzANBglg
# hkgBZQMEAgEFAKCBnjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg2MveY8O6v+b4
# yzcDOH3osMypVq57LzVsoOaQd5kUW4EwMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAGwb
# K5iJMmpXSG2cttuhiy9M5J+38ORP5ORJCu/VF1Nr4sPSX6wU617a+3uQteJYf/EL
# h1ONkMF+umJLsodtTT7PG9sbu0yNxBwdLE7kPfpst/IjefngwhLpIrQPI9zoCZxN
# lMYjbSrHcVueU6crHlWXBBc29XOEeqz2VG0tzaPi11GEMexEjmI/45zzALZxSfSF
# hHMmki/bY/RRtxW+aWoyq1JsC/pvFEMuvkIKn11EedKm6YouXF6q8pABAtiA6x13
# DMoB4w1jvT7PWlcPtV71Y6yTLagFT0ynF1OTfb6Bjf7GDkswXcfJ9rOQwdmG9Muv
# 4k/Ljx4YNLu11jJWkVWhgg7JMIIOxQYKKwYBBAGCNwMDATGCDrUwgg6xBgkqhkiG
# 9w0BBwKggg6iMIIOngIBAzEPMA0GCWCGSAFlAwQCAQUAMHgGCyqGSIb3DQEJEAEE
# oGkEZzBlAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQg+BVtfDV5p7+F
# 8hVgXHhi5MRpDC7qjKvsHjZNun8Ng8oCEQCv/F+cOXmEh+r7VNvbnOHZGA8yMDIw
# MTEyNDIwMDgyMlqgggu7MIIGgjCCBWqgAwIBAgIQBM0/hWiudsYbsP5xYMynbTAN
# BgkqhkiG9w0BAQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2Vy
# dCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTE5MTAwMTAwMDAw
# MFoXDTMwMTAxNzAwMDAwMFowTDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMSQwIgYDVQQDExtUSU1FU1RBTVAtU0hBMjU2LTIwMTktMTAtMTUw
# ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDpZDWc+qmYZWQb5BfcuCk2
# zGcJWIVNMODJ/+U7PBEoUK8HMeJdCRjC9omMaQgEI+B3LZ0V5bjooWqO/9Su0noW
# 7/hBtR05dcHPL6esRX6UbawDAZk8Yj5+ev1FlzG0+rfZQj6nVZvfWk9YAqgyaSIT
# vouCLcaYq2ubtMnyZREMdA2y8AiWdMToskiioRSl+PrhiXBEO43v+6T0w7m9FCzr
# DCgnJYCrEEsWEmALaSKMTs3G1bJlWSHgfCwSjXAOj4rK4NPXszl3UNBCLC56zpxn
# ejh3VED/T5UEINTryM6HFAj+HYDd0OcreOq/H3DG7kIWUzZFm1MZSWKdegKblRSj
# AgMBAAGjggM4MIIDNDAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNV
# HSUBAf8EDDAKBggrBgEFBQcDCDCCAb8GA1UdIASCAbYwggGyMIIBoQYJYIZIAYb9
# bAcBMIIBkjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQ
# UzCCAWQGCCsGAQUFBwICMIIBVh6CAVIAQQBuAHkAIAB1AHMAZQAgAG8AZgAgAHQA
# aABpAHMAIABDAGUAcgB0AGkAZgBpAGMAYQB0AGUAIABjAG8AbgBzAHQAaQB0AHUA
# dABlAHMAIABhAGMAYwBlAHAAdABhAG4AYwBlACAAbwBmACAAdABoAGUAIABEAGkA
# ZwBpAEMAZQByAHQAIABDAFAALwBDAFAAUwAgAGEAbgBkACAAdABoAGUAIABSAGUA
# bAB5AGkAbgBnACAAUABhAHIAdAB5ACAAQQBnAHIAZQBlAG0AZQBuAHQAIAB3AGgA
# aQBjAGgAIABsAGkAbQBpAHQAIABsAGkAYQBiAGkAbABpAHQAeQAgAGEAbgBkACAA
# YQByAGUAIABpAG4AYwBvAHIAcABvAHIAYQB0AGUAZAAgAGgAZQByAGUAaQBuACAA
# YgB5ACAAcgBlAGYAZQByAGUAbgBjAGUALjALBglghkgBhv1sAxUwHwYDVR0jBBgw
# FoAU9LbhIB3+Ka7S5GGlsqIlssgXNW4wHQYDVR0OBBYEFFZTD8HGB6dN19huV3KA
# UEzk7J7BMHEGA1UdHwRqMGgwMqAwoC6GLGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9zaGEyLWFzc3VyZWQtdHMuY3JsMDKgMKAuhixodHRwOi8vY3JsNC5kaWdpY2Vy
# dC5jb20vc2hhMi1hc3N1cmVkLXRzLmNybDCBhQYIKwYBBQUHAQEEeTB3MCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wTwYIKwYBBQUHMAKGQ2h0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJBc3N1cmVkSURU
# aW1lc3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggEBAC6DoUQFSgTjuTJS
# +tmB8Bq7+AmNI7k92JKh5kYcSi9uejxjbjcXoxq/WCOyQ5yUg045CbAs6Mfh4szt
# y3lrzt4jAUftlVSB4IB7ErGvAoapOnNq/vifwY3RIYzkKYLDigtgAAKdH0fEn7QK
# aFN/WhCm+CLm+FOSMV/YgoMtbRNCroPBEE6kJPRHnN4PInJ3XH9P6TmYK1eSRNfv
# bpPZQ8cEM2NRN1aeRwQRw6NYVCHY4o5W10k/V/wKnyNee/SUjd2dGrvfeiqm0kWm
# VQyP9kyK8pbPiUbcMbKRkKNfMzBgVfX8azCsoe3kR04znmdqKLVNwu1bl4L4y6kI
# bFMJtPcwggUxMIIEGaADAgECAhAKoSXW1jIbfkHkBdo2l8IVMA0GCSqGSIb3DQEB
# CwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQg
# SUQgUm9vdCBDQTAeFw0xNjAxMDcxMjAwMDBaFw0zMTAxMDcxMjAwMDBaMHIxCzAJ
# BgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5k
# aWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBU
# aW1lc3RhbXBpbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC9
# 0DLuS82Pf92puoKZxTlUKFe2I0rEDgdFM1EQfdD5fU1ofue2oPSNs4jkl79jIZCY
# vxO8V9PD4X4I1moUADj3Lh477sym9jJZ/l9lP+Cb6+NGRwYaVX4LJ37AovWg4N4i
# Pw7/fpX786O6Ij4YrBHk8JkDbTuFfAnT7l3ImgtU46gJcWvgzyIQD3XPcXJOCq3f
# QDpct1HhoXkUxk0kIzBdvOw8YGqsLwfM/fDqR9mIUF79Zm5WYScpiYRR5oLnRlD9
# lCosp+R1PrqYD4R/nzEU1q3V8mTLex4F0IQZchfxFwbvPc3WTe8GQv2iUypPhR3E
# HTyvz9qsEPXdrKzpVv+TAgMBAAGjggHOMIIByjAdBgNVHQ4EFgQU9LbhIB3+Ka7S
# 5GGlsqIlssgXNW4wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wEgYD
# VR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYB
# BQUHAwgweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5k
# aWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4
# oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dEFzc3VyZWRJRFJvb3RDQS5jcmwwUAYDVR0gBEkwRzA4BgpghkgBhv1sAAIEMCow
# KAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCwYJYIZI
# AYb9bAcBMA0GCSqGSIb3DQEBCwUAA4IBAQBxlRLpUYdWac3v3dp8qmN6s3jPBjdA
# hO9LhL/KzwMC/cWnww4gQiyvd/MrHwwhWiq3BTQdaq6Z+CeiZr8JqmDfdqQ6kw/4
# stHYfBli6F6CJR7Euhx7LCHi1lssFDVDBGiy23UC4HLHmNY8ZOUfSBAYX4k4YU1i
# RiSHY4yRUiyvKYnleB/WCxSlgNcSR3CzddWThZN+tpJn+1Nhiaj1a5bA9FhpDXzI
# AbG5KHW3mWOFIoxhynmUfln8jA/jb7UBJrZspe6HUSHkWGCbugwtK22ixH67xCUr
# RwIIfEmuE7bhfEJCKMYYVs9BNLZmXbZ0e/VWMyIvIjayS6JKldj1po5SMYICTTCC
# AkkCAQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZ
# MBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hB
# MiBBc3N1cmVkIElEIFRpbWVzdGFtcGluZyBDQQIQBM0/hWiudsYbsP5xYMynbTAN
# BglghkgBZQMEAgEFAKCBmDAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJ
# KoZIhvcNAQkFMQ8XDTIwMTEyNDIwMDgyMlowKwYLKoZIhvcNAQkQAgwxHDAaMBgw
# FgQUAyW9UF7aljAtwi9PoB5MKL4oNMUwLwYJKoZIhvcNAQkEMSIEII5QvXgmPSCi
# awOMgJ77q+DBnlXKbTTH23uYTCMsJBX3MA0GCSqGSIb3DQEBAQUABIIBAGOry6nJ
# Fvb2Zto/SHkdMImn8Hl/mxMldxp+UsAkWqjffO5q9PdQHKYsABAHlSPLj6HeeZ49
# uKAFvkBoBgVvhambd8CABTSzrV/XHUdaFY0oWTKPVgTepLIkJrk7fMAIjQ6suOSQ
# X2yTibr7h+YtRAqBh2CDO/ZOxSc0yjaUPVXzsNM6klZqDRWnZx5lfronrYV8hzeT
# 0iBfizE2Gi/XJb8m4pvC5nZyFOaCXRXw2hhxx2HDtniWbnxq+p5tB6T1C/Ww1KcZ
# NBRordOXJ50orIuMH0Pu2aQLd3mWNWbbEuh90tR5W4/AB9/WgTmluulYiOLJDhzJ
# zsXhWgcCzjjXTCg=
# SIG # End signature block
