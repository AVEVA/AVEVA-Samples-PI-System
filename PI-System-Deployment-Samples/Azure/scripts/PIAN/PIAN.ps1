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
# MIIbzAYJKoZIhvcNAQcCoIIbvTCCG7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCzMlnsQpbCqiep
# 1Jfw5YDa9rhmxpod6OXtlxqs8zXXgqCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIDfCJtRCH/qi
# NLs9Dyc0Jv73BOREROth7ptugPMqp/yaMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQBG
# wRqHZpTenB7n3Pdgba/06GgRAlKMgWkd96fFPegK2V7x8uBWB58G7t7ExTEyeI1+
# uSP/k6mR5UFrOaqQEusgN/fSYEL2d1OKNJBQhqVdzbXR7lzNhkOg+eyMUxcbMn0I
# uTUAe6RM5tiBbDK1Y9QnHPoNigmjfm4bqEBZY/VZQyrM47qwM6gVuv8IOK/CJk2x
# 7bBGaT60b+FFDRFn6feRj3hyI39VcCTO4Tu/U/6/qR6uQIAygJfWs528x7vXbrLs
# 6xiUSFzs8W40ejUXypbHbsTt4E2wXG97NSxWFgNvfPXifm6+1675CjZhRIwDMNeb
# yw2T9aASTnOREyiaCceVoYIOPTCCDjkGCisGAQQBgjcDAwExgg4pMIIOJQYJKoZI
# hvcNAQcCoIIOFjCCDhICAQMxDTALBglghkgBZQMEAgEwggEPBgsqhkiG9w0BCRAB
# BKCB/wSB/DCB+QIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgQhBD
# Q4W9wg9ev28OkSFzOA7j3PKIHrMH3Lg2ePKEr7cCFQDHSA+fP50yAzyJA118qbdW
# BgB1QBgPMjAxOTEwMDgxOTU2MTJaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
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
# DQEJBTEPFw0xOTEwMDgxOTU2MTJaMC8GCSqGSIb3DQEJBDEiBCCRgKZ7BOJgdQQq
# 4xt9R6n8o8pQUup5vLtN6IkE674pTjA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# a6F0VACzHbdWJABRgmOCdwobXBmi16thazZ+UUtN78KhkRgngahvCpZjdl3+pdAB
# qWTa13Q3vQM1IHI+F/yV8gAxkJ/7MK7S8Ex7vGebNW+i99L+jZWf97FGHbSWV6SX
# 3djvk9Xmum2um4zfKBVBid+pomNU8qv6H8vinT7wQnDPLGRHkFCUmfOD1fY1ydBj
# NBB2WYusTZtqvk6YePWL6Xr0WQWMLykastCTefL3Zj9Q9xBeccOfWBvPOwezJjcc
# H9yWbu7Kno1o42H+pnW8p4X2hPx1sOrE8JJ4cUqPG8tEcVA5F+T/iLd5SN0zpVWX
# WwKpY/5VQ6t4KayIX3j7Mw==
# SIG # End signature block
