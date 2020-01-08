Configuration PIAN
{
    param(
        # PI Analysis Default settings
		[string]$PIPath,
		[string]$PIProductID,

        [Parameter(Mandatory=$true)]
        [string]$DefaultPIAFServer,
        [Parameter(Mandatory=$true)]
        [string]$DefaultPIDataArchive,
        [Parameter(Mandatory=$true)]
        [string]$PIVisionServer,        
        [Parameter(Mandatory=$true)]
        [string]$PIAnalysisServer,

        [string]$PIHOME = 'F:\Program Files (x86)\PIPC',
        [string]$PIHOME64 = 'F:\Program Files\PIPC',

        [Parameter(Mandatory=$true)]
        [PSCredential]$svcCredential,
        [pscredential]$runAsCredential,

        [Parameter(Mandatory)]
        [string]$OSIsoftTelemetry,
   
        [Parameter(Mandatory=$true)]
        [string]$TestFileName,
        [Parameter(Mandatory=$true)]
        [string]$RDSName,
        [Parameter(Mandatory=$true)]
        [string]$deployHA
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName xStorage
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName XActiveDirectory
	Import-DscResource -ModuleName cchoco


    # Generate credential for PI Analysis Service Account
    $DomainNetBiosName = ((Get-WmiObject -Class Win32_NTDomain -Filter "DnsForestName = '$((Get-WmiObject -Class Win32_ComputerSystem).Domain)'").DomainName)

    # Extracts username only (no domain net bios name)
    $PIANSvcAccountUserName = $svcCredential.Username
    # Create credential with Domain Net Bios Name included.
    $domainServiceAccountCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$PIANSvcAccountUserName", $svcCredential.Password)
    
    $EventLogSource = 'PISystemDeploySample'
    $DomainAdminUsername = $runAsCredential.UserName
    $TestRunnerAccount = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$DomainAdminUsername", $runAsCredential.Password)

    Node localhost {
        
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = "ContinueConfiguration"
        }

        #region ### 1. VM PREPARATION ###
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

        # 1B. Open PI Analytics Firewall Rules
        xFirewall PIAFAnalysisFirewallRule {
            Direction   = 'Inbound'
            Name        = 'PI-System-PI-AF-Analysis-TCP-In'
            DisplayName = 'PI System PI AF Analysis (TCP-In)'
            Description = 'Inbound rule for PI AF Analysis to allow TCP traffic access to the PI AF Server.'
            Group       = 'PI Systems'
            Enabled     = 'True'
            Action      = 'Allow'
            Protocol    = 'TCP'
            LocalPort   = '5463'
            Ensure      = 'Present'
        }
        #endregion ### 1. VM PREPARATION ###

        #region ### 2. INSTALL AND SETUP ###
        # 2A i. Installing the RSAT tools for AD Cmdlets
        WindowsFeature ADPS {
            Name   = 'RSAT-AD-PowerShell'
            Ensure = 'Present'
        }

        # 2A ii. Create PI Analysis Service Account
        xADUser ServiceAccount_PIAN {
            DomainName                    = $DomainNetBiosName
            UserName                      = $svcCredential.Username
            CannotChangePassword          = $true
            Description                   = 'PI Analysis service account.'
            DomainAdministratorCredential = $runAsCredential
            Enabled                       = $true
            Ensure                        = 'Present'
            Password                      = $svcCredential
            DependsOn                     = '[WindowsFeature]ADPS'
        }

        # 2A iii. Add PI Analysis Service account to the AD Group mapped to the PI Identity "PIPointsAnalysisGroup"
        xADGroup CreateANServersGroup {
            GroupName        = 'PIPointsAnalysisCreator'
            Description      = 'Identity for PIACEService, PIAFService and users that can create and edit PI Points'
            Category         = 'Security'
            Ensure           = 'Present'
            GroupScope       = 'Global'
            MembersToInclude = $PIANSvcAccountUserName
            Credential       = $runAsCredential
            DependsOn        = '[WindowsFeature]ADPS'
        }

        # 2B. Installing Chocolatey to facilitate package installs.
		cChocoInstaller installChoco {
			InstallDir = 'C:\ProgramData\chocolatey'
		}

		# 2C. Install .NET Framework 4.8
		cChocoPackageInstaller 'dotnetfx' {
            Name     = 'netfx-4.8-devpack'
            Ensure   = 'Present'
            Version  = '4.8.0.20190930'
            DependsOn = '[cChocoInstaller]installChoco'
		}

        xPendingReboot RebootDotNet {
            Name      = 'RebootDotNet'
            DependsOn = '[cChocoPackageInstaller]dotnetfx'
        }

        # 2D. Install PI System Client Tools
        # PI Analysis service account updated with Service resource to avoid passing plain text password.
        Package PISystem {
            Name                 = 'PI Server 2018 Installer'
            Path                 = $PIPath
            ProductId            = $PIProductID
            Arguments            = "/silent ADDLOCAL=PIAnalysisService,FD_AFExplorer,FD_AFAnalysisMgmt,PiPowerShell PIHOME=""$PIHOME"" PIHOME64=""$PIHOME64"" AFSERVER=""$DefaultPIAFServer"" PISERVER=""$DefaultPIDataArchive"" PI_ARCHIVESIZE=""1024"" SENDTELEMETRY=""$OSIsoftTelemetry"" AFACKNOWLEDGEBACKUP=""1"" PIANALYSIS_SERVICEACCOUNT=""$($domainServiceAccountCredential.username)"" PIANALYSIS_SERVICEPASSWORD=""$($domainServiceAccountCredential.GetNetworkCredential().Password)"""
            Ensure               = 'Present'
            PsDscRunAsCredential = $runAsCredential  # Admin creds due to limitations extracting install under SYSTEM account.
            ReturnCode           = 0, 3010, 1641
            DependsOn            = '[xDisk]Volume_F', '[xPendingReboot]RebootDotNet'
        }

        # Updating RunAs account for PI Analytics
        Service UpdateANServiceAccount {
            Name = 'PIAnalysisManager'
            StartupType = 'Automatic'
            State = 'Running'
            Ensure = 'Present'
            Credential = $domainServiceAccountCredential
            DependsOn = '[Package]PISystem'
        }

        # 2E. Initiate any outstanding reboots.
        xPendingReboot Reboot1 {
            Name      = 'RebootServer'
            DependsOn = '[Package]PISystem'
        }
        #endregion ### 2. INSTALL AND SETUP ###

        #region DeploymentTests
        # 3B Install visual studio 2017 build tools for tests.
        cChocoPackageInstaller 'visualstudio2017buildtools' {
            Name = 'visualstudio2017buildtools'
            DependsOn = '[cChocoInstaller]installChoco'
        }

        # 3C Obtain & Install PI Vision certificate
        Script ConfigurePIVisionAccess {
            GetScript = {
                return @{
                    Value = 'ConfigurePIVisionAccess'
                }
            }

            TestScript = {
                $FileName = $Using:TestFileName
                $TestFileNameArray = $FileName.Split('.')
                $TestDir = $TestFileNameArray[0]

                return (Test-Path -LiteralPath C:\$TestDir\testResults)
            }

            SetScript = {
                Try {
                    [Uri]$Uri  = "https://$Using:PIVisionServer" 
                    [string]$PIVSServer = "$Using:PIVisionServer.com"
                    $request = [System.Net.HttpWebRequest]::Create($uri)

                    #Get PIVision certificate
                    try
                    {
                        #Make the request but ignore (dispose it) the response, since we only care about the service point
                        $request.GetResponse().Dispose()
                    }
                    catch [System.Net.WebException]
                    {
                        if ($_.Exception.Status -eq [System.Net.WebExceptionStatus]::TrustFailure)
                        {
                            #Ignore trust failures, since we only want the certificate, and the service point is still populated at this point
                        }
                        else
                        {								
                            Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Error -EventId 0 -Message  $_
                        }
                    }

                    #Install PIVision certificate
                    try {
                        #The ServicePoint object should now contain the Certificate for the site.
                        $servicePoint = $request.ServicePoint

                        $bytes = $servicePoint.Certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)
                        set-content -value $bytes -encoding byte -path "D:\pivs.cer"
                        Import-Certificate -FilePath D:\pivs.cer -CertStoreLocation Cert:\LocalMachine\Root
                    }
                    catch {
                        Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Error -EventId 0 -Message  $_
                    }

                    #Add PIVision to trusted sites
                    try {
                        Set-Location "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
                        Set-Location ZoneMap\Domains
                        New-Item $PIVSServer
                        Set-Location $PIVSServer
                        New-Item www
                        Set-Location www
                        New-ItemProperty . -Name https -Value 2 -Type DWORD

                        #Let machine trust UNC paths
                        Set-Location "HKCU:\Software\Microsoft\Windows\"
                        Set-Location "CurrentVersion"
                        Set-Location "Internet Settings"
                        Set-ItemProperty ZoneMap UNCAsIntranet -Type DWORD 1
                        Set-ItemProperty ZoneMap IntranetName -Type DWORD 1
                    }
                    catch {
    
                        Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Error -EventId 0 -Message  $_
                    }
                }
                Catch {
                    Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Error -EventId 0 -Message  $_
                }
            }
            DependsOn  = '[Package]PISystem', '[xPendingReboot]Reboot1'
            PsDscRunAsCredential = $TestRunnerAccount
        }

        # 3D Run tests
        Script DeploymentTests {
            GetScript = {
                return @{
                    Value = 'DeploymentTests'
                }
            }

            TestScript = {
                $FileName = $Using:TestFileName
                $TestFileNameArray = $FileName.Split('.')
                $TestDir = $TestFileNameArray[0]

                return (Test-Path -LiteralPath C:\$TestDir\testResults)
            }

            SetScript = {
                Try {
                    $FileName = $Using:TestFileName
                    $TestFileNameArray = $FileName.Split('.')
                    $TestDir = $TestFileNameArray[0]

                    # Check Event Log souce, create if not present
                    $CheckSource = Get-EventLog -LogName Application -Source "$Using:EventLogSource" -ErrorAction SilentlyContinue
                    if (!$CheckSource) {New-EventLog -LogName Application -Source "$Using:EventLogSource" -Verbose}  

                    Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Information -EventId 0 -Message "Deployment tests starting. DomainName: $Using:DomainNetBiosName UserName: $Using:DomainAdminUserName TestFileName $Using:TestFileName TestDir $TestDir DefaultPIDataArchive $Using:DefaultPIDataArchive DefaultPIAFServer $Using:DefaultPIAFServer PIVisionServer $PIVisionServer PIAnalysisServer $PIAnalysisServer"

                    #Expand test zip file
                    Expand-Archive -LiteralPath "D:\$TestFileName" -DestinationPath c:\ -Force

                    #Update config with EC2 machine names
                    (Get-Content C:\$TestDir\source\App.config).replace('Enter_Your_PIDataArchive_Name_Here', $Using:DefaultPIDataArchive) | Set-Content C:\$TestDir\source\App.config
                    (Get-Content C:\$TestDir\source\App.config).replace('Enter_Your_AFServer_Name_Here', $Using:DefaultPIAFServer) | Set-Content C:\$TestDir\source\App.config
                    (Get-Content C:\$TestDir\source\App.config).replace('Enter_Analysis_Service_Machine_Name_Here', $Using:PIAnalysisServer ) | Set-Content C:\$TestDir\source\App.config

                    $deployHA = $Using:deployHA
                    if($deployHA -eq 'false')	{
                        (Get-Content C:\$TestDir\source\App.config).replace('key="PIWebAPI" value=""', "key=""PIWebAPI"" value=""$Using:PIVisionServer""") | Set-Content C:\$TestDir\source\App.config
                        (Get-Content C:\$TestDir\source\App.config).replace('key="PIVisionServer" value=""', "key=""PIVisionServer"" value=""https://$Using:PIVisionServer/PIVision""") | Set-Content C:\$TestDir\source\App.config
                    }

                    (Get-Content C:\$TestDir\source\App.config).replace('key="SkipCertificateValidation" value=""', 'key="SkipCertificateValidation" value="True"') | Set-Content C:\$TestDir\source\App.config

                    #Run tests
                    Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Information -EventId 0 -Message "Beginning tests"
                    &C:\PI-System-Deployment-Tests-master\scripts\run.ps1 -f

                    # Copy test result to remote desktop gateway server
                    Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Information -EventId 0 -Message "About to create directory \\$Using:RDSName\\C$\TestResults\"
                    New-Item -ItemType directory -Path "\\$Using:RDSName\\C$\TestResults\" -Force
                    Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Information -EventId 0 -Message "Created directory, about to copy C:\$TestDir\testResults\*.html to \$Using:RDSName\\C$\TestResults\"
                    Copy-Item -Path "C:\$TestDir\testResults\*.html" -Destination "\\$Using:RDSName\\C$\TestResults\"

                    Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Information -EventId 0 -Message "Tests end."
                }
                Catch {
                    Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Error -EventId 0 -Message  $_
                }
            }
            DependsOn  = '[Package]PISystem', '[cChocoPackageInstaller]visualstudio2017buildtools', '[xPendingReboot]Reboot1'
            PsDscRunAsCredential = $TestRunnerAccount
        }
        #endregion

        

        
    }
}

# SIG # Begin signature block
# MIIbywYJKoZIhvcNAQcCoIIbvDCCG7gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAUASVpvYF1lJue
# GCTQzS118vBllFhFEKWppPQN04qOqqCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJ527Rh2Oeu6
# 209UhJPJUTmYhNOR7siHRElj43DAIEjNMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQBD
# A6SJhsPLhHZQKt7mx6UrPpq1qLJV4QYLug2enQNc4SKFb48DpIz/NvCoO6NZAJBS
# t8XE+0uldZWqCBY9Auf5kN957OP7gJS4P2DkIZpDR4OPjCYsxAX67qdPPEb9hvVh
# V/1Xk2adn/WUiL+USawtRuw5bH/hMIwILSNcNamebLs7WDpGy1QE26H1VHBspwzI
# 8uaQFD3Pctuq2p7La06QEeY5u9cSq7iuHcXoIRsJz24aa/hF1H8Ng0WSHCe9Y/L2
# oasExxQ5Ag1JSyRejKeUoL1HEGkcJTasVK6Pn30ESUdzIuMOoirGAGXnA0a4fa2G
# QuPdTMRnalB1Axcs7hv2oYIOPDCCDjgGCisGAQQBgjcDAwExgg4oMIIOJAYJKoZI
# hvcNAQcCoIIOFTCCDhECAQMxDTALBglghkgBZQMEAgEwggEOBgsqhkiG9w0BCRAB
# BKCB/gSB+zCB+AIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgrevP
# uClvFjn9gDHklyeZXJ1YjgneGxbadB0B27tAufICFCTvyP2tH5Syf0OGOOdcH1OJ
# z26MGA8yMDIwMDEwNjE1Mzk0N1owAwIBHqCBhqSBgzCBgDELMAkGA1UEBhMCVVMx
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
# AQkFMQ8XDTIwMDEwNjE1Mzk0N1owLwYJKoZIhvcNAQkEMSIEIPnXHRJw4157TLD0
# DEhtO2p9UF/GzJUoqLBPKeHfxx0IMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMR0
# znYAfQI5Tg2l5N58FMaA+eKCATz+9lPvXbcf32H4MAsGCSqGSIb3DQEBAQSCAQBu
# gAl9IvzjEhbL5GxqoF/79rR00EIWLBj2XPAS96mbXUFN+zbgt3kKCpoZK/zYaRge
# Ab451GNqJVIcHd5+wusn5Otp9XsrvJH7ILwRu2XEnvgL94HiaPFsJZ2dF+dXMVGX
# miXt5RpakCfJ2pIAZH7xaaZuEPfVjgeedjR/m7atQG9RaFOJj0WlzfQVNey9VNqL
# h+O1Y9z0t3tCkTXDtCnAXnmoRh+BW32t9PiXmSRrg3/EUSvzmvaMQHsvt8eUqJmv
# OBK66sb8jL1lnNd34gle5p62Mbmv25il7y8kb10CFZyWeZTzcJKZ9zvxwk93N/am
# ykILKugBtrq+/xRXdZGU
# SIG # End signature block
