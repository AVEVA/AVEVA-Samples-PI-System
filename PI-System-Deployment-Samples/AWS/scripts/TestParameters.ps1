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

$DeploySampleRootScripts = 'CreateWaitHandle.ps1', 'IPHelper.psm1', 'Join-Domain.ps1', 'New-DSCCertificate.ps1', 'Reset-LocalAdminPassword.ps1', 'Un7zip-Archive.ps1', 'Unzip-Archive.ps1'
$DeploySampleADScripts = 'Add-DNSEntry.ps1', 'Configure-Sites.ps1', 'ConvertTo-EnterpriseAdmin.ps1', 'Create-AdminUser.ps1', 'Create-ServiceAccounts.ps1', 'Disable-WindowsFirewall.ps1', 'Install-ADDSDC.ps1', 'Install-ADDSForest.ps1', 'Install-Prereqs.ps1', 'New-CertificateAuthority.ps1', 'Rename-Computer.ps1', 'Set-StaticIP.ps1', 'Update-DNSServers.ps1'
$DeploySampleConfigScripts = 'PIAF0.ps1', 'PIAN0.ps1', 'PIDA0.ps1', 'PIVS0.ps1', 'RDGW0.ps1', 'SQL0.ps1'
$DeploySampleAFScripts = 'UpdateAFServersUser.sql'
$DeploySampleDAScripts = 'Backup.ps1', 'CollectiveManager.ps1', 'Connections.ps1', 'CreatePIDACollective.ps1', 'Get-RemoteCert.ps1', 'ListPIMessages.ps1', 'MoveOldArchives.ps1', 'PIDA_Scripts.zip', 'SecureCollective.ps1', 'SendPrimaryPublicCertToSecondaries.ps1', 'SendSecondaryPublicCertToPrimary.ps1'
$DeploySampleSQLScripts = 'AddUserToGroup.ps1', 'Disable-CredSSP.ps1', 'Enable-CredSSP.ps1', 'Install-WindowsFailoverClustering.ps1', 'Reconfigure-SQL.ps1', 'Set-ClusterQuorum.ps1', 'Test-ADUser.ps1', 'Configure-WSFC0.ps1', 'DownloadSQLEE.ps1', 'Install-NETFrameworkCore.ps1', 'Join-Domain.ps1', 'Rename-Computer.ps1', 'Set-Folder-Permissions.ps1', 'Configure-WSFC1.ps1', 'Create-Share.ps1', 'Enable-AlwaysOn.ps1', 'InstallSQLEE.ps1', 'OpenWSFCPorts.ps1', 'Restart-Computer.ps1', 'SetMaxDOP.ps1'

$DeploySampleModules = 'cNtfsAccessControl_1.4.1.zip', 'xAdcsDeployment_1.4.zip', 'xNetworking_5.7.zip', 'xSmbShare_2.1.zip', 'AWSQuickStart.zip', 'SqlServerDsc_13.2.zip', 'xComputerManagement_4.1.zip', 'cChoco_2.4.zip', 'xStorage_3.4.zip', 'SqlServer_21.0.17279.zip', 'xDnsServer_1.15.zip', 'xPendingReboot_0.4.zip', 'xWebAdministration_2.8.zip', 'PSDSSupportPIVS.zip', 'PSDSSupportPIDA.zip', 'xActiveDirectory_3.0.zip', 'xRemoteDesktopSessionHost_1.9.zip'
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
# MIIbzAYJKoZIhvcNAQcCoIIbvTCCG7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDs8h84to5Gx27H
# /GLLBGbaGMQj/AmITWA6fs36fCpHDaCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPS54oQCqalf
# 2ocVwwV+bQUo1CjxfuijNIO6i92wjRUlMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQBJ
# XGyU/9wENQUdOByYU3LlajhhbIeOf1+9VGdk2aEMtnDvrbn4bshNHaZcVZ5S9mHP
# M5uLnnP42+JKSrSMvwEr5xqynkrAMf+HoKyUxQA+5yFm+PLUojwInwPuGBZwLy+l
# TcHhFQ1T4vxgPnj07bFRGwa5k1lKoMIY6Db/vnAZrFCA3HEYzemuD8Nnh+vh6ypR
# 0riqWRRelJr6sjsOa1KzStEYqV00Ygl8wYgKHpMnezqmVti41I6HtTttAafpmgDY
# FFB8LH0+KEy1vdXH2F5UK2cKIuvzWrx2fkzLm5EHeHsiA1hoFPGtJ/v/iMukVhYa
# 2H8wLHy/dOJPdbRo/haAoYIOPTCCDjkGCisGAQQBgjcDAwExgg4pMIIOJQYJKoZI
# hvcNAQcCoIIOFjCCDhICAQMxDTALBglghkgBZQMEAgEwggEPBgsqhkiG9w0BCRAB
# BKCB/wSB/DCB+QIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgcu3Z
# uPgXbJxTGHL7KYk8+e9bRWNZzAB11JXLrSVyOq4CFQCziXaQaaV4WINRMJSEvddQ
# yVMw1RgPMjAxOTA4MDgxNDU3MzFaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
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
# DQEJBTEPFw0xOTA4MDgxNDU3MzFaMC8GCSqGSIb3DQEJBDEiBCCFaDoGgPcVoDet
# fmw1c69CQIkTSRj9zb921qhplJc+JzA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# CW2gI+lMlu3hJ16pdLyD9lQXvGoJL0lP6Z3+RKVIuGdTamyDptlWBzqpXzG3Cxpm
# QrGOORdrPOylq5qix2nhfTRXyu5w45As+90zHdRIqnakhRsdhmQmhiCKE3nOpEl+
# a7h5BsxWx3z9mv3lXC2oAac6H7d4w3pADXoGUWTUmgp5GkbOmroyNeb33B9HzbGw
# lGpsbzoKmgMy2UIlOR9bKrpUhYFPyZfiuqvqQElpIktQ/0nr3OHVeNguD6N0EgMP
# TOKsYdepZAtgQsXuzh/8uiV3t8c8Knh50bn7VNWN2EMedKz0mHCEISq625izaLyo
# tR8S5up4UO+8oR6ZEvCSRg==
# SIG # End signature block
