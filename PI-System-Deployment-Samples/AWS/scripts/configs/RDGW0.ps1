[CmdletBinding()]
param(
    # Name of AF Server for Analysis Server
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DefaultPIAFServer,

    # Default PI Data Archive
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DefaultPIDataArchive,

    # Setup Kit PI Installer Product ID
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$SetupKitsS3PIProductID,

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix,

	# Domain Net BIOS Name
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DomainNetBiosName,
	
    # Domain Admin Username
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DomainAdminUsername
)

try {
    # Set to enable catch to Write-AWSQuickStartException
    $ErrorActionPreference = "Stop"
    Import-Module $psscriptroot\IPHelper.psm1

    # Set Local Configuration Manager
    Configuration LCMConfig {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            CertificateID      = (Get-ChildItem Cert:\LocalMachine\My)[0].Thumbprint
        }
    }
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
    Configuration RDGW0Config {

		param(
            # PI Analysis Service Default settings
            [string]$afServer = $DefaultPIAFServer,
            [string]$piServer = $DefaultPIDataArchive
        )

        Import-DscResource -ModuleName PSDesiredStateConfiguration
        Import-DscResource -ModuleName xStorage -ModuleVersion 3.4.0.0
        Import-DscResource -ModuleName xComputerManagement -ModuleVersion 4.1.0.0
        Import-DscResource -ModuleName xPendingReboot -ModuleVersion 0.4.0.0
        Import-DscResource -ModuleName xRemoteDesktopSessionHost -ModuleVersion 1.9.0.0

        Node $env:COMPUTERNAME {

            # Check for new volumes. The uninitialized disk number may vary depending on EC2 type (i.e. temp disk or no temp disk). This logic will test to find the disk number of an uninitialized disk.
            $disks = Get-Disk | Where-Object 'partitionstyle' -eq 'raw' | Sort-Object number
            if ($disks) {
                # Wait for Data Disk availability
                xWaitforDisk Volume_F {
                    DiskID           = $disks[0].number
                    retryIntervalSec = 30
                    retryCount       = 20
                }

                # Format Data Disk
                xDisk Volume_F {
                    DiskID      = $disks[0].number
                    DriveLetter = 'F'
                    FSFormat    = 'NTFS'
                    FSLabel     = 'Apps'
                    DependsOn   = '[xWaitforDisk]Volume_F'
                }
            }

            WindowsFeatureSet AdminTools {
                Name   = 'RSAT-AD-Tools', 'RSAT-AD-PowerShell', 'RSAT-ADDS', 'RSAT-ADDS-Tools', 'RSAT-DNS-Server'
                Ensure = 'Present'
            }

            # PI Client Configuration settings
            $archiveFilesSize = '256'
            $PIHOME = 'C:\Program Files (x86)\PIPC'
            $PIHOME64 = 'C:\Program Files\PIPC'

            # Install PI System Client Tools
            Package PIClientTools {
                Name       = 'PI Server 2018 Installer'
                Path       = 'C:\media\PIServer\PIServerInstaller.exe'
                ProductId  = $SetupKitsS3PIProductID
                Arguments = "/quiet ADDLOCAL=FD_AFExplorer,FD_AFAnalysisMgmt,PiPowerShell,pismt3 PIHOME=""$PIHOME"" PIHOME64=""$PIHOME64"" SENDTELEMETRY=""0"" AFACKNOWLEDGEBACKUP=""1"" PI_ARCHIVESIZE=""$archiveFilesSize"" AFSERVER=""$afServer"" PISERVER=""$piServer"""
                Ensure     = 'Present'
                LogPath    = "$env:ProgramData\PIServer_install.log"
                ReturnCode = 0, 3010
            }

            # Creates and configures a remote Desktop Services Collection for multiple concurrent users.
            WindowsFeatureset RDS-Features {
                Name   = 'Remote-Desktop-Services', 'RDS-RD-Server', 'RDS-Connection-Broker', 'RDS-Web-Access', 'RDS-Licensing'
                Ensure = 'Present'
            }

            WindowsFeature RSAT-RDS-Tools {
                Ensure               = 'Present'
                Name                 = 'RSAT-RDS-Tools'
                IncludeAllSubFeature = $true
            }

            # Get the FQDN for the EC2 machine needed by RDS setup.
            $hostFQDN = [System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName

            xRDSessionDeployment Deployment {
                SessionHost      = $hostFQDN
                ConnectionBroker = $hostFQDN
                WebAccessServer  = $hostFQDN
                DependsOn        = '[windowsFeatureset]RDS-Features'
            }

            xRDSessionCollection Collection {
                CollectionName        = 'Tenant Jump Box'
                CollectionDescription = 'Remote Desktop Services instance for Remote Desktop jumpbox access.'
                SessionHost           = $hostFQDN
                ConnectionBroker      = $hostFQDN
                DependsOn             = '[xRDSessionDeployment]Deployment'
            }

            xRDSessionCollectionConfiguration CollectionConfiguration {
                CollectionName                 = 'Tenant Jump Box'
                CollectionDescription          = 'Remote Desktop Services instance for Remote Desktop jumpbox access.'
                ConnectionBroker               = $hostFQDN
                AutomaticReconnectionEnabled   = $true
                ClientDeviceRedirectionOptions = 'Drive,Clipboard'
                IdleSessionLimitMin            = 120
                DisconnectedSessionLimitMin    = 1440
                TemporaryFoldersDeletedOnExit  = $false
                SecurityLayer                  = 'SSL'
                DependsOn                      = '[xRDSessionCollection]Collection'
            }

            # Writes output to the AWS CloudFormation Init Wait Handle (indicating script completed).
            Script Write-AWSQuickStartStatus {
                GetScript  = {@( Value = 'WriteAWSQuickStartStatus' )}
                TestScript = {$false}
                SetScript  = {

                    # Ping WaitHandle to increment Count and indicate DSC has completed.
                    # Use DSC Configuration name 'rdgw0config' to generate unique ID and register as a unique signal. See Ref for details: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-signal.html
                    Write-Verbose -Message "Getting Handle" -Verbose
                    $handle = Get-AWSQuickStartWaitHandle -ErrorAction SilentlyContinue

                    Write-Verbose -Message "Signalling AWS WaitCondition to inidicate script complete." -Verbose
                    Invoke-Expression "cfn-signal.exe -e 0 -i 'rdgw0config' '$handle'"

                    # Write to Application Log to record status update locally.
                    $CheckSource = Get-EventLog -LogName Application -Source AWSQuickStartStatus -ErrorAction SilentlyContinue
					if (!$CheckSource) {New-EventLog -LogName Application -Source 'AWSQuickStartStatus' -Verbose}  # Check for source to avoid throwing exception if already present.
                    Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message "Write-AWSQuickStartStatus function was triggered."
                }
                # Ensures this resource only triggers after all resources successfully complete.
                DependsOn  = '[xWaitforDisk]Volume_F', '[xDisk]Volume_F', '[WindowsFeatureSet]AdminTools', '[Package]PIClientTools', '[WindowsFeatureset]RDS-Features', '[WindowsFeature]RSAT-RDS-Tools', '[xRDSessionDeployment]Deployment', '[xRDSessionCollection]Collection', '[xRDSessionCollectionConfiguration]CollectionConfiguration'
            }

            xPendingReboot Reboot1 {
                Name = 'RebootServer'
                DependsOn = '[Script]Write-AWSQuickStartStatus'
            }

        }
    }

    # Compile and Execute Configuration
    RDGW0Config -ConfigurationData $ConfigurationData
    Start-DscConfiguration -Path .\RDGW0Config -Wait -Verbose -Force -ErrorVariable ev
}

catch {
    # If any expectations are thrown, output to CloudFormation Init.
    $_ | Write-AWSQuickStartException
}
# SIG # Begin signature block
# MIIcVgYJKoZIhvcNAQcCoIIcRzCCHEMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDqDEag8eCNlv+/
# kVtMJ7wcaZfYqwpyZk4Z5mk+hn76nKCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg0jaYlKM1C4Of
# Y9YF3oTFvKN+h06sS2N4j6dkamow358wMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAAOJ
# i7+3OPj5sCsm1zaFiypwA+GJnrrvlXVmN+rTKM6J648ZnmWV0+V6iLkiwrcXJtu0
# 7CU2BOpFW5aJC08iZ2yIeqKBgLR91AsrnpeRI2SBsg3WyHJj5fML3VlEtEdw6QYP
# /BkdxyDUIy6wMbHmshERFyKxWolWuC2Qw1juu/yPrMZmjK7ebPQkOlIle8MQP6vn
# ezOY6Za+IHYgx6PqJmDMjRA8F3NlG2cAfic6g/c+t1EhAF0GvQ8V/1tlrzcjaAlD
# 2WGD7dyqk4ujNNsne1qt4dzGFPNLIjaIzh2VZ+JekpkiInkk9jpOCh5isb9o6nhR
# vrSFfyK8dTJtb1zhCl6hgg7IMIIOxAYKKwYBBAGCNwMDATGCDrQwgg6wBgkqhkiG
# 9w0BBwKggg6hMIIOnQIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEE
# oGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQg+/3LNT8/bY7H
# JK40CPCIXU1m65WQiXx9Qz4EiopbuV8CEEZOikeLGuKD0HZQ1hG31joYDzIwMjAx
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
# BBQDJb1QXtqWMC3CL0+gHkwovig0xTAvBgkqhkiG9w0BCQQxIgQgjWOkR2GOS1+A
# NT3ovEyM0tBcvr7sWz9a0CpMSze9q14wDQYJKoZIhvcNAQEBBQAEggEAvjNI8NgC
# NN8nKB9mgztlG8ZYzQwPlZVoPf6RQkou4v7oLc1C4CSHBe2NxT5ll1Bv0O09kECK
# m/5TSebM7UwtEIvqRyh3wB3JOFmHMQodJO608BCDYmjxxT0c3R8LYa5J46xoohE1
# 4yAz6hWapg1aP2mYJHmLdYyF6pwhGueUprA7tbFYhGyu45FVyxXmAJlnHbrUYr2z
# HipYv80MhF02Yeep8YqmUUpZi1JhxE9X2K6HPSaMZOwYO9VbsJoCENF4jCqY28PN
# yzLBlDXjmBA11saztMcDaUnh6QfeIm8zT5+OnFMkXfqz1+6a8NbRfukfDY+2i1Ge
# E4oODwDR4PYGiQ==
# SIG # End signature block
