# TestParameters.ps1 - Tests that all DeploySample files can be accessed by the deployment.

#region Parameters
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DSS3BucketName,

    [Parameter(Mandatory=$true)]
    [string]$DSS3KeyPrefix,

    [Parameter(Mandatory=$true)]
    [string]$DSS3BucketRegion,

    [Parameter(Mandatory=$true)]
    [string]$SetupKitsS3BucketName,

    [Parameter(Mandatory=$true)]
    [string]$SetupKitsS3KeyPrefix,

    [Parameter(Mandatory=$true)]
    [string]$SetupKitsS3BucketRegion,

    [Parameter(Mandatory=$true)]
    [string]$SetupKitsS3PIFileName,

    [Parameter(Mandatory=$true)]
    [string]$SetupKitsS3VisionFileName,

    [Parameter(Mandatory=$true)]
    [string]$TestFileName
)

$LicenseFileName = "pilicense.dat"

# These variables are static, not configured in the deployment 
$DeploySampleTemplates = 'ec2PrivateAD.template', 'ec2PrivatePIAF.template', 'ec2PrivatePIAnalysis.template', 'ec2PrivatePIDA.template', 'ec2PrivateSQL.template', 'ec2PublicPIVision.template', 'ec2PublicPIVision.template', 'ec2PublicRDGW.template', 'DSCoreSecurityGroups.template', 'DSCoreStack.template', 'DSMasterStack.template', 'DSPIStack.template', 'DSPISystemsSecurityGroups.template', 'vpc.template'

$DeploySampleRootScripts = 'CreateWaitHandle.ps1', 'IPHelper.psm1', 'Join-Domain.ps1', 'New-DSCCertificate.ps1', 'Rename-Computer.ps1', 'Reset-LocalAdminPassword.ps1', 'Un7zip-Archive.ps1', 'Unzip-Archive.ps1'
$DeploySampleADScripts = 'Add-DNSEntry.ps1', 'Configure-Sites.ps1', 'ConvertTo-EnterpriseAdmin.ps1', 'Create-AdminUser.ps1', 'Create-ServiceAccounts.ps1', 'Disable-WindowsFirewall.ps1', 'Install-ADDSDC.ps1', 'Install-ADDSForest.ps1', 'Install-Prereqs.ps1', 'New-CertificateAuthority.ps1', 'Set-StaticIP.ps1', 'Update-DNSServers.ps1'
$DeploySampleConfigScripts = 'PIAF0.ps1', 'PIAN0.ps1', 'PIDA0.ps1', 'PIVS0.ps1', 'RDGW0.ps1', 'SQL0.ps1'
$DeploySampleAFScripts = 'UpdateAFServersUser.sql'
$DeploySampleDAScripts = 'Backup.ps1', 'CollectiveManager.ps1', 'Connections.ps1', 'CreatePIDACollective.ps1', 'Get-RemoteCert.ps1', 'ListPIMessages.ps1', 'MoveOldArchives.ps1', 'PIDA_Scripts.zip', 'SecureCollective.ps1', 'SendPrimaryPublicCertToSecondaries.ps1', 'SendSecondaryPublicCertToPrimary.ps1'
$DeploySampleSQLScripts = 'AddUserToGroup.ps1', 'Disable-CredSSP.ps1', 'Enable-CredSSP.ps1', 'Install-WindowsFailoverClustering.ps1', 'Reconfigure-SQL.ps1', 'Set-ClusterQuorum.ps1', 'Test-ADUser.ps1', 'Configure-WSFC0.ps1', 'DownloadSQLEE.ps1', 'Install-NETFrameworkCore.ps1', 'Join-Domain.ps1', 'Set-Folder-Permissions.ps1', 'Configure-WSFC1.ps1', 'Create-Share.ps1', 'Enable-AlwaysOn.ps1', 'InstallSQLEE.ps1', 'OpenWSFCPorts.ps1', 'Restart-Computer.ps1', 'SetMaxDOP.ps1'

$DeploySampleModules = 'cNtfsAccessControl_1.4.1.zip', 'xAdcsDeployment_1.4.zip', 'xNetworking_5.7.zip', 'xSmbShare_2.1.zip', 'AWSQuickStart.zip', 'SqlServerDsc_13.2.zip', 'xComputerManagement_4.1.zip', 'cChoco_2.4.zip', 'xStorage_3.4.zip', 'SqlServer_21.1.18218.zip', 'xDnsServer_1.15.zip', 'xPendingReboot_0.4.zip', 'xWebAdministration_2.8.zip', 'PSDSSupportPIVS.zip', 'PSDSSupportPIDA.zip', 'xActiveDirectory_3.0.zip', 'xRemoteDesktopSessionHost_1.9.zip'
#endregion

#region DeploySample
# Test the bucket name & region
# This produces a bad error message, so this try-catch massages the output to something helpful
try{
   $Result = Get-S3Object -BucketName $DSS3BucketName -Region $DSS3BucketRegion
}
catch [System.InvalidOperationException] {
   throw "Could not find bucket $DSS3BucketName in region $DSS3BucketRegion. Ensure the bucket name and region are correct."
}

$Result = Get-S3Object -BucketName $DSS3BucketName -KeyPrefix $DSS3KeyPrefix -Region $DSS3BucketRegion

if ($null -eq $Result){
   throw "Could not find folder $DSS3KeyPrefix in bucket $DSS3BucketName"
}
foreach ($template in $DeploySampleTemplates) {
   $Result = Get-S3Object -BucketName $DSS3BucketName -Key $DSS3KeyPrefix/templates/$template -Region $DSS3BucketRegion
   if ($null -eq $Result){
      throw "Could not find $template in the DeploySample bucket $DSS3BucketName. Ensure this file exists in $DSS3KeyPrefix/templates and you have access to it."
   }
}

foreach($script in $DeploySampleRootScripts){
   $Result = Get-S3Object -BucketName $DSS3BucketName -Key $DSS3KeyPrefix/scripts/$script -Region $DSS3BucketRegion
   if ($null -eq $Result){
      throw "Could not find $script in the DeploySample bucket $DSS3BucketName. Ensure this file exists in $DSS3KeyPrefix/scripts and you have access to it."
   }
}

foreach($script in $DeploySampleADScripts){
   $Result = Get-S3Object -BucketName $DSS3BucketName -Key $DSS3KeyPrefix/scripts/AD/$script -Region $DSS3BucketRegion
   if ($null -eq $Result){
      throw "Could not find $script in the DeploySample bucket $DSS3BucketName. Ensure this file exists in $DSS3KeyPrefix/scripts/AD and you have access to it."
   }
}

foreach($script in $DeploySampleConfigScripts){
   $Result = Get-S3Object -BucketName $DSS3BucketName -Key $DSS3KeyPrefix/scripts/configs/$script -Region $DSS3BucketRegion
   if ($null -eq $Result){
      throw "Could not find $script in the DeploySample bucket $DSS3BucketName. Ensure this file exists in $DSS3KeyPrefix/scripts/configs and you have access to it."
   }
}

foreach($script in $DeploySampleAFScripts){
   $Result = Get-S3Object -BucketName $DSS3BucketName -Key $DSS3KeyPrefix/scripts/PIAF/$script -Region $DSS3BucketRegion
   if ($null -eq $Result){
      throw "Could not find $script in the DeploySample bucket $DSS3BucketName. Ensure this file exists in $DSS3KeyPrefix/scripts/PIAF and you have access to it."
   }
}

foreach($script in $DeploySampleDAScripts){
   $Result = Get-S3Object -BucketName $DSS3BucketName -Key $DSS3KeyPrefix/scripts/PIDA/$script -Region $DSS3BucketRegion
   if ($null -eq $Result){
      throw "Could not find $script in the DeploySample bucket $DSS3BucketName. Ensure this file exists in $DSS3KeyPrefix/scripts/PIDA and you have access to it."
   }
}

foreach($script in $DeploySampleSQLScripts){
   $Result = Get-S3Object -BucketName $DSS3BucketName -Key $DSS3KeyPrefix/scripts/SQL/$script -Region $DSS3BucketRegion
   if ($null -eq $Result){
      throw "Could not find $script in the DeploySample bucket $DSS3BucketName. Ensure this file exists in $DSS3KeyPrefix/scripts/SQL and you have access to it."
   }
}

foreach($module in $DeploySampleModules){
   $Result = Get-S3Object -BucketName $DSS3BucketName -Key $DSS3KeyPrefix/modules/$module -Region $DSS3BucketRegion
   if ($null -eq $Result){
      throw "Could not find $module in the DeploySample bucket $DSS3BucketName. Ensure this file exists in $DSS3KeyPrefix/modules and you have access to it."
   }
}
Write-Output "DeploySample bucket contents have been verified"
#endregion

#region SetupKits
# Test the bucket name & region
# This produces a bad error message, so this try-catch massages the output to something helpful
try{
   $Result = Get-S3Object -BucketName $SetupKitsS3BucketName -Region $SetupKitsS3BucketRegion
}
catch [System.InvalidOperationException] {
   throw "Could not find bucket $SetupKitsS3BucketName in region $SetupKitsS3BucketRegion. Ensure the bucket name and region are correct."
}

$Result = Get-S3Object -BucketName $SetupKitsS3BucketName -KeyPrefix $SetupKitsS3KeyPrefix -Region $SetupKitsS3BucketRegion
if ($null -eq $Result){
   throw "Could not folder $SetupKitsS3KeyPrefix in bucket $SetupKitsS3BucketName"
}
   
$Result = Get-S3Object -BucketName $SetupKitsS3BucketName -Key $SetupKitsS3KeyPrefix/PIServer/$SetupKitsS3PIFileName -Region $SetupKitsS3BucketRegion
if ($null -eq $Result){
   throw "Could not find $SetupKitsS3PIFileName in $SetupKitsS3BucketName/$SetupKitsS3KeyPrefix/PIServer. Ensure the file exists and you have access to it."
}

$Result = Get-S3Object -BucketName $SetupKitsS3BucketName -Key $SetupKitsS3KeyPrefix/PIServer/$LicenseFileName -Region $SetupKitsS3BucketRegion
if ($null -eq $Result){
   throw "Could not find $LicenseFileName in $SetupKitsS3BucketName/$SetupKitsS3KeyPrefix/PIServer. Ensure the file exists and you have access to it."
}

$Result = Get-S3Object -BucketName $SetupKitsS3BucketName -Key $SetupKitsS3KeyPrefix/PIVision/$SetupKitsS3VisionFileName -Region $SetupKitsS3BucketRegion
if ($null -eq $Result){
   throw "Could not find $SetupKitsS3VisionFileName in $SetupKitsS3BucketName/$SetupKitsS3KeyPrefix/PIVision. Ensure the file exists and you have access to it."
}

$Result = Get-S3Object -BucketName $SetupKitsS3BucketName -Key $SetupKitsS3KeyPrefix/$TestFileName -Region $SetupKitsS3BucketRegion
if ($null -eq $Result){
   throw "Could not find $TestFileName in $SetupKitsS3BucketName/$SetupKitsS3KeyPrefix. Ensure the file exists and you have access to it."
}

Write-Output "Setup kit bucket contents have been verified"
#endregion

# SIG # Begin signature block
# MIIcVgYJKoZIhvcNAQcCoIIcRzCCHEMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD4rRylYMhJKD1l
# pfW8SPJRsbS0qJdPepa8jmFzQjQpQqCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg9dZDYB3mef4+
# Ue4IAqyaP6uUEsKsKXDgAkCEkiOLUzUwMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBADl9
# jL3Jlw2xR0oEXYlkwc2jcA+4JRXmVUr2xR+IHBJhqkgIi8nXcNNanYBK1lD0oWml
# iriM3TC3/T+3lvufhElNZPE5PAZYT+gwnOSPieYUbqXQtHVzgiG/F1+cJptMBAG+
# 8Bo6PKIdQijlMrlDUVXU3RwTWOAWGmXxVAOHRSZ3zdjk0UBWikwBtE5xNVLuMC2F
# uXMCB7185BB//Lbbb9Cq4W4xS4NlpUOhr31O2UgyxqT5bqus9UoCSXGQqSPfml5c
# vpqslKCRh/YRn3FEdxIEiKByQ888HOmRVz5FlOQvsT1N8nmJLaklDGfnzwukCcVC
# 0vlbnAOQkuTh+KI1Zfehgg7IMIIOxAYKKwYBBAGCNwMDATGCDrQwgg6wBgkqhkiG
# 9w0BBwKggg6hMIIOnQIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEE
# oGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQg9F6joS3r8H3f
# nThPE1obGq+9pgnLuE7Im3HWhR7V7N8CECg2c+n8nagIz8NwAQX4Io8YDzIwMjAx
# MTExMTcyNzI2WqCCC7swggaCMIIFaqADAgECAhAEzT+FaK52xhuw/nFgzKdtMA0G
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
# hkiG9w0BCQUxDxcNMjAxMTExMTcyNzI2WjArBgsqhkiG9w0BCRACDDEcMBowGDAW
# BBQDJb1QXtqWMC3CL0+gHkwovig0xTAvBgkqhkiG9w0BCQQxIgQgFsHWIbo+Foh/
# qAwSwVyUBqXuNvJigsN52EMmAfny924wDQYJKoZIhvcNAQEBBQAEggEAhX3uWPZc
# +U593ihuFpt3AXCUEZkFgIJe4PRhTj8BcefoOx6l2PVsXQ3LpHI7TFY8WEdcgPEY
# ht8nCCvBkxDmP+GIObm2IG5uwgVOZ+Nvuq/IxIqvdFHapexC4uI9C8mcsFPO1YH2
# x0prDuirsSlDeoiRWPGp9dEzsu/Ob+E1OX/nC4XPjSclOMgdTK/OJusZCtd9zR64
# Fx76WAVLQy0YlvqC48xOWKNhEXyMPOHs8JAWLczwY3cGylt80Mejzbl1+18Ch/Pc
# r4kkW9hc0PHW7ZT7COHUc2hs3CRcRTf+Cs/9VJu/ZJzwu5pYvot5ZuyOGU861q24
# MhHujn/WSF2hNQ==
# SIG # End signature block
