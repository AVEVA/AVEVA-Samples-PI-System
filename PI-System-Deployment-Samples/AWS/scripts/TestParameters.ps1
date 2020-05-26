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
# MIIbywYJKoZIhvcNAQcCoIIbvDCCG7gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD4rRylYMhJKD1l
# pfW8SPJRsbS0qJdPepa8jmFzQjQpQqCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPXWQ2Ad5nn+
# PlHuCAKsmj+rlBLCrClw4AJAhJIji1M1MDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQAt
# kjJPws5T2/yua+bVMwyCnrt5z+m3JMxf6X4FdXP0LO/95G8mB6pIJRoNNUy8KJmb
# utfLNHHN+SSsRfSE2IP29TYRuBfDNLMmD0rEPcNcblawdeX6pJKl8SPxbCIF9Ifb
# hMpi5V8m7IcMc5WEDbPQBDwLYKZA9tGTLT0mJydj5fDI5DOQejsWQenLV4hvDm6/
# Jw0gylzi+M71j1J0so7IiDMIZNfyGmk7Eab4PM9XLHZArHhEWcFD1Ns4fIVSJHcE
# 35hoIMX3uIKhhro37pTLPToQ6zC5SGiXwmyB1DlsojnD+TRA5jHcJCFBcpX93M7W
# PJ1mzrKEEHeZHpz8KHB4oYIOPDCCDjgGCisGAQQBgjcDAwExgg4oMIIOJAYJKoZI
# hvcNAQcCoIIOFTCCDhECAQMxDTALBglghkgBZQMEAgEwggEOBgsqhkiG9w0BCRAB
# BKCB/gSB+zCB+AIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgLtIo
# aVSjhd0csQQsnSa0HTHxmL3E1wnAojywSEPoEQ8CFBXEDy2iHXhBmn67xLILZGV7
# B9BLGA8yMDIwMDMzMDE1NDAxNVowAwIBHqCBhqSBgzCBgDELMAkGA1UEBhMCVVMx
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
# AQkFMQ8XDTIwMDMzMDE1NDAxNVowLwYJKoZIhvcNAQkEMSIEIA3eRzajqqG6i2PF
# zERSKekOn6JhNohxL1eCEcuuZg20MDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMR0
# znYAfQI5Tg2l5N58FMaA+eKCATz+9lPvXbcf32H4MAsGCSqGSIb3DQEBAQSCAQBg
# 7Wx+WQsYgQnWEubVXcTAlN3hXjFnuC+qYGCPxVtB7nKi6PeZbFqXqdDOcLRusaP+
# umLQARdU/RjfzxvJPPPAWvLzzY18kyr3OJT3rkcvGXvK+VfFjQmVQSw/ncWADnru
# 37+K3rm+ANkYiv2Zl8GfYc6sNR31eLKx7XfegUc/zUzNMUnP92LeujtF0I1dUdFD
# TQWxaGxLfBELIzv7WvIOXbkNAFq5Le4XqERukliam1CGYK2bxpTQybBFdLaRwwc0
# Ms6qcqcCaMsTCAObprtSL3dYu3lEuxmv3yHwrijvhS7s1GPWjCcXtgmYXp8OUdWk
# Oay5+iYCjAfjw+9+I0A0
# SIG # End signature block
