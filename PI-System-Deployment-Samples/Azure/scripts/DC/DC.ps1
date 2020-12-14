# From https://github.com/Azure/azure-quickstart-templates/tree/master/active-directory-new-domain
configuration DC
{
   param
   (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [String]$primaryDC,

        [string]$primaryDCIP,

        [Parameter(Mandatory)]
        [PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [PSCredential]$Afcreds,

        [Parameter(Mandatory)]
        [PSCredential]$Ancreds,

        [Parameter(Mandatory)]
        [PSCredential]$Vscreds,

        [Parameter(Mandatory)]
        [PSCredential]$Sqlcreds,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    )

    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xStorage
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xPendingReboot


    [System.Management.Automation.PSCredential]$DomainAdminCreds = New-Object System.Management.Automation.PSCredential ("$DomainName\$($Admincreds.UserName)", $Admincreds.Password)
    [System.Management.Automation.PSCredential]$DomainAfCreds = New-Object System.Management.Automation.PSCredential ("$DomainName\$($Afcreds.UserName)", $Afcreds.Password)
    [System.Management.Automation.PSCredential]$DomainAnCreds = New-Object System.Management.Automation.PSCredential ("$DomainName\$($Ancreds.UserName)", $Ancreds.Password)
    [System.Management.Automation.PSCredential]$DomainVsCreds = New-Object System.Management.Automation.PSCredential ("$DomainName\$($Vscreds.UserName)", $Vscreds.Password)
    [System.Management.Automation.PSCredential]$DomainSqlCreds = New-Object System.Management.Automation.PSCredential ("$DomainName\$($Sqlcreds.UserName)", $Sqlcreds.Password)

    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)
    $domainExists = $null

    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }
        WindowsFeature DNS
        {
            Ensure = "Present"
            Name = "DNS"
        }
        Script EnableDNSDiags
        {
            SetScript = {
                Set-DnsServerDiagnostics -All $true
                Write-Verbose -Verbose "Enabling DNS client diagnostics"
            }
            GetScript =  { @{} }
            TestScript = { $false }
            DependsOn = "[WindowsFeature]DNS"
        }
        WindowsFeature DnsTools
        {
            Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
        }
        if($env:COMPUTERNAME -eq $primaryDC) {
            xDnsServerAddress DnsServerAddressPrimaryDC
            {
                Address        = '127.0.0.1'
                InterfaceAlias = $InterfaceAlias
                AddressFamily  = 'IPv4'
                DependsOn = "[WindowsFeature]DNS"
            }
        }
        else {
            xDnsServerAddress DnsServerAddressSecondaryDC
            {
                Address        = $primaryDCIP
                InterfaceAlias = $InterfaceAlias
                AddressFamily  = 'IPv4'
                DependsOn = "[WindowsFeature]DNS"
            }
        }
        xWaitforDisk Disk2
        {
            DiskID = 2
            RetryIntervalSec =$RetryIntervalSec
            RetryCount = $RetryCount
        }
        xDisk ADDataDisk {
            DiskID = 2
            DriveLetter = "F"
            DependsOn = "[xWaitForDisk]Disk2"
        }
        WindowsFeature ADDSInstall
        {
            Ensure = "Present"
            Name = "AD-Domain-Services"
            DependsOn="[WindowsFeature]DNS"
        }
        WindowsFeature ADDSTools
        {
            Ensure = "Present"
            Name = "RSAT-ADDS-Tools"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }
        WindowsFeature ADAdminCenter
        {
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }
        if($env:COMPUTERNAME -eq $primaryDC)
        {
            xADDomain FirstDC
            {
                DomainName = $DomainName
                DomainAdministratorCredential = $DomainAdminCreds
                SafemodeAdministratorPassword = $DomainAdminCreds
                DatabasePath = "F:\NTDS"
                LogPath = "F:\NTDS"
                SysvolPath = "F:\SYSVOL"
                DependsOn = @("[xDisk]ADDataDisk", "[WindowsFeature]ADDSInstall")
            }

            xADUser ServiceAccount_PIAF {
                DomainName                    = $DomainName
                UserName                      = $AfCreds.Username
                UserPrincipalName             = ($AfCreds.Username + "@" + $DomainName)
                CannotChangePassword          = $true
                Description                   = 'PI AF Server service account.'
                DomainAdministratorCredential = $DomainAdminCreds
                Enabled                       = $true
                Ensure                        = 'Present'
                Password                      = $AfCreds
                DependsOn                     = '[xADDomain]FirstDC'
            }

            xADUser ServiceAccount_PIAN {
                DomainName                    = $DomainName
                UserName                      = $AnCreds.Username
                UserPrincipalName             = ($AnCreds.Username + "@" + $DomainName)
                CannotChangePassword          = $true
                Description                   = 'PI Analysis Server service account.'
                DomainAdministratorCredential = $DomainAdminCreds
                Enabled                       = $true
                Ensure                        = 'Present'
                Password                      = $AnCreds
                DependsOn                     = '[xADDomain]FirstDC'
            }

            xADUser ServiceAccount_PIVS {
                DomainName                    = $DomainName
                UserName                      = $VsCreds.Username
                UserPrincipalName             = ($VsCreds.Username + "@" + $DomainName)
                CannotChangePassword          = $true
                Description                   = 'PI Web API on PI Vision box service account.'
                DomainAdministratorCredential = $DomainAdminCreds
                Enabled                       = $true
                Ensure                        = 'Present'
                Password                      = $VsCreds
                DependsOn                     = '[xADDomain]FirstDC'
            }

            xADUser ServiceAccount_SQL {
                DomainName                    = $DomainName
                UserName                      = $SqlCreds.Username
                UserPrincipalName             = ($SqlCreds.Username + "@" + $DomainName)
                CannotChangePassword          = $true
                Description                   = 'Service account running SQL server'
                DomainAdministratorCredential = $DomainAdminCreds
                Enabled                       = $true
                Ensure                        = 'Present'
                Password                      = $SqlCreds
                DependsOn                     = '[xADDomain]FirstDC'
            }

        }
        else
        {
            xWaitForADDomain CheckIfADForestReady
            {
                DomainName = $DomainName
                RetryCount = 30
                RetryIntervalSec = 30
                DependsOn = "[WindowsFeature]ADDSInstall"
            }
            xADDomainController SecondDC
            {
                DomainName = $DomainName
                DomainAdministratorCredential = $DomainAdminCreds
                SafemodeAdministratorPassword = $DomainAdminCreds
                DatabasePath = "F:\NTDS"
                LogPath = "F:\NTDS"
                SysvolPath = "F:\SYSVOL"
                DependsOn = @("[xDisk]ADDataDisk", "[WindowsFeature]ADDSInstall",'[xWaitForADDomain]CheckIfADForestReady')
            }
        }
   }
}