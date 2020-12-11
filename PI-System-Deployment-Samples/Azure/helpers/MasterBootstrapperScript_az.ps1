[CmdletBinding(DefaultParametersetname="AutoCreds")]
param(
    $PIVisionPath = 'D:\PI-Vision_2020_.exe',
    $PIPath = 'D:\PI-Server_2018-SP3-Patch-3_.exe',
    $PIProductID = '63819281-e1d6-4c55-b797-b4d1ca9af535',
    $TestFileName = 'PI-System-Deployment-Tests.zip',
    
    # Parameters passed from StarterScript ********************************************************************************************
    #Deployment target variables (Azure subscr., Azure geo location (eg., 'WestUS'), Azure resource group)
    [Parameter(Mandatory=$true)]
    $SubscriptionName,
    [Parameter(Mandatory=$true)]
    $Location,
    [Parameter(Mandatory=$true)]
    $ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [string]$deployHA,
    [Parameter(Mandatory=$true)]
    $EnableOSIsoftTelemetry,
    [Parameter(Mandatory=$true)]
    $EnableMicrosoftTelemetry,
    
    #*********************************************************************************************************************************

    [Parameter(ParameterSetName='ManualCreds', Mandatory=$true)]
    $KeyVault,

    # Credential should not include the domain, so just username and password
    # Can define as function params or, if left blank, script will prompt user
    [Parameter(ParameterSetName='ManualCreds')]
    [pscredential]
    $AdminCredential,

    [Parameter(ParameterSetName='ManualCreds')]
    [pscredential]
    $AfCredential,

    [Parameter(ParameterSetName='ManualCreds')]
    [pscredential]
    $AnCredential,

    [Parameter(ParameterSetName='ManualCreds')]
    [pscredential]
    $VsCredential,

    [Parameter(ParameterSetName='ManualCreds')]
    [pscredential]
    $SqlCredential,

    $ArtifactResourceGroupName = $ResourceGroupName,
    $ArtifactStorageAccountName,
    $ArtifactStorageAccountContainerName = 'azureds-artifacts',
    # Azure File share to store other artifacts (installers)
    $ArtifactStorageAccountFileShareName = 'pi2018',

    # Local directory for artifacts
    $LocalArtifactFilePath = (Join-Path $PSScriptRoot '..\LocalArtifacts'),
    #*****************************************************************************************************************
    
    # SKU to use if need to create artifact storage account
    $ArtifactStorageAccountSku = 'Standard_LRS',
    # Kind of storage account to use for artifact storage account
    $ArtifactStorageAccountKind = 'StorageV2',
    # Path to pull Nuget packages for DSC modules (Temporary until can host packages somewhere public)
    $LocalNugetSource = (Join-Path $PSScriptRoot '..\LocalNugetPackages'),

    # Path to nuget executable
    $NugetPath = (Join-Path $PSScriptRoot '..\nuget.exe'),

    $VMNamePrefix = 'ds',
    [Parameter(ParameterSetName='ManualCreds')]
    [switch]
    $ManualCreds,
    # Specify to skip connection if already connected
    [switch]
    $SkipConnect,
    # Specify to skip downloading DSC artifacts
    [switch]
    $skipDscArtifact,
    [switch]
    $skipLocalPIArtifact,
    $DSCName
)

#  Ensure deployHA, EnableMicrosoftTelemetry and EnableOSIsoftTelemetry parameters from starter script are lowercase
$deployHA = $deployHA.ToLower()
$EnableMicrosoftTelemetry = $EnableMicrosoftTelemetry.ToLower()
$EnableOSIsoftTelemetry = $EnableOSIsoftTelemetry.ToLower()

# https://blogs.technet.microsoft.com/389thoughts/2017/12/23/get-uniquestring-generate-unique-id-for-azure-deployments/
function Get-UniqueString ([string]$id, $length=13)
{
    $hashArray = (new-object System.Security.Cryptography.SHA512Managed).ComputeHash($id.ToCharArray())
    -join ($hashArray[1..$length] | ForEach-Object { [char]($_ % 26 + [byte][char]'a') })
}

# "Resource group name"-determined unique string used for creating globally unique Azure resources
$rgString = Get-UniqueString -id $ResourceGroupName -length 5

# Variables used for automatic creation of creds when none are specifed at deployment
[string]$vaultName = ($VMNamePrefix+'-vault-'+$rgString)
[string]$adminUser = ($VMNamePrefix+'-admin')
[string]$afServiceAccountName = ($VMNamePrefix+'-piaf-svc')
[string]$anServiceAccountName = ($VMNamePrefix+'-pian-svc')
[string]$vsServiceAccountName = ($VMNamePrefix+'-pivs-svc')
[string]$sqlServiceAccountName = ($VMNamePrefix+'-sql-svc')
$vaultCredentials = (
    $adminUser,
    $afServiceAccountName,
    $anServiceAccountName,
    $vsServiceAccountName,
    $sqlServiceAccountName
)


# https://stackoverflow.com/questions/38354888/upload-files-and-folder-into-azure-blob-storage
function Copy-LocalDirectoryToBlobStorage
{
    param(
        $SourceFileRoot,
        $StorageContext,
        $StorageContainer
    )
    $sourceRoot = Get-Item $SourceFileRoot
    $filesToUpload = Get-ChildItem $SourceFileRoot -Recurse -File
    # TODO: Make this path manipulation more robust
    foreach ($x in $filesToUpload) {
        $targetPath = $sourceRoot.Name + "/" + ($x.fullname.Substring($sourceRoot.FullName.Length + 1)).Replace("\\", "/")
        Write-Verbose "targetPath: $targetPath"
        Write-Verbose "Uploading $("\" + $x.fullname.Substring($sourceRoot.FullName.Length + 1)) to $($StorageContainer.CloudBlobContainer.Uri.AbsoluteUri + "/" + $targetPath)"
        Set-AzStorageBlobContent -File $x.fullname -Container $StorageContainer.Name -Blob $targetPath -Context $StorageContext -Force
    }
}

function Copy-LocalDirectoryToFileShare
{
    param(
        $SourceFileRoot,
        $StorageShare
    )
    $sourceRoot = Get-Item $SourceFileRoot
    Get-ChildItem -Path $SourceFileRoot -Recurse | Where-Object { $_.GetType().Name -eq "FileInfo"} | ForEach-Object {
        $path=$_.FullName.Substring($sourceRoot.FullName.Length+1).Replace("\","/")
        Set-AzStorageFileContent -ShareName $ArtifactStorageAccountFileShareName -Context $storageContext -Source $_.FullName -Path $path -Force
    }
}

function Get-RandomCharacters($length, $characters) { 
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length } 
    $private:ofs="" 
    return [String]$characters[$random]
}

function Scramble-String([string]$inputString){     
    $characterArray = $inputString.ToCharArray()   
    $scrambledStringArray = $characterArray | Get-Random -Count $characterArray.Length     
    $outputString = -join $scrambledStringArray
    return $outputString 
}

if (-not $SkipConnect)
{
    # Make connection to Azure
    $azureAccount = Connect-AzAccount
    Select-AzSubscription -Subscription $SubscriptionName
}

# Set default ArtifactStorageAccountName using the Get-UniqueString function
if (-not $ArtifactStorageAccountName) { $ArtifactStorageAccountName = 'osiazureds' + (Get-UniqueString -id $ArtifactResourceGroupName -length 12) }

# Generate Artifact Zip files that are used by DSC
if (-not $skipDscArtifact) {
$dscArtifactPath = (Join-Path $env:temp 'dsc')
$dscArtifactParams = @{
    NugetPath = $NugetPath
    LocalNugetSource = $LocalNugetSource
    OutputDirectory = $dscArtifactPath
}
if ($null -ne $DSCName) {
    $dscArtifactParams.add("DSCName",$DSCName)
}
& (Join-Path $PSScriptRoot 'CreateDSCArtifactZip.ps1') @dscArtifactParams
}

# Check if specified Artifact Resource Group exists, if not, create it
try
{
    $artifactResourceGroup = Get-AzResourceGroup -Name $ArtifactResourceGroupName -ErrorAction Stop
}
catch
{
    $artifactResourceGroup = New-AzResourceGroup -Name $ArtifactResourceGroupName -Location $Location
}

# Check if specified Artifact Storage Account exists, if not, create it and assign some permissions
try
{
    $artifactStorageAccount = Get-AzStorageAccount -ResourceGroupName $ArtifactResourceGroupName -Name $ArtifactStorageAccountName -ErrorAction Stop
}
catch
{
    $artifactStorageAccount = New-AzStorageAccount -ResourceGroupName $ArtifactResourceGroupName -Name $ArtifactStorageAccountName -SkuName $ArtifactStorageAccountSku -Location $Location -Kind $ArtifactStorageAccountKind
}

# Get Context for the created storage account so we can upload files to it
try
{
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ArtifactResourceGroupName -Name $ArtifactStorageAccountName).Value[0]
    $storageContext = New-AzStorageContext -StorageAccountName $ArtifactStorageAccountName -StorageAccountKey $storageAccountKey -ErrorAction Stop
}
catch
{
    Write-Error 'Could not get Azure Storage Context'
    throw
}

# Check if specified Artifact Storage Container exists, otherwise create it
try
{
    $artifactStorageContainer = Get-AzRmStorageContainer -Name $ArtifactStorageAccountContainerName -ResourceGroupName $ArtifactResourceGroupName -StorageAccountName $ArtifactStorageAccountName -ErrorAction Stop
}
catch
{
    $artifactStorageContainer = New-AzRmStorageContainer -Name $ArtifactStorageAccountContainerName -ResourceGroupName $ArtifactResourceGroupName -StorageAccountName $ArtifactStorageAccountName -ErrorAction Stop
}

# Upload the necessary files to blob storage (ARM Templates, DSC Artifacts, Deployment Scripts)
if ($artifactStorageContainer)
{
    $nestedRoot = (Get-Item (Join-Path $PSScriptRoot '..\nested')).FullName
    $deploymentScriptsRoot = (Get-Item (Join-Path $PSScriptRoot '..\scripts\deployment')).FullName
    Copy-LocalDirectoryToBlobStorage -SourceFileRoot $nestedRoot -StorageContext $storageContext -StorageContainer $artifactStorageContainer
    if (-not $skipDscArtifact) {
    Copy-LocalDirectoryToBlobStorage -SourceFileRoot $dscArtifactPath -StorageContext $storageContext -StorageContainer $artifactStorageContainer
    }
    Copy-LocalDirectoryToBlobStorage -SourceFileRoot $deploymentScriptsRoot -StorageContext $storageContext -StorageContainer $artifactStorageContainer
}

try
{
    $artifactStorageAccountFileShare = Get-AzStorageShare -Name $ArtifactStorageAccountFileShareName -Context $storageContext -ErrorAction Stop
}
catch
{
    $artifactStorageAccountFileShare = New-AzStorageShare -Name $ArtifactStorageAccountFileShareName -Context $storageContext
}

if ($artifactStorageAccountFileShare -and -not $skipLocalPIArtifact)
{
    Copy-LocalDirectoryToFileShare -SourceFileRoot $LocalArtifactFilePath -StorageContext $storageContext -StorageShare $artifactStorageAccountFileShare
}

# Check if specified resource group to deploy exists, if not, create it
try
{
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
}
catch
{
    $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
}

# Get SAS Token to pass to deployment so deployment process has access to file in blob storage
$sasTokenDurationHours = 6
$artifactRoot = "https://$ArtifactStorageAccountName.blob.core.windows.net/$ArtifactStorageAccountContainerName"
$sasToken = New-AzStorageContainerSASToken -Name $ArtifactStorageAccountContainerName -Context $storageContext -Permission 'r' -ExpiryTime (Get-Date).AddHours($sasTokenDurationHours) | ConvertTo-SecureString -AsPlainText -Force

# Create the Azure key vault to store all deployment creds
try {
    if($ManualCreds) {
        Write-Output -Message "ManualCreds: Create key value"
        New-AzKeyVault -VaultName $KeyVault -ResourceGroupName $ResourceGroupName -Location $Location -SoftDeleteRetentionInDays 7 -ErrorAction Stop
    }
    else {
      Write-Output -Message "Create key value"
      New-AzKeyVault -VaultName $vaultName -ResourceGroupName $ResourceGroupName -Location $Location -SoftDeleteRetentionInDays 7  -ErrorAction Stop
    }
}
catch
{
    Write-Host $_.Exception.Message
}

# If manual creds are used, user is prompted for creds to be used. These creds are also stored in an Azure key vault
if ($ManualCreds) {
    # Prepare variables to be passed
        if ($null -eq $AdminCredential) {
            $AdminCredential = (Get-Credential -Message "Enter domain admin credentials (exclude domain)")
            try {
                $secretValue = Get-AzKeyVaultSecret -VaultName $vaultName -Name $AdminCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzKeyVaultSecret -VaultName $vaultName -Name $AdminCredential.UserName -SecretValue ($AdminCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
        if ($null -eq $AfCredential) {
            $AfCredential = (Get-Credential -Message "Enter PI Asset Framework service account credentials (exclude domain)")
            try {
                $secretValue = Get-AzKeyVaultSecret -VaultName $vaultName -Name $AfCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzKeyVaultSecret -VaultName $vaultName -Name $AfCredential.UserName -SecretValue ($AfCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
        if ($null -eq $AnCredential) {
            $AnCredential = (Get-Credential -Message "Enter PI Analysis service account credentials (exclude domain)")
            try {
                $secretValue = Get-AzKeyVaultSecret -VaultName $vaultName -Name $AnCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzKeyVaultSecret -VaultName $vaultName -Name $AnCredential.UserName -SecretValue ($AnCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
        if ($null -eq $VsCredential) {
            $VsCredential = (Get-Credential -Message "Enter PI Web API service account credentials (used for PI Vision; exclude domain)")
            try {
                $secretValue = Get-AzKeyVaultSecret -VaultName $vaultName -Name $VsCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzKeyVaultSecret -VaultName $vaultName -Name $VsCredential.UserName -SecretValue ($VsCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
        if ($null -eq $SqlCredential) {
            $SqlCredential = (Get-Credential -Message "Enter SQL Sever service account credentials (exclude domain)")
            try {
                $secretValue = Get-AzKeyVaultSecret -VaultName $vaultName -Name $SqlCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzKeyVaultSecret -VaultName $vaultName -Name $SqlCredential.UserName -SecretValue ($SqlCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
    }

    Else {
        ForEach ($vaultCredential in $vaultCredentials)
        {

            try
            {
                $secretValue = Get-AzKeyVaultSecret -VaultName $vaultName -Name $vaultCredential
                if (!$secretValue) {-ErrorAction Stop}
                Write-Output "$vaultCredential already exists in $vaultName"

            }
            catch
            {
                $password = Get-RandomCharacters -length 15 -characters 'abcdefghiklmnoprstuvwxyz'
                $password += Get-RandomCharacters -length 5 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
                $password += Get-RandomCharacters -length 5 -characters '1234567890'
                $password += Get-RandomCharacters -length 5 -characters '!$#%'
                $password = Scramble-String $password 
                
                $secretValue = ConvertTo-SecureString -String $password -AsPlainText -Force
                Set-AzKeyVaultSecret -VaultName $vaultName -Name $vaultCredential -SecretValue $secretValue
            }
        }

        $AdminCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $adminUser, (Get-AzKeyVaultSecret -VaultName $vaultName -Name $adminUser).SecretValue
        $AfCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $afServiceAccountName, (Get-AzKeyVaultSecret -VaultName $vaultName -Name $afServiceAccountName).SecretValue
        $AnCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $anServiceAccountName, (Get-AzKeyVaultSecret -VaultName $vaultName -Name $anServiceAccountName).SecretValue
        $VsCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $vsServiceAccountName, (Get-AzKeyVaultSecret -VaultName $vaultName -Name $vsServiceAccountName).SecretValue
        $SqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sqlServiceAccountName, (Get-AzKeyVaultSecret -VaultName $vaultName -Name $sqlServiceAccountName).SecretValue

    }

# Call Frontend Deployment
$masterDeploymentParams = @{
    ResourceGroupName = $ResourceGroupName
    TemplateFile = (Join-Path $PSScriptRoot '..\nested\base\DEPLOY.master.template.json')
    namePrefix = $VMNamePrefix
    EnableMicrosoftTelemetry = $EnableMicrosoftTelemetry
    EnableOSIsoftTelemetry = $EnableOSIsoftTelemetry
    PIVisionPath = $PIVisionPath
    PIPath = $PIPath
    PIProductID = $PIProductID
    TestFileName = $TestFileName
    deployHA = $deployHA
    adminUsername = $AdminCredential.UserName
    adminPassword = $AdminCredential.Password
    afServiceAccountUsername = $AfCredential.UserName
    afServiceAccountPassword = $AfCredential.Password
    anServiceAccountUsername = $AnCredential.UserName
    anServiceAccountPassword = $AnCredential.Password
    sqlServiceAccountUsername = $SqlCredential.UserName
    sqlServiceAccountPassword = $SqlCredential.Password
    vsServiceAccountUsername = $VsCredential.UserName
    vsServiceAccountPassword = $VsCredential.Password
    deploymentStorageAccountKey = ($storageAccountKey | ConvertTo-SecureString -AsPlainText -Force)
    deploymentStorageAccountName = ($ArtifactStorageAccountName | ConvertTo-SecureString -AsPlainText -Force)
    deploymentStorageAccountFileShareName = ($ArtifactStorageAccountFileShareName | ConvertTo-SecureString -AsPlainText -Force)
    _artifactRoot = $artifactRoot
    _artifactSasToken = $sasToken
}

Write-Output -Message "Deploying the full environment using DEPLOY.master.template.json"
Write-Output -Message $PIVisionPath
Write-Output -Message $PIPath
Write-Output -Message $PIProductID
New-AzResourceGroupDeployment @masterDeploymentParams -Verbose

# SIG # Begin signature block
# MIIcVwYJKoZIhvcNAQcCoIIcSDCCHEQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBSQkp/WDhAPb0O
# vJ9yOOf8tu1aTquV7kGkzQqp+7KlZ6CCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgPJI27cRUpVll
# KTpfKT9TBLfmBEu8ty2z3/o8E58aDBMwMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBACir
# GJDCbV/6vvGzpus3irUTpKkcDhPkqLdyejX3sHrmmzAUqBvArFO3O6T/qIXDn0+B
# jhejiDnzj8uFgkV+Czt6SHwrIjGqcjri8Z1ePEs7Dzf2KrGMnmfLsymLuCpvXwnY
# k++7O6FLXVzfnP1uANzBEXxlDG944COCHiRMMevl+sy6PWZ3ZZnZJqduP9rz8QWg
# WKgIHNiEA0onf5+tMN4YV4Q2FIWb6wsocwln8oFuOw7ZnmmSxDkD61S9vG/+tXG4
# IliEdnclQ65JWWA47GOabp9cErYz61D/MnaI09FGeD/t6GaA9FqqvaiBB66QWAmi
# KwZnqU3UxiCoITFgUlahgg7JMIIOxQYKKwYBBAGCNwMDATGCDrUwgg6xBgkqhkiG
# 9w0BBwKggg6iMIIOngIBAzEPMA0GCWCGSAFlAwQCAQUAMHgGCyqGSIb3DQEJEAEE
# oGkEZzBlAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQgUCQStJ3cNo2s
# Q8PTpFe01qi6y2dQvRPVWhCunMuMK5gCEQCVoAWK2Ux5cLOduLWOTyI/GA8yMDIw
# MTEyNDIxNDk0N1qgggu7MIIGgjCCBWqgAwIBAgIQBM0/hWiudsYbsP5xYMynbTAN
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
# KoZIhvcNAQkFMQ8XDTIwMTEyNDIxNDk0N1owKwYLKoZIhvcNAQkQAgwxHDAaMBgw
# FgQUAyW9UF7aljAtwi9PoB5MKL4oNMUwLwYJKoZIhvcNAQkEMSIEID6pmOaWid4r
# PrLHvojJrnhtawlHjIle2OnrQr73GkTxMA0GCSqGSIb3DQEBAQUABIIBAKDbhuGi
# 9Z2osov6qCfhyIG1fCcj54h1WODOXYWV9LPqC6eOe1Pn3eEwZcIe0cFrShRmKoRV
# boPX0MxF4aFcIlRSXpRxGxWGbU3pf4YBvPcTbhj6oIr5/3TLsevbYY8h1z/LbzRD
# iqyU36maBbDryjCa12vXGAg/AFLufz4n6QJoPZJh4xIdXCH/9wY1s3VpcazrKz3A
# Y8yvVQqkZmpSrt5Zt162tUn6CZqH1uf8wgM5ZFTvGanfSjavcUwwPMHkODP9vNYo
# CwJV4VHmPEhsoztEyfmW5Sq9Xqm2FEskur6qfkS1jA8z0s2/nTZAYay/F1xCWnQw
# R8fY8FxHhl/4Ekw=
# SIG # End signature block
