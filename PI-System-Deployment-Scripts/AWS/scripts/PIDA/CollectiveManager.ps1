# ***********************************************************************
# * All sample code is provided by OSIsoft for illustrative purposes only.
# * These examples have not been thoroughly tested under all conditions.
# * OSIsoft provides no guarantee nor implies any reliability, 
# * serviceability, or function of these programs.
# * ALL PROGRAMS CONTAINED HEREIN ARE PROVIDED TO YOU "AS IS" 
# * WITHOUT ANY WARRANTIES OF ANY KIND. ALL WARRANTIES INCLUDING 
# * THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY
# * AND FITNESS FOR A PARTICULAR PURPOSE ARE EXPRESSLY DISCLAIMED.
# ************************************************************************

param(
    [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "reinit")]
    [switch] $Reinitialize,

    [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "create")]
    [switch] $Create,

    [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "create")]
    [string] $PICollectiveName,

    [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "reinit")]
    [Parameter(Position = 2, Mandatory = $true, ParameterSetName = "create")]
    [string] $PIPrimaryName,

    [Parameter(Position = 2, Mandatory = $true, ParameterSetName = "reinit")]
    [Parameter(Position = 3, Mandatory = $true, ParameterSetName = "create")]
    [string[]] $PISecondaryNames,

    [Parameter(Position = 3, Mandatory = $true, ParameterSetName = "reinit")]
    [Parameter(Position = 4, Mandatory = $true, ParameterSetName = "create")]
    [Int32] $NumberOfArchivesToBackup,

    [Parameter(Position = 4, Mandatory = $true, ParameterSetName = "reinit")]
    [Parameter(Position = 5, Mandatory = $true, ParameterSetName = "create")]
    [string] $BackupLocationOnPrimary,

    [Parameter(Position = 5, Mandatory = $false, ParameterSetName = "reinit")]
    [Parameter(Position = 6, Mandatory = $false, ParameterSetName = "create")]
    [switch] $ExcludeFutureArchives
)

if ((Test-Path '.\SendPrimaryPublicCertToSecondaries.ps1') -eq $false) {
    Write-Error 'missing file: SendPrimaryPublicCertToSecondaries.ps1'
    return
}
if ((Test-Path '.\SendSecondaryPublicCertToPrimary.ps1') -eq $false) {
    Write-Error 'missing file: SendSecondaryPublicCertToPrimary.ps1'
    return
}
if ($Reinitialize -eq $true) {
    $activity = "Reinitalizing Collective from Primary " + $PIPrimaryName
}
else {
    $activity = "Creating Collective " + $PICollectiveName
}

$status = "Connecting to server " + $PIPrimaryName
Write-Progress -Activity $activity -Status $status

$connection = Connect-PIDataArchive -PIDataArchiveMachineName $PIPrimaryName -ErrorAction Stop

[Version] $v395 = "3.4.395"
[Version] $v410 = "3.4.410"
[String] $firstPathArchiveSet1;
$includeSet1 = $false
if ($ExcludeFutureArchives -eq $false -and
    $connection.ServerVersion -gt $v395) {
    Write-Progress -Activity $activity -Status "Getting primary archive"
    $archives = Get-PIArchiveInfo -ArchiveSet 0 -Connection $connection
    $primaryArchive = $archives.ArchiveFileInfo[0].Path

    try {
        $firstPathArchiveSet1 = (Get-PIArchiveInfo -ArchiveSet 1 -Connection $connection -ErrorAction SilentlyContinue).ArchiveFileInfo[0].Path
        if ($firstPathArchiveSet1 -eq $null) {
            # There are no future archives registered
            $includeSet1 = $false
        }
        else {
            # There is at least one future archive registered
            $includeSet1 = $true
        }
    }
    catch {
        $includeSet1 = $false
    }
}
else {
    Write-Progress -Activity $activity -Status "Getting primary archive"
    $archives = Get-PIArchiveInfo -Connection $connection
    $primaryArchive = $archives.ArchiveFileInfo[0].Path
}

if ($Reinitialize -eq $true) {
    ###########################################################
    # Verify connection is the primary member of a collective #
    ###########################################################
    if ($connection.CurrentRole.Type -ne "Primary") {
        Write-Host "Error:" $connection.Address.Host "is not the primary member of a collective."
        exit(-1)
    }

    ##############################################
    # Verify secondary names specified are valid #
    ##############################################
    Write-Progress -Activity $activity -Status "Verifying secondary is part of collective"
    $collectiveMembers = (Get-PICollective -Connection $connection).Members 

    foreach ($secondary in $PISecondaryNames) {
        [bool]$found = $false
        foreach ($member in $collectiveMembers) {
            if ($member.Role -eq "Secondary") {
                if ($member.Name -eq $secondary) {
                    $found = $true
                }
            }
        }

        if ($found -eq $false) {
            Write-Host "Error:" $secondary "is not a secondary node of collective" $connection.Name
            exit(-2)
        }
    }	
}
else {
    #####################################################################
    # Verify primary name specified is not already part of a collective #
    #####################################################################
    if ($connection.CurrentRole.Type -ne "Unspecified") {
        Write-Host "Error:" $PIPrimaryName "is already part of a collective."
        exit(-3)
    }
	
    ###########################################
    # Write collective information to primary #
    ###########################################

    Write-Progress -Activity $activity -Status "Writing collective information to primary"
    $collective = New-PICollective -Name $PICollectiveName -Secondaries $PISecondaryNames -Connection $connection
    ForEach ($secondary in $PISecondaryNames) {
        $path = (Connect-PIDataArchive $secondary | Get-PIDataArchiveDetails).Path
        if ($path -And ($path -contains '.') -And ([bool]($path -as [IPAddress] -eq 'false'))) {		
            $fqdn = $path
        }
        else {
            $wmiHost = Get-WmiObject win32_computersystem -ComputerName $secondary
            $fqdn = $wmiHost.DNSHostName + "." + $wmiHost.Domain
        }
        $collective | Set-PICollectiveMember -Name $secondary -Path $fqdn
    }
}

if ($connection.ServerVersion -ge $v410) {
    ###########################################################
    # Exchange public certificates between collective members #
    ###########################################################
    $storePath = 'OSIsoft LLC Certificates'
    .\SendPrimaryPublicCertToSecondaries.ps1 $PIPrimaryName $storePath $PISecondaryNames
    .\SendSecondaryPublicCertToPrimary.ps1 $PIPrimaryName $PISecondaryNames $storePath
}


####################################################
# Get the PI directory for each of the secondaries #
####################################################

$destinationPIPaths = @{}
foreach ($secondary in $PISecondaryNames) {
    $session = New-PSSession -ComputerName $secondary -ErrorAction Stop -WarningAction Stop
    $destinationPIPaths.Add($secondary, (Invoke-Command -Session $session -ScriptBlock { (Get-ItemProperty (Get-Item HKLM:\Software\PISystem\PI).PSPath).InstallationPath } ))
    Remove-PSSession -Id $session.ID
}

############################
# Stop all the secondaries #
############################

foreach ($secondary in $PISecondaryNames) {
    $status = "Stopping secondary node " + $secondary
    Write-Progress -Activity $activity -Status $status -CurrentOperation "Retrieving dependent services..."
    $pinetmgrService = Get-Service -Name "pinetmgr" -ComputerName $secondary
    $dependentServices = Get-Service -InputObject $pinetmgrService -DependentServices
    $index = 1
    foreach ($dependentService in $dependentServices) {
        if ($dependentService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            Write-Progress -Activity $activity -Status $status -CurrentOperation ("Stopping " + $dependentService.DisplayName) -PercentComplete (($index / ($dependentServices.Count + 1)) * 100)
            Stop-Service -InputObject $dependentService -Force -ErrorAction Stop -WarningAction SilentlyContinue
        }
        $index++
    }
    Write-Progress -Activity $activity -Status $status -CurrentOperation ("Stopping " + $pinetmgrService.Name) -PercentComplete 100
    Stop-Service -InputObject $pinetmgrService -Force -WarningAction SilentlyContinue -ErrorAction Sto
}

###########################
# Flush the archive cache #
###########################

Write-Progress -Activity $activity -Status ("Flushing archive cache on server " + $connection.Name)
Clear-PIArchiveQueue -Connection $connection

#########################
# Backup Primary Server #
#########################

$status = "Backing up PI Server " + $connection.Name
Write-Progress -Activity $activity -Status $status -CurrentOperation "Initializing..."
Start-PIBackup -Connection $connection -BackupLocation $BackupLocationOnPrimary -Exclude pimsgss, SettingsAndTimeoutParameters -ErrorAction Stop
$state = Get-PIBackupState -Connection $connection
while ($state.IsInProgress -eq $true) {
    [int32]$pc = [int32]$state.BackupProgress.OverallPercentComplete
    Write-Progress -Activity $activity -Status $status -CurrentOperation $state.CurrentBackupProgress.CurrentFile -PercentComplete $pc
    Start-Sleep -Milliseconds 500
    $state = Get-PIBackupState -Connection $connection
}

$backupInfo = Get-PIBackupReport -Connection $connection -LastReport

###################################################
# Create restore file for each of the secondaries #
###################################################

foreach ($secondary in $PISecondaryNames) {
    Write-Progress -Activity $activity -Status "Creating secondary restore files" -CurrentOperation $secondary
    $secondaryArchiveDirectory = Split-Path $primaryArchive
    if ($includeSet1 -eq $false) {
        New-PIBackupRestoreFile -Connection $connection -OutputDirectory ($BackupLocationOnPrimary + "\" + $secondary) -NumberOfArchives $NumberOfArchivesToBackup -HistoricalArchiveDirectory $secondaryArchiveDirectory
    }
    else {
        $secondaryArchiveSet1Directory = Split-Path $firstPathArchiveSet1
        $newArchiveDirectories = $secondaryArchiveDirectory, $secondaryArchiveSet1Directory
        New-PIBackupRestoreFile -Connection $connection -OutputDirectory ($BackupLocationOnPrimary + "\" + $secondary) -NumberOfArchives $NumberOfArchivesToBackup -ArchiveSetDirectories $newArchiveDirectories
    }
}

#################################
# Copy Backup to each secondary #
#################################

$backupLocationUNC = "\\" + $PIPrimaryName + "\" + $BackupLocationOnPrimary.SubString(0, 1) + "$" + $BackupLocationOnPrimary.Substring(2)

foreach ($item in $backupInfo.Files) {
    $totalSize += $item.Size
}

foreach ($secondary in $PISecondaryNames) {
    $destinationUNCPIRoot = "\\" + $secondary + "\" + $destinationPIPaths.$secondary.Substring(0, 1) + "$" + $destinationPIPaths.$secondary.Substring(2)

    $status = "Copying backup to secondary node"
    $currentSize = 0
    foreach ($file in $backupInfo.Files) {
        $currentSize += $file.Size
        Write-Progress -Activity $activity -Status $status -CurrentOperation $file.Name -PercentComplete (($currentSize / $totalSize) * 100)
        $sourceUNCFile = "\\" + $connection.Address.Host + "\" + $file.Destination.SubString(0, 1) + "$" + $file.Destination.Substring(2)
        if ($file.ComponentDescription.StartsWith("Archive") -eq $true) {
            $destinationFilePath = Split-Path $file.Destination
            if ($destinationFilePath.EndsWith("arcFuture") -eq $true) {
                $destinationUNCPath = "\\" + $secondary + "\" + $secondaryArchiveSet1Directory.Substring(0, 1) + "$" + $secondaryArchiveSet1Directory.Substring(2)
            }
            else {
                $destinationUNCPath = "\\" + $secondary + "\" + $secondaryArchiveDirectory.Substring(0, 1) + "$" + $secondaryArchiveDirectory.Substring(2)
            }
        }
        else {
            $destinationUNCPath = $destinationUNCPIRoot + (Split-Path $file.Destination).Replace($BackupLocationOnPrimary, "")
        }

        if ((Test-Path -Path $destinationUNCPath) -eq $false) {
            New-Item -Path $destinationUNCPath -ItemType Directory | Out-Null
        }

        Copy-Item -Path $sourceUNCFile -Destination $destinationUNCPath

        $index++
    }

    $piarstatUNC = $backupLocationUNC + "\" + $secondary
    Copy-Item -Path ($piarstatUNC + "\piarstat.dat") -Destination ($destinationUNCPIRoot + "\dat")
    # We only need this file for one server, it's ok to delete it now
    Remove-Item -Path ($piarstatUNC + "\piarstat.dat")
}

########################
# Cleanup backup files #
########################
Start-Sleep -Seconds 30
foreach ($file in $backupInfo.Files) {
    $sourceUNCFile = "\\" + $PIPrimaryName + "\" + $file.Destination.SubString(0, 1) + "$" + $file.Destination.Substring(2)
    Remove-Item -Path $sourceUNCFile
}

[Int32]$count = (Get-ChildItem $backupLocationUNC -Recurse | where {$_.psIsContainer -eq $false}).Count

if ($count -eq 0) {
    Write-Progress -Activity $activity -Status "Removing empty backup directories."
    Remove-Item -Path $backupLocationUNC -Recurse
}

#########################
# Start all secondaries #
#########################

[string[]] $piServices = "pinetmgr", "pimsgss", "pilicmgr", "piupdmgr", "pibasess", "pisnapss", "piarchss", "pibackup"

foreach ($secondary in $PISecondaryNames) {
    foreach ($service in $piServices) {
        $service = Get-Service -ComputerName $secondary -Name $service
        Write-Progress -Activity $activity -Status ("Starting secondary node " + $secondary) -CurrentOperation ("Starting " + $service.DisplayName)
        Start-Service -InputObject $service -WarningAction SilentlyContinue
    }
}
# SIG # Begin signature block
# MIIbzAYJKoZIhvcNAQcCoIIbvTCCG7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA/P20mGtMDGfCe
# /HhO7O6Br8Qm7VRDBaSHcKzT44JT6qCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEINyjM5RUZBpF
# RBF26IYV3K1LeKGwezxujFrWTYSQG02hMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQBe
# XkOfZh+OAB9xkQ3fSLVB+eOvdvKXEy3gtjG91Nk+/So+7WbnrfNAlgADFnHSOkFA
# uutz61Zkr4MQRuDNhDNHClmJXf0MkxvkRphVPPQ+0xN82tS7TW2FCrWyzcbPL7Uq
# sMVCAABeUw1wxB3Ew8mS9pJ6v/uzCPg3jxROIxDtPSg6+ewMFBAmzhgC9WJO/5lW
# EK1YyvnB5ZCNYvOfJyK1FhX3lNKF4LBsS2mu1MWKsVZ4x5F966kacHP336H1J64t
# N7Hlf5hCJ3OD29A+WaT8y4zkd433Uu4/ZJ1cZEi7GnAyvIZQtIBxuWlnOqYHcidg
# yD3z75lPzEpoEDXtaEAYoYIOPTCCDjkGCisGAQQBgjcDAwExgg4pMIIOJQYJKoZI
# hvcNAQcCoIIOFjCCDhICAQMxDTALBglghkgBZQMEAgEwggEPBgsqhkiG9w0BCRAB
# BKCB/wSB/DCB+QIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgois9
# De8CVlVPGtuHiL7sRaCN7vzOH0qFlmf9suk3ou4CFQD4lZMlM2uQsxNXz4WWBLrA
# TpAmlxgPMjAxOTA4MDgxNDU4MDJaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
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
# DQEJBTEPFw0xOTA4MDgxNDU4MDJaMC8GCSqGSIb3DQEJBDEiBCC+2HGE33ItFN8L
# 52PzN7fxMSxd6uVKLy1SkVrj2dzQFzA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# rX/H4zQ8NeQsF3uOdb13ZHaQ3oQ65F7Xfaw5CuaoQcXA9nSKwuGFdaEmvfP2PTM7
# j9rnbhySXnv/wzCsx3GWUvC9EJGmZ/WiUyL4hiyliboQWN9hfZBX0oNlgQhPmMhp
# 0TyvNO0mJI/wFu5FIHCxC0bISCbr9G8YIOlNsjrZqeEzDV8yw/y/al5m+7SloI5n
# rBAB2pEKbNSCRLu10eY1Flpxe7vvRkSTxU5nFp8wswODdYynlHdFMieD4q34INc4
# ST7wjfCljLmO6GPcKezNRXtgQwJaYtihULCdApi5fuduwIg3CLDcIiEXD0a1+Kkv
# T6Wy9VX/SiCVuf4OQCrMDw==
# SIG # End signature block
