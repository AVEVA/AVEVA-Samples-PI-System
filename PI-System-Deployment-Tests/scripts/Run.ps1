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

.PARAMETER Preliminary
    Switch to build and run the PreliminaryCheck tests

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
.\run.ps1 -p
Set up the target AF Database

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
[CmdletBinding()]
Param (
    [Alias('p')]
    [switch]$Preliminary,

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
$runTests = ($Testing.IsPresent -or ($TestClass -ne '') -or ($TestName -ne '')) -and -not $Preliminary.IsPresent

# Three major steps in the work flow are Setup, Testing and Cleanup.  One may choose to run one or more steps.
# If no particular switch is specified, the script will run all steps.
$runAll = -not ($Preliminary -or $Setup -or $runTests -or $Cleanup)

# Run PreliminaryChecks xUnit tests
if ($Preliminary -or $runAll) {
    Add-InfoLog -Message "Build xUnit tests."
    Build-Tests

    Add-InfoLog -Message "Run PreliminaryChecks xUnit tests."
    Start-PrelimTesting
}

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
}

# Run xUnit tests
if ($runTests -or $runAll) {
    Add-InfoLog -Message "Test connection to the target AF database, $($config.AFDatabase), on $($config.AFServer)."
    $TargetDatabase = $PISystem.Databases[$config.AFDatabase]
    if (-not $TargetDatabase) {
        Add-ErrorLog -Message ("Cannot find the specified AF database, $($config.AFDatabase)," + 
            " on $($config.AFServer).") -Fatal
    }

    if (-not $runAll) {
        Add-InfoLog -Message "Build xUnit tests."
        Build-Tests
	}

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
# MIIcLQYJKoZIhvcNAQcCoIIcHjCCHBoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDFerfunU1+RrUy
# yJjMkQRq9YVFZSzOS9kqlDhhWCQssaCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# dAbq5BqlYz1Fr8UrWeR3KIONPNtkm2IFHNMdpsgmKwC/Xh3nC3b27DGCEPUwghDx
# AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIg
# QXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAVNNVk3TJ+08xyzMPnTxD8wDQYJ
# YIZIAWUDBAIBBQCggf8wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFi30k3EQWN9
# ub2nXAsRsJAqq/kMnB6QewT572A8+2bcMIGSBgorBgEEAYI3AgEMMYGDMIGAoFyA
# WgBQAEkAIABTAHkAcwB0AGUAbQAgAEQAZQBwAGwAbwB5AG0AZQBuAHQAIABUAGUA
# cwB0AHMAIABQAG8AdwBlAHIAUwBoAGUAbABsACAAUwBjAHIAaQBwAHQAc6EggB5o
# dHRwOi8vdGVjaHN1cHBvcnQub3Npc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# DdgN1UvJ0VrjgPK5IvdHtUm6pUqOyvCh6HZIQJiJW4nMhnFQz7ZsDY41+EIua/gF
# 2AGzMP+WYOKUoprIxFlynYMvX1d305/9ALmXJOkgd8s6zYSeNSYqYEAdRN8i998l
# lJ0APVoESrfJ7L295y+jX4gsbE75VdvEVl2CJpTk65kbST98hkqHafshhx4k/Rv2
# oNbXsu2HoSLs5jL+fcPxvP/K7WhLssXZSCJhrrvJxkM/Cxwp22HWnTGvnzvC8yqO
# C0eIhZeNpsxr6GwYzbdFXhOq12HlpsWlrWNCEMyPLnaC+F2xShQmgRbI+UKpAH4W
# ZG2ECcN76IQ9ZYqjP3wvqaGCDj0wgg45BgorBgEEAYI3AwMBMYIOKTCCDiUGCSqG
# SIb3DQEHAqCCDhYwgg4SAgEDMQ0wCwYJYIZIAWUDBAIBMIIBDwYLKoZIhvcNAQkQ
# AQSggf8EgfwwgfkCAQEGC2CGSAGG+EUBBxcDMDEwDQYJYIZIAWUDBAIBBQAEINY/
# soNXCFL9F53gToEdQWyd0ZIuKePhhqG9zV1NwqdFAhUAkGNXt2FBX5DzQzDXx1ne
# +jw//jUYDzIwMjAwNDAzMTg1NjM2WjADAgEeoIGGpIGDMIGAMQswCQYDVQQGEwJV
# UzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xHzAdBgNVBAsTFlN5bWFu
# dGVjIFRydXN0IE5ldHdvcmsxMTAvBgNVBAMTKFN5bWFudGVjIFNIQTI1NiBUaW1l
# U3RhbXBpbmcgU2lnbmVyIC0gRzOgggqLMIIFODCCBCCgAwIBAgIQewWx1EloUUT3
# yYnSnBmdEjANBgkqhkiG9w0BAQsFADCBvTELMAkGA1UEBhMCVVMxFzAVBgNVBAoT
# DlZlcmlTaWduLCBJbmMuMR8wHQYDVQQLExZWZXJpU2lnbiBUcnVzdCBOZXR3b3Jr
# MTowOAYDVQQLEzEoYykgMjAwOCBWZXJpU2lnbiwgSW5jLiAtIEZvciBhdXRob3Jp
# emVkIHVzZSBvbmx5MTgwNgYDVQQDEy9WZXJpU2lnbiBVbml2ZXJzYWwgUm9vdCBD
# ZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTAeFw0xNjAxMTIwMDAwMDBaFw0zMTAxMTEy
# MzU5NTlaMHcxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazEoMCYGA1UEAxMf
# U3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBALtZnVlVT52Mcl0agaLrVfOwAa08cawyjwVrhponADKX
# ak3JZBRLKbvC2Sm5Luxjs+HPPwtWkPhiG37rpgfi3n9ebUA41JEG50F8eRzLy60b
# v9iVkfPw7mz4rZY5Ln/BJ7h4OcWEpe3tr4eOzo3HberSmLU6Hx45ncP0mqj0hOHE
# 0XxxxgYptD/kgw0mw3sIPk35CrczSf/KO9T1sptL4YiZGvXA6TMU1t/HgNuR7v68
# kldyd/TNqMz+CfWTN76ViGrF3PSxS9TO6AmRX7WEeTWKeKwZMo8jwTJBG1kOqT6x
# zPnWK++32OTVHW0ROpL2k8mc40juu1MO1DaXhnjFoTcCAwEAAaOCAXcwggFzMA4G
# A1UdDwEB/wQEAwIBBjASBgNVHRMBAf8ECDAGAQH/AgEAMGYGA1UdIARfMF0wWwYL
# YIZIAYb4RQEHFwMwTDAjBggrBgEFBQcCARYXaHR0cHM6Ly9kLnN5bWNiLmNvbS9j
# cHMwJQYIKwYBBQUHAgIwGRoXaHR0cHM6Ly9kLnN5bWNiLmNvbS9ycGEwLgYIKwYB
# BQUHAQEEIjAgMB4GCCsGAQUFBzABhhJodHRwOi8vcy5zeW1jZC5jb20wNgYDVR0f
# BC8wLTAroCmgJ4YlaHR0cDovL3Muc3ltY2IuY29tL3VuaXZlcnNhbC1yb290LmNy
# bDATBgNVHSUEDDAKBggrBgEFBQcDCDAoBgNVHREEITAfpB0wGzEZMBcGA1UEAxMQ
# VGltZVN0YW1wLTIwNDgtMzAdBgNVHQ4EFgQUr2PWyqNOhXLgp7xB8ymiOH+AdWIw
# HwYDVR0jBBgwFoAUtnf6aUhHn1MS1cLqBzJ2B9GXBxkwDQYJKoZIhvcNAQELBQAD
# ggEBAHXqsC3VNBlcMkX+DuHUT6Z4wW/X6t3cT/OhyIGI96ePFeZAKa3mXfSi2VZk
# hHEwKt0eYRdmIFYGmBmNXXHy+Je8Cf0ckUfJ4uiNA/vMkC/WCmxOM+zWtJPITJBj
# SDlAIcTd1m6JmDy1mJfoqQa3CcmPU1dBkC/hHk1O3MoQeGxCbvC2xfhhXFL1TvZr
# jfdKer7zzf0D19n2A6gP41P3CnXsxnUuqmaFBJm3+AZX4cYO9uiv2uybGB+queM6
# AL/OipTLAduexzi7D1Kr0eOUA2AKTaD+J20UMvw/l0Dhv5mJ2+Q5FL3a5NPD6ita
# s5VYVQR9x5rsIwONhSrS/66pYYEwggVLMIIEM6ADAgECAhB71OWvuswHP6EBIwQi
# QU0SMA0GCSqGSIb3DQEBCwUAMHcxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1h
# bnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29y
# azEoMCYGA1UEAxMfU3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTAeFw0x
# NzEyMjMwMDAwMDBaFw0yOTAzMjIyMzU5NTlaMIGAMQswCQYDVQQGEwJVUzEdMBsG
# A1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xHzAdBgNVBAsTFlN5bWFudGVjIFRy
# dXN0IE5ldHdvcmsxMTAvBgNVBAMTKFN5bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBp
# bmcgU2lnbmVyIC0gRzMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCv
# Doqq+Ny/aXtUF3FHCb2NPIH4dBV3Z5Cc/d5OAp5LdvblNj5l1SQgbTD53R2D6T8n
# SjNObRaK5I1AjSKqvqcLG9IHtjy1GiQo+BtyUT3ICYgmCDr5+kMjdUdwDLNfW48I
# HXJIV2VNrwI8QPf03TI4kz/lLKbzWSPLgN4TTfkQyaoKGGxVYVfR8QIsxLWr8mwj
# 0p8NDxlsrYViaf1OhcGKUjGrW9jJdFLjV2wiv1V/b8oGqz9KtyJ2ZezsNvKWlYEm
# LP27mKoBONOvJUCbCVPwKVeFWF7qhUhBIYfl3rTTJrJ7QFNYeY5SMQZNlANFxM48
# A+y3API6IsW0b+XvsIqbAgMBAAGjggHHMIIBwzAMBgNVHRMBAf8EAjAAMGYGA1Ud
# IARfMF0wWwYLYIZIAYb4RQEHFwMwTDAjBggrBgEFBQcCARYXaHR0cHM6Ly9kLnN5
# bWNiLmNvbS9jcHMwJQYIKwYBBQUHAgIwGRoXaHR0cHM6Ly9kLnN5bWNiLmNvbS9y
# cGEwQAYDVR0fBDkwNzA1oDOgMYYvaHR0cDovL3RzLWNybC53cy5zeW1hbnRlYy5j
# b20vc2hhMjU2LXRzcy1jYS5jcmwwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYD
# VR0PAQH/BAQDAgeAMHcGCCsGAQUFBwEBBGswaTAqBggrBgEFBQcwAYYeaHR0cDov
# L3RzLW9jc3Aud3Muc3ltYW50ZWMuY29tMDsGCCsGAQUFBzAChi9odHRwOi8vdHMt
# YWlhLndzLnN5bWFudGVjLmNvbS9zaGEyNTYtdHNzLWNhLmNlcjAoBgNVHREEITAf
# pB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtNjAdBgNVHQ4EFgQUpRMBqZ+F
# zBtuFh5fOzGqeTYAex0wHwYDVR0jBBgwFoAUr2PWyqNOhXLgp7xB8ymiOH+AdWIw
# DQYJKoZIhvcNAQELBQADggEBAEaer/C4ol+imUjPqCdLIc2yuaZycGMv41UpezlG
# Tud+ZQZYi7xXipINCNgQujYk+gp7+zvTYr9KlBXmgtuKVG3/KP5nz3E/5jMJ2aJZ
# EPQeSv5lzN7Ua+NSKXUASiulzMub6KlN97QXWZJBw7c/hub2wH9EPEZcF1rjpDvV
# aSbVIX3hgGd+Yqy3Ti4VmuWcI69bEepxqUH5DXk4qaENz7Sx2j6aescixXTN30cJ
# hsT8kSWyG5bphQjo3ep0YG5gpVZ6DchEWNzm+UgUnuW/3gC9d7GYFHIUJN/HESwf
# AD/DSxTGZxzMHgajkF9cVIs+4zNbgg/Ft4YCTnGf6WZFP3YxggJaMIICVgIBATCB
# izB3MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24x
# HzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsxKDAmBgNVBAMTH1N5bWFu
# dGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0ECEHvU5a+6zAc/oQEjBCJBTRIwCwYJ
# YIZIAWUDBAIBoIGkMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAcBgkqhkiG
# 9w0BCQUxDxcNMjAwNDAzMTg1NjM2WjAvBgkqhkiG9w0BCQQxIgQgtDQMuwPPRsV8
# 4xtsCrTBFQT5hEW02ofKHhWLcFZ3G8UwNwYLKoZIhvcNAQkQAi8xKDAmMCQwIgQg
# xHTOdgB9AjlODaXk3nwUxoD54oIBPP72U+9dtx/fYfgwCwYJKoZIhvcNAQEBBIIB
# AJINlQUs6EEQVguk3ch+EWQSrbGVafQUT/z4S6UYAloZB/cMLD6QkUwORY4lDyI6
# TrZFPLzm0+IImbE7NkPYkadqnPYcDV5bVLlsVZHl0hqSSJj+JbiFpOm+q4B/TqcC
# lvZ8udy2nzOYmXkAsPdBBNIlDj9NHz9Di32PgCIDrZg2NfKNuIsvVwTJfF09WYVN
# +5zPjBeTDUx9yDL/5dEvRvzvkPfMKPOpRPGWpe3+P2wx0akCRr2fYsRM6ICTwklr
# VvZnmrCeOp7zW0u/UArT+pr+UEwHHARNXwoEmegy3CRPnpSmy1gcBasC115jQFkB
# VCccpaRw06AHf4pZIhCP18U=
# SIG # End signature block
