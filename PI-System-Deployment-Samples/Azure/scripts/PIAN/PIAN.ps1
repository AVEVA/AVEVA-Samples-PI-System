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
                        (Get-Content C:\$TestDir\source\App.config).replace('key="PIVisionServer" value=""', "key=""PIVisionServer"" value=""https://$Using:PIVisionServer/PIVision""") | Set-Content C:\$TestDir\source\App.config
                    }

                    (Get-Content C:\$TestDir\source\App.config).replace('key="SkipCertificateValidation" value=""', 'key="SkipCertificateValidation" value="True"') | Set-Content C:\$TestDir\source\App.config

                    #Run tests
                    Write-EventLog -LogName Application -Source "$Using:EventLogSource" -EntryType Information -EventId 0 -Message "Beginning tests"
                    &C:\PI-System-Deployment-Tests\scripts\run.ps1 -f

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
# MIIcVgYJKoZIhvcNAQcCoIIcRzCCHEMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD+Wr49KI5LpUU9
# Ldn/IzZtfQg1AR0/xs4roXj7Pl8tGqCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgJUXNSjx5C1Jq
# FwGTWBh/p7LW+evOSI2EJIQkG0j6sMQwMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAKt6
# bBDfNzXqTEGZOxKQWjCIzecDR7BzZ6n5vE5Q7iTcfR7uf6Mh205qoiQM/nf3jvhC
# fVuth6S6JqWtFpxgn1G+Xdhp2D+D/qz+9Gs3jULiBKCYADWHrl9YB/b38CNOy1Ih
# D9MUvNQ6irT9hY4GDGXZwm7992VJNfHtpiJDfVVZjX2NeSn4ClJQECM3GgRkHfDb
# cYA/GHehmnw9/ljPIWFyTrw1lyqyqY3xbIkZJSkIMDMLYxW+s7Gou29IWPaPrjf/
# jC6jmIHY1tibjzL7l6EUTktHX8I5JtJjq7yeeTotaMotTYtZEnlg6onvremfwCIt
# AnObmOOZEoT23DkIzvShgg7IMIIOxAYKKwYBBAGCNwMDATGCDrQwgg6wBgkqhkiG
# 9w0BBwKggg6hMIIOnQIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEE
# oGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQgcdzHE1hdxVeq
# uyVKdbpZPjhCcrTsk1mPhsMJqTj/hn0CEBeMlK1d5qRbMAkAnUHSpl8YDzIwMjAx
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
# BBQDJb1QXtqWMC3CL0+gHkwovig0xTAvBgkqhkiG9w0BCQQxIgQgbkr4y7CARX2E
# 6lnKwQqmMY4tKXw4akK3sbmi9XYgFswwDQYJKoZIhvcNAQEBBQAEggEAzsPzm2tf
# oCFjsBVwe8JCRwVZHqo8pj69otDLFyxDncPjOFuiIWfRxlHBy4AApWLPtsIaFieF
# UR35wiD3jC8wF/NcYKek/u6+2+nyzsrI+7WJIBjiAlKoiaBEgAjuum74wdW6B7oi
# jA6VQYGWuFc3gXerg5TRgT1sWGJPp7G8rfYYSVxy2DwwaU/oWzVPxldH31wBWAVj
# 2AKX9ahD1OgVFBiz0VuC30G8vsDo35VGqsNi2n8M/ka7kqxoZGWbQ6Wv1e09RvyF
# P9MUs9/ZUVmH9pJtQY8yNnrPP4h/sdb//+3bA/krrs1Wg9aR53zk/KKidvvSIZ14
# JkoGK/dpgIGagg==
# SIG # End signature block
