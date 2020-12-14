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
# MIIcVwYJKoZIhvcNAQcCoIIcSDCCHEQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA/P20mGtMDGfCe
# /HhO7O6Br8Qm7VRDBaSHcKzT44JT6qCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg3KMzlFRkGkVE
# EXbohhXcrUt4obB7PG6MWtZNhJAbTaEwMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAMB7
# YjikMU3rMpTlRyyG3LL+RVPnXzUYH4VZnk1itKVsdjnGsaBjxc5h+ZR6mNdXaZdD
# VlngujK3pniJmT3lTdvbK+xXMbAN+HWiMp/cWJzTM0pliJaccL4lXeBIxnZKacDk
# GkWn6LouRL6240zKH2y5AwxQ/1eEaWwqkJ4haVFUxwV+WoX/Xvs73oABoFdhKFyK
# xUfarpi1oICOc5cVO3sNiohcsNC8d99M9BoktKt0eY+0H5eFuo4lprfK9ShwC7zw
# kAkC1H+FsvbRoaTAd4HeTFSS/+xUR2CIDcpsT8IQjx9z4lwy+qnSnym11AsyydrD
# k5XMlC/2eed/CfLVvKWhgg7JMIIOxQYKKwYBBAGCNwMDATGCDrUwgg6xBgkqhkiG
# 9w0BBwKggg6iMIIOngIBAzEPMA0GCWCGSAFlAwQCAQUAMHgGCyqGSIb3DQEJEAEE
# oGkEZzBlAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQguh9QGKKRO2ue
# BrBfa4reDQenvyI1tbKZm7vcDgThQLYCEQC2J6MVt+Boqoq5sFwFyx9pGA8yMDIw
# MTExMTE3MjczMVqgggu7MIIGgjCCBWqgAwIBAgIQBM0/hWiudsYbsP5xYMynbTAN
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
# KoZIhvcNAQkFMQ8XDTIwMTExMTE3MjczMVowKwYLKoZIhvcNAQkQAgwxHDAaMBgw
# FgQUAyW9UF7aljAtwi9PoB5MKL4oNMUwLwYJKoZIhvcNAQkEMSIEIOh8lbxA23CW
# EeK8ZkJfxSkO1TcpAWF8tF+TK1nKAigDMA0GCSqGSIb3DQEBAQUABIIBAGkIEt2Q
# CPZ8jraEgQGtbt6dNJbKOcYTuBFto4xXsEHCuUtWCtw+i6jkIODMfsYimu7EQQgD
# CR9j99rbxQTJgZSfkLivxfzANTbNs6NmN3064FFmY1K/VZLyvFhtFPuO+fdN882o
# 6oBOyY9tnjN7Q/2GLBex8kSG/w2H5UL8SrnfqoQVFKKGQhc2karUj7RSTLeLxmoK
# Eq8CEkFegWpDUaZV7qNFSeQMwVkUgVwa12wjQ3NfhR8Rakrigi6qaZ9PCjWAOOXV
# OZS52IFljVQbH27OvbTr24zq2Ica5Pg0bsY1zpBhygIdKdgwY0ZVMEKMppWdc65X
# MXRdjNKrOokKahY=
# SIG # End signature block
