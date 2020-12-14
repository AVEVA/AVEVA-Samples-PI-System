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

    # Test File Name
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$TestFileName,

    # Domain Admin Username
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DomainAdminUsername,

    # PI Analytics service account name. Also the AWS SSM Parameter Store parameter name. Used to retrieve the account password.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIANServiceAccountName,

    # Domain Net BIOS Name
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$DomainNetBiosName,

    # Domain Controller Name
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()] 
    $DomainControllerServerName,

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix,

    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [ValidateSet('true','false')]
    [string]$DeployHA
)

try {

    # Define Event Log source so it's always available
    $CheckSource = Get-EventLog -LogName Application -Source AWSQuickStartStatus -ErrorAction SilentlyContinue
    if (!$CheckSource) {New-EventLog -LogName Application -Source 'AWSQuickStartStatus' -Verbose}  # Check for source to avoid throwing exception if already present.
    
    # Set to enable catch to Write-AWSQuickStartException
    $ErrorActionPreference = "Stop"

    Import-Module $psscriptroot\IPHelper.psm1

    # Set Local Configuration Manager
    Configuration LCMConfig {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode  = 'ApplyOnly'
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

    # Get exisitng service account password from AWS System Manager Parameter Store.
    $DomainAdminPassword = (Get-SSMParameterValue -Name "/$NamePrefix/$DomainAdminUserName" -WithDecryption $True).Parameters[0].Value
    $PIANServiceAccountPassword = (Get-SSMParameterValue -Name "/$NamePrefix/$PIANServiceAccountName" -WithDecryption $True).Parameters[0].Value

    # Generate credential for domain security group creation.
    $securePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $domainCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$DomainAdminUserName", $securePassword)


    # EC2 Configuration 
    Configuration PIAnalysis0Config {

        param(
            # PI Analysis Service Default settings
            [string]$afServer = $DefaultPIAFServer,
            [string]$piServer = $DefaultPIDataArchive,
            [string]$PIHOME = 'F:\Program Files (x86)\PIPC',
            [string]$PIHOME64 = 'F:\Program Files\PIPC',
            [string]$PIANSvcAccountUserName = $PIANServiceAccountName,
            [string]$PIANSvcAccountPassword = $PIANServiceAccountPassword
        )

        Import-DscResource -ModuleName PSDesiredStateConfiguration
        Import-DscResource -ModuleName xPendingReboot -ModuleVersion 0.4.0.0
        Import-DscResource -ModuleName xStorage -ModuleVersion 3.4.0.0
        Import-DscResource -ModuleName xNetworking -ModuleVersion 5.7.0.0
        Import-DscResource -ModuleName XActiveDirectory -ModuleVersion 3.0.0.0
        Import-DscResource -ModuleName cChoco -ModuleVersion 2.4.0.0
        Import-DscResource -ModuleName xWindowsUpdate

        # Generate credential for PI Analysis Service Account
        $securePIANServiceAccountPassword = ConvertTo-SecureString $PIANSvcAccountPassword -AsPlainText -Force
        $domainServiceAccountCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$PIANSvcAccountUserName", $securePIANServiceAccountPassword) 

        Node $env:COMPUTERNAME {

            #region ### 1. VM PREPARATION ### 
            # 1A. Check for new volumes. The uninitialized disk number may vary depending on EC2 type (i.e. temp disk or no temp disk). This logic will test to find the disk number of an uninitialized disk.
            $disks = Get-Disk | Where-Object {$_.Number -ne 0} | Sort-Object Number
            if ($disks) {
                # Elastic Block Storage for Binary Files
                xWaitforDisk Volume_F {
                    DiskID           = $disks[0].number
                    retryIntervalSec = 30
                    retryCount       = 20
                }
                xDisk Volume_F {
                    DiskID      = $disks[0].number
                    DriveLetter = 'F'
                    FSFormat    = 'NTFS'
                    FSLabel     = 'Apps'
                    DependsOn   = '[xWaitforDisk]Volume_F'
                }
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
                UserName                      = $PIANSvcAccountUserName
                CannotChangePassword          = $true
                Description                   = 'PI Analysis Service account.'
                DomainAdministratorCredential = $domainCredential
                Enabled                       = $true
                Ensure                        = 'Present'
                Password                      = $domainServiceAccountCredential
                DomainController              = $DomainControllerServerName
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
                Credential       = $domainCredential
                DomainController = $DomainControllerServerName
                DependsOn        = '[WindowsFeature]ADPS'
            }
            
            # 2B a. Install Chocolatey
            cChocoInstaller installChoco {
                InstallDir = 'C:\choco'
            }

            # 2B b. Install .NET Framework Developer Pack for COTS.
            Script InstallDevPack {
                GetScript = {
                    return @{
                        Value = 'InstallDevPack'
                    }
                }

                # Forces SetScript execution everytime
                TestScript = {
                    return $false
                }

                SetScript = {
                    Try {
                        choco install netfx-4.8-devpack --pre -Y
                    }
                    Catch {
                        Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message  $_
                    }
                }
                DependsOn  = '[cChocoInstaller]installChoco'
                PsDscRunAsCredential = $domainCredential
            }

            # 2B c. Install visual studio 2017 build tools for COTS.
            cChocoPackageInstaller 'visualstudio2017buildtools' {
                Name = 'visualstudio2017buildtools'
                DependsOn = '[cChocoInstaller]installChoco'
            }

            # 2C. Installl .NET Framwork 4.8
            xHotFix NETFramework {
                Path = 'C:\media\NETFramework\windows10.0-kb4486129.msu'
                Id = 'KB4486129'
                Ensure = 'Present'
            }

            # 2D. Initiate any outstanding reboots.
            xPendingReboot RebootNETFramework {
                Name      = 'PostNETFrameworkInstall'
                DependsOn = '[xHotFix]NETFramework'
            }

            # 2E. Install PI System Client Tools
            Package PISystem {
                Name                 = 'PI Server 2018 Installer'
                Path                 = 'C:\media\PIServer\PIServerInstaller.exe'
                ProductId            = $SetupKitsS3PIProductID
                Arguments            = "/silent ADDLOCAL=PIAnalysisService,FD_AFExplorer,FD_AFAnalysisMgmt,PiPowerShell PIHOME=""$PIHOME"" PIHOME64=""$PIHOME64"" AFSERVER=""$afServer"" PISERVER=""$piServer"" PI_ARCHIVESIZE=""1024"" SENDTELEMETRY=""0"" AFACKNOWLEDGEBACKUP=""1"" PIANALYSIS_SERVICEACCOUNT=""$DomainNetBiosName\$PIANSvcAccountUserName"" PIANALYSIS_SERVICEPASSWORD=""$PIANSvcAccountPassword"""
                Ensure               = 'Present'
                LogPath              = "$env:ProgramData\PIServer_install.log"
                PsDscRunAsCredential = $domainCredential  # Admin creds due to limitations extracting install under SYSTEM account.
                ReturnCode           = 0, 3010
                DependsOn            = '[xDisk]Volume_F', '[cChocoPackageInstaller]visualstudio2017buildtools', '[xHotFix]NETFramework', '[xPendingReboot]RebootNETFramework'
            }

            # 2F. Initiate any outstanding reboots.
            xPendingReboot RebootPISystem { 
                Name      = 'RebootServer'
                DependsOn = '[Package]PISystem'
            }
            #endregion ### 2. INSTALL AND SETUP ###

            #region ### 3. COTS ###
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
						$DeployHA = $Using:DeployHA
						[Uri]$Uri  = "https://PIVS0" 
						[string]$PIVSServer = "PIVS0.com"
						if($DeployHA -eq 'true')	{
							$Uri = "https://PIVS1" 
							$PIVSServer = "PIVS1.com"
						}
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
                                Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message  $_
							}
						}

						#Install PIVision certificate
						try {
							#The ServicePoint object should now contain the Certificate for the site.
							$servicePoint = $request.ServicePoint

							$bytes = $servicePoint.Certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)
							set-content -value $bytes -encoding byte -path "c:\media\pivs.cer"
							Import-Certificate -FilePath c:\media\pivs.cer -CertStoreLocation Cert:\LocalMachine\Root
						}
						catch {
							Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message  $_
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
        
							Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message  $_
						}
					}
					Catch {
						Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message  $_
                    }
				}
				DependsOn  = '[Package]PISystem', '[xPendingReboot]RebootPISystem'
                PsDscRunAsCredential = $domainCredential
			}

            Script CreateCots {
                GetScript = {
                    return @{
                        Value = 'CreateCots'
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

						Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message "COTS start. DomainName: $Using:DomainNetBiosName UserName: $Using:DomainAdminUserName NamePrefix: $Using:NamePrefix TestFileName $Using:TestFileName TestDir $TestDir DefaultPIDataArchive $Using:DefaultPIDataArchive DefaultPIAFServer $Using:DefaultPIAFServer"

						#Expand test zip file
						Expand-Archive -LiteralPath C:\media\TestFile.zip -DestinationPath c:\

						#Update config with EC2 machine names
						(Get-Content C:\$TestDir\source\App.config).replace('Enter_Your_PIDataArchive_Name_Here', $Using:DefaultPIDataArchive) | Set-Content C:\$TestDir\source\App.config
						(Get-Content C:\$TestDir\source\App.config).replace('Enter_Your_AFServer_Name_Here', $Using:DefaultPIAFServer) | Set-Content C:\$TestDir\source\App.config
						(Get-Content C:\$TestDir\source\App.config).replace('Enter_Analysis_Service_Machine_Name_Here', 'PIAN0') | Set-Content C:\$TestDir\source\App.config

						$DeployHA = $Using:DeployHA
						if($DeployHA -eq 'false')	{
							(Get-Content C:\$TestDir\source\App.config).replace('key="PIVisionServer" value=""', 'key="PIVisionServer" value="https://PIVS0/PIVision"') | Set-Content C:\$TestDir\source\App.config
						}

						(Get-Content C:\$TestDir\source\App.config).replace('key="SkipCertificateValidation" value=""', 'key="SkipCertificateValidation" value="True"') | Set-Content C:\$TestDir\source\App.config

						#Add user to AF security group
						try {
							$Recal = Get-AFSecurityIdentity -Name "Asset Analytics Recalculation" -Refresh -AFServer (Get-AFServer -Name $Using:DefaultPIAFServer);
							$User = $Using:DomainNetBiosName + '\' + $Using:DomainAdminUserName ;
							Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message "COTS User: $User"
							Add-AFSecurityMapping -Name PIAdmin -WindowsAccount $User -AFSecurityIdentity $Recal -CheckIn -AFServer (Get-AFServer -Name $Using:DefaultPIAFServer);
						}
						Catch {
							#Continue user was previously added to group
							Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message  $_
						}

						#Run tests
						Start-Process -FilePath powershell.exe -Wait -PassThru -WorkingDirectory C:\$TestDir\scripts\ -ArgumentList ".\run.ps1 -f"

						#Copy test result to remote desktop gateway server
						New-Item -ItemType directory -Path "\\RDGW0.osideploysample.int\\C$\TestResults\" -Force
						Copy-Item -Path "C:\$TestDir\testResults\*.html" -Destination "\\RDGW0.osideploysample.int\\C$\TestResults\"

						Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message "COTS end."
                    }
                    Catch {
                        Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message  $_
                    }
                }
                DependsOn  = '[Package]PISystem', '[xPendingReboot]RebootPISystem'
                PsDscRunAsCredential = $domainCredential
            }
            #endregion ### 3. COTS ###            

            #region ### 4. SIGNAL WAITCONDITION ###
            # Writes output to the AWS CloudFormation Init Wait Handle (Indicating script completed)
            # To ensure it triggers only at the end of the script, set DependsOn to include all resources.
            Script Write-AWSQuickStartStatus {
                GetScript  = {@( Value = 'WriteAWSQuickStartStatus' )}
                TestScript = {$false}
                SetScript  = {
                    Write-Verbose "Getting Handle" -Verbose
                    $handle = Get-AWSQuickStartWaitHandle -ErrorAction SilentlyContinue
                    Invoke-Expression "cfn-signal.exe -e 0 -i 'pianalysis0config' '$handle'" 

                    # Write to Application Log to record status update.
                    $CheckSource = Get-EventLog -LogName Application -Source AWSQuickStartStatus -ErrorAction SilentlyContinue
                    if (!$CheckSource) {New-EventLog -LogName Application -Source 'AWSQuickStartStatus' -Verbose}  # Check for source to avoid throwing exception if already present.
                    Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message "Write-AWSQuickStartStatus function was triggered."
                }
                DependsOn  = '[Package]PISystem', '[xPendingReboot]RebootPISystem'
            }
            #endregion ### 4. SIGNAL WAITCONDITION ###
        }
    }

    # Compile and Execute Configuration
    PIAnalysis0Config -ConfigurationData $ConfigurationData
    Start-DscConfiguration -Path .\PIAnalysis0Config -Wait -Verbose -Force -ErrorVariable ev
}

catch {
    # If any expectations are thrown, output to CloudFormation Init.
    $_ | Write-AWSQuickStartException
}
# SIG # Begin signature block
# MIIcVwYJKoZIhvcNAQcCoIIcSDCCHEQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCxjXAIucdnnwpT
# qxaH6yyRF0ptgDCXLyfUGDInYLqotaCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgb0dL7/bGh6Da
# EmHiWfBNkfS1LK9vGLRem0eoMGM5OiUwMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAItC
# nmLqaPpRKP7cUbPh1xtn8ueunoDsrtINC6LdBgezQIF8qeZ7J8vfQSLwvETHxSdt
# XS2CcjJK+gFIOB5b/iUMnu22/t7npAuyei/gUG4Nvi4AwWKBdCNsbF8hEI5CCxQm
# zcsPfRzWV0ddkkvaMpEdj1xedFmZI6fCe//3gIOBVfBzmXJVh/Iu7fQ3Ntd5yjvZ
# sOy+BbBylvw/jwkplNRKedNoRnCkY68Cl7C41gVToq6OmKdFeTOkTWhZcfcBOItG
# aBhMN3lkH5QEKnZBM+Ho7J7JgUCV7c+3s8opOLtyg4Q4KmrRR/BRYGszcpBjQ1QY
# dBbm2GfIYOH6+THVrKuhgg7JMIIOxQYKKwYBBAGCNwMDATGCDrUwgg6xBgkqhkiG
# 9w0BBwKggg6iMIIOngIBAzEPMA0GCWCGSAFlAwQCAQUAMHgGCyqGSIb3DQEJEAEE
# oGkEZzBlAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQgjqNYnlISb7a3
# +MnDGc1g4WuPsNZeSPqlSrs4lVKNk+ACEQCkaZccs1io5x7gJ2jd5dOeGA8yMDIw
# MTExMTE3MjcyOFqgggu7MIIGgjCCBWqgAwIBAgIQBM0/hWiudsYbsP5xYMynbTAN
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
# KoZIhvcNAQkFMQ8XDTIwMTExMTE3MjcyOFowKwYLKoZIhvcNAQkQAgwxHDAaMBgw
# FgQUAyW9UF7aljAtwi9PoB5MKL4oNMUwLwYJKoZIhvcNAQkEMSIEIImx7tS8fQjb
# oVTXTbyCZTQZzLjLm5d8oYz38ie3TVBbMA0GCSqGSIb3DQEBAQUABIIBAKobe8I5
# 12OVPwesosRaosFycpyHDewj3apyk5UIPvsXYvYi8GquFlJ+uLDt2hAVO7LzT5hP
# O7Uyh87ONCsqh5GrkeEedQcwiHXV0ILtjhcBDf6vnZEbpTlKeltQh/3AFunNEHd9
# o+/wNA99YecmsT9zKHzsRlwYnlbqkLGSyRebrP2vqjKLJXXRmX3VXfVFFqOEsi1x
# KhyvK14ISPog044uPg8DohSk4p3tDJJ1CiF3sSX+Cys4drTy3K8Lvq+wLKeCIOJy
# fUFLpBmQ3gjmdaY1LRc0dlcSXiBWEE4BL030/TQevalRzfgPN/9uoX7KUBiA2Xaq
# jq6A6xHw3ShGivE=
# SIG # End signature block
