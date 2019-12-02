<#
.SYNOPSIS
    Runs the full work flow of OSIsoft PI System Deployment Tests

.DESCRIPTION
    The work flow consists of following steps:
        Load test configuration,
        Test the connection to servers,
        Create the target Wind Farm AF database if needed,
        Install build tools if missing, 
        Build test solution, 
        Execute the test suite,
        Optionally remove the Wind Farm PI database.

.PARAMETER Setup
    Switch to set up the target AF database

.PARAMETER Testing
    Switch to build and run all tests

.PARAMETER TestClass
    Name of the xUnit test class to run.  If set, the script will run all tests in the class. The Testing switch is optional.

.PARAMETER TestName
    Name of the xUnit test to run.  If set, only the single test will be run. The TestClass parameter is required.
    
.PARAMETER Cleanup
    Switch to remove the test environment

.PARAMETER Force
    Switch to suppress confirmation prompts

.EXAMPLE
.\run.ps1
Run the full work flow

.EXAMPLE
.\run.ps1 -f
Run the full work flow without confirmation prompts

.EXAMPLE
.\run.ps1 -s
Set up the target AF Database

.EXAMPLE
.\run.ps1 -s -f
Set up the target AF Database without confirmation prompts

.EXAMPLE
.\run.ps1 -t
Run xUnit tests 

.EXAMPLE
.\run.ps1 -t -f
Run xUnit tests without confirmation prompts

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass"
Run a specific xUnit test class

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass"
Run a specific xUnit test class

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass" -f
Run a specific xUnit test class without confirmation prompts

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass" -TestName "MyTest"
Run a specific xUnit test

.EXAMPLE
.\run.ps1 -TestClass "MyTestClass" -TestName "MyTest" -f
Run a specific xUnit test without confirmation prompts

.EXAMPLE
.\run.ps1 -c
Clean up all test related PI/AF components

.EXAMPLE
.\run.ps1 -c -f
Clean up all test related PI/AF components without confirmation prompts
#>
#requires -version 4.0
#requires -RunAsAdministrator
[CmdletBinding()]
Param (
    [Alias('s')]
    [switch]$Setup,
    
    [Alias('t')]
    [switch]$Testing,

    [String]$TestClass = '',

    [String]$TestName = '',

    [Alias('c')]
    [switch]$Cleanup,

    [Alias('f')]
    [switch]$Force
)

$MinimumOSIPSVersion = New-Object System.Version("2.2.2.0")
$OSIPSModule = Get-Module -ListAvailable -Name OSIsoft.PowerShell
$OSIPSVersion = (Get-Item $OSIPSModule.Path).VersionInfo.ProductVersion
if ((-not $OSIPSModule) -or ($OSIPSVersion -lt $MinimumOSIPSVersion)) {
    Write-Error -Message ("The script requires PI AF Client and PowerShell Tools for the PI System with a minimum " + 
        "version of 2018 SP3, please upgrade PI software and try again." + [environment]::NewLine) -ErrorAction Stop
}

. "$PSScriptRoot\common.ps1"

Add-InfoLog -Message "Start OSIsoft PI System Deployment Tests script."

Add-InfoLog -Message "Load PI System settings."
$config = Read-PISystemConfig -Force:$Force

Add-InfoLog -Message "Test connection to the specified PI Data Archive, $($config.PIDataArchive)."
$PIDAConfig = Get-PIDataArchiveConnectionConfiguration -Name $config.PIDataArchive
if (-not $PIDAConfig) {
    Add-ErrorLog -Message "Could not retrieve PI Data Archive connection information from $($config.PIDataArchive)" -Fatal
}

$PIDA = Connect-PIDataArchive -PIDataArchiveConnectionConfiguration $PIDAConfig -ErrorAction Stop

Add-InfoLog -Message "Test connection to the specified AF server, $($config.AFServer)."
$PISystems = New-Object OSIsoft.AF.PISystems
$PISystem = $PISystems[$config.AFServer]
if (-not $PISystem) {
    Add-ErrorLog -Message "Cannot find the specified AF Server, $($config.AFServer)." -Fatal
}

# If testing related parameters are specified, set runTests flag to true.
$runTests = $Testing.IsPresent -or ($TestClass -ne '') -or ($TestName -ne '') 

# Three major steps in the work flow are Setup, Testing and Cleanup.  One may choose to run one or more steps.
# If no particular switch is specified, the script will run all steps.
$runAll = -not ($Setup -or $runTests -or $Cleanup)

# Run setup steps
if ($Setup -or $runAll) {
    Add-InfoLog -Message "Set up the target AF database."
    $SetTargetDatabaseParams = @{
        PISystem = $PISystem
        Database = $config.AFDataBase
        PIDA     = $PIDA
        Force    = $Force
    }
    Set-TargetDatabase @SetTargetDatabaseParams

    # In order to build xUnit test solution, we need .NET Framework Developer Pack, NuGet.exe, and MSBuild
    Add-InfoLog -Message "Install .NET Framework Developer Pack if missing."
    Install-DotNETDevPack

    Add-InfoLog -Message "Install NuGet.exe if missing."
    Install-NuGet

    Add-InfoLog -Message "Install MSBuild if missing."
    Install-BuildTools
}

# Run xUnit tests
if ($runTests -or $runAll) {
    Add-InfoLog -Message "Test connection to the target AF database, $($config.AFDatabase), on $($config.AFServer)."
    $TargetDatabase = $PISystem.Databases[$config.AFDatabase]
    if (-not $TargetDatabase) {
        Add-ErrorLog -Message ("Cannot find the specified AF database, $($config.AFDatabase)," + 
            " on $($config.AFServer).") -Fatal
    }

    Add-InfoLog -Message "Restore the NuGet packages of the test solution."
    Restore-SolutionPackages

    Add-InfoLog -Message "Build the test solution."
    Build-TestSolution

    if ($TestName -ne '' -and $TestClass -ne '') {
        Add-InfoLog -Message "Run xUnit test '$TestName'."
        Start-Testing -TestClassName "$TestClass" -TestName "$TestName"
    }
    elseif ($TestName -eq '' -and $TestClass -ne '') {
        Add-InfoLog -Message "Run xUnit test class '$TestClass'."
        Start-Testing -TestClassName "$TestClass"
    }
    elseif ($TestName -eq '' -and $TestClass -eq '') {
        Add-InfoLog -Message "Run xUnit tests."
        Start-Testing
    }
    else {
        Add-ErrorLog -Message "Incorrect usage for test runs. Correct usage: '.\run.ps1 -t (Optional)-TestClass 'MyTestClass' (Optional, Requires TestClass)-TestName 'MyTest' (Optional)-f'" -Fatal
    }
}

# Run cleanup steps
if ($Cleanup -or $runAll) {
    Add-InfoLog -Message "Remove all test related components."
    $RemoveTargetDatabaseParams = @{
        PISystem = $PISystem
        Database = $config.AFDataBase
        PIDA     = $PIDA
        Force    = $Force
    }
    Remove-TargetDatabase @RemoveTargetDatabaseParams
}

Disconnect-PIDataArchive -Connection $PIDA > $null

Add-InfoLog -Message "OSIsoft PI System Deployment Tests script finished."
# SIG # Begin signature block
# MIIcLAYJKoZIhvcNAQcCoIIcHTCCHBkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDnq2ZWNXh8hxiY
# cSHWkAoJGphBn17mIU7ayFv+2X7qyKCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# dAbq5BqlYz1Fr8UrWeR3KIONPNtkm2IFHNMdpsgmKwC/Xh3nC3b27DGCEPQwghDw
# AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIg
# QXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAVNNVk3TJ+08xyzMPnTxD8wDQYJ
# YIZIAWUDBAIBBQCggf8wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIHC/RDV19Ihe
# GbCrahm2RF06fczWeqp30NcSr0Jr8uZcMIGSBgorBgEEAYI3AgEMMYGDMIGAoFyA
# WgBQAEkAIABTAHkAcwB0AGUAbQAgAEQAZQBwAGwAbwB5AG0AZQBuAHQAIABUAGUA
# cwB0AHMAIABQAG8AdwBlAHIAUwBoAGUAbABsACAAUwBjAHIAaQBwAHQAc6EggB5o
# dHRwOi8vdGVjaHN1cHBvcnQub3Npc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# Uh1iH/kT5zWZZ9ay2W1NnWDPsxaJ6Xu1sB0uPmVPzcGv4Nd2H4fNL87iB89x7sMF
# wydN3foZ8ATpBr9rsCGAVJwPFjSkoCBXPb/JXawdfMZX5yAzE9UsttUBhRr/ktRN
# TUDzm/I3O+OkNbVxhHvCXxkKn8HJ5LKeZnNFUiV9zIci0R5UKRRznqxp6KiUXRSc
# KpR1UeJJ4bH3zNNc0TwPeoBVVBT5nglEIVOHUZVzVx7GYRyXDKPqDOE7ZvV1Qm4G
# 3LxEvc3XQkce0rodH8b3wwSIB4xF5TY7aiJgCVx5KgsCIruHLTRtAr1lwFBI8cLO
# Y4jnxS6N3keavcuYKuuPh6GCDjwwgg44BgorBgEEAYI3AwMBMYIOKDCCDiQGCSqG
# SIb3DQEHAqCCDhUwgg4RAgEDMQ0wCwYJYIZIAWUDBAIBMIIBDgYLKoZIhvcNAQkQ
# AQSggf4EgfswgfgCAQEGC2CGSAGG+EUBBxcDMDEwDQYJYIZIAWUDBAIBBQAEIOwz
# OCTz+AW2qBD8ejiAqHAshAI35Q6QC0kzEq3/62MzAhRr2EYDvX8wBXbiGqTJyp0p
# 37SfbRgPMjAxOTExMjAxNTM4NDRaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
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
# DQEJBTEPFw0xOTExMjAxNTM4NDRaMC8GCSqGSIb3DQEJBDEiBCBFRYaNDYAWnviB
# QIq8+x2WBLSMSW+x7QBN2r+2FUUwBjA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# i1Yix0RDNMQMikArg3zLJ9rYgJqbzn7WDZdzBKsG5cwxJ9Z9fNLj7PUV6wfTzY5j
# VS7AiKaXMqQWXBge7fH/ByodmvZ3KEavO2efK9dO3Efr6vXaRHcJmPfih5sjE2s+
# 0EXcl/Fk38tDJPqvygm6TfKPNFBKymoMKENreT6teOv4FXT+y6TuQ0ZbVUNuBtmE
# lsHX1W9P8GiHiYDVi4NxyILS8eMogFcjuO8tAYjKY6q79H7fnk3JM1mugCRGK+ax
# L9J9XmTfYUIZawRIwMeAuPZN5k+2Jn13s7Lwaxg77WudEQgIVl7dADFmhGimFqqF
# 6GVtA2LvxtwCN6QwekIj/A==
# SIG # End signature block
