[CmdletBinding(DefaultParametersetname="AutoCreds")]
param(
	$PIVisionPath = 'D:\PI_Vision_2019_.exe',
	$PIPath = 'D:\PI Server_2018 SP3_.exe',
    $PIProductID = '04a352f8-8231-4fe7-87cb-68b69becc145',
    $TestFileName = 'PI-System-Deployment-Tests-master.zip',
	
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
        Set-AzureStorageBlobContent -File $x.fullname -Container $StorageContainer.Name -Blob $targetPath -Context $StorageContext -Force:$Force | Out-Null
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
        Set-AzureStorageFileContent -Share $StorageShare -Source $_.FullName -Path $path -Force
    }
}

if (-not $SkipConnect)
{
    # Make connection to Azure
    $azureAccount = Connect-AzureRmAccount
    Select-AzureRmSubscription -SubscriptionName $SubscriptionName
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
    $artifactResourceGroup = Get-AzureRmResourceGroup -Name $ArtifactResourceGroupName -ErrorAction Stop
}
catch
{
    $artifactResourceGroup = New-AzureRmResourceGroup -Name $ArtifactResourceGroupName -Location $Location
}

# Check if specified Artifact Storage Account exists, if not, create it and assign some permissions
try
{
    $artifactStorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ArtifactResourceGroupName -Name $ArtifactStorageAccountName -ErrorAction Stop
}
catch
{
    $artifactStorageAccount = New-AzureRmStorageAccount -ResourceGroupName $ArtifactResourceGroupName -Name $ArtifactStorageAccountName -SkuName $ArtifactStorageAccountSku -Location $Location -Kind $ArtifactStorageAccountKind
}

# Get Context for the created storage account so we can upload files to it
try
{
    $storageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $ArtifactResourceGroupName -Name $ArtifactStorageAccountName).Value[0]
    $storageContext = New-AzureStorageContext -StorageAccountName $ArtifactStorageAccountName -StorageAccountKey $storageAccountKey -ErrorAction Stop
}
catch
{
    Write-Error 'Could not get Azure Storage Context'
    throw
}

# Check if specified Artifact Storage Container exists, otherwise create it
try
{
    $artifactStorageContainer = Get-AzureRmStorageContainer -Name $ArtifactStorageAccountContainerName -ResourceGroupName $ArtifactResourceGroupName -StorageAccountName $ArtifactStorageAccountName -ErrorAction Stop
}
catch
{
    $artifactStorageContainer = New-AzureRmStorageContainer -Name $ArtifactStorageAccountContainerName -ResourceGroupName $ArtifactResourceGroupName -StorageAccountName $ArtifactStorageAccountName -ErrorAction Stop
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
    $artifactStorageAccountFileShare = Get-AzureStorageShare -Name $ArtifactStorageAccountFileShareName -Context $storageContext -ErrorAction Stop
}
catch
{
    $artifactStorageAccountFileShare = New-AzureStorageShare -Name $ArtifactStorageAccountFileShareName -Context $storageContext
}

if ($artifactStorageAccountFileShare -and -not $skipLocalPIArtifact)
{
    Copy-LocalDirectoryToFileShare -SourceFileRoot $LocalArtifactFilePath -StorageContext $storageContext -StorageShare $artifactStorageAccountFileShare
}

# Check if specified resource group to deploy exists, if not, create it
try
{
    $resourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction Stop
}
catch
{
    $resourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
}

# Get SAS Token to pass to deployment so deployment process has access to file in blob storage
$sasTokenDurationHours = 6
$artifactRoot = "https://$ArtifactStorageAccountName.blob.core.windows.net/$ArtifactStorageAccountContainerName"
$sasToken = New-AzureStorageContainerSASToken -Name $ArtifactStorageAccountContainerName -Context $storageContext -Permission 'r' -ExpiryTime (Get-Date).AddHours($sasTokenDurationHours) | ConvertTo-SecureString -AsPlainText -Force

# Create the Azure key vault to store all deployment creds
try {
    if($ManualCreds) {
        New-AzureRmKeyVault -Name $KeyVault -ResourceGroupName $ResourceGroupName -Location $Location -ErrorAction Stop
    }
    else {
        New-AzureRmKeyVault -Name $vaultName -ResourceGroupName $ResourceGroupName -Location $Location -ErrorAction Stop
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
                $secretValue = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $AdminCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzureKeyVaultSecret -VaultName $vaultName -Name $AdminCredential.UserName -SecretValue ($AdminCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
        if ($null -eq $AfCredential) {
            $AfCredential = (Get-Credential -Message "Enter PI Asset Framework service account credentials (exclude domain)")
            try {
                $secretValue = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $AfCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzureKeyVaultSecret -VaultName $vaultName -Name $AfCredential.UserName -SecretValue ($AfCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
        if ($null -eq $AnCredential) {
            $AnCredential = (Get-Credential -Message "Enter PI Analysis service account credentials (exclude domain)")
            try {
                $secretValue = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $AnCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzureKeyVaultSecret -VaultName $vaultName -Name $AnCredential.UserName -SecretValue ($AnCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
        if ($null -eq $VsCredential) {
            $VsCredential = (Get-Credential -Message "Enter PI Web API service account credentials (used for PI Vision; exclude domain)")
            try {
                $secretValue = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $VsCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzureKeyVaultSecret -VaultName $vaultName -Name $VsCredential.UserName -SecretValue ($VsCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
        if ($null -eq $SqlCredential) {
            $SqlCredential = (Get-Credential -Message "Enter SQL Sever service account credentials (exclude domain)")
            try {
                $secretValue = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $SqlCredential.UserName -ErrorAction SilentlyContinue
                if (!$secretValue) {-ErrorAction Stop}
            }
            catch {
                Set-AzureKeyVaultSecret -VaultName $vaultName -Name $SqlCredential.UserName -SecretValue ($SqlCredential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force)
            }
        }
    }

    Else {
        ForEach ($vaultCredential in $vaultCredentials)
        {

            try
            {
                $secretValue = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $vaultCredential
                if (!$secretValue) {-ErrorAction Stop}
                Write-Output "$vaultCredential already exists in $vaultName"

            }
            catch
            {

                $passwordLength = 30
                $nonAlphCh = 10
                Do {
                        #Generate password using .net
                        $password = [System.Web.Security.Membership]::GeneratePassword($PasswordLength, $NonAlphCh)
                    }
                    While ($null -ne (Select-String -InputObject $Password -Pattern "\[+\S*\]+"))
                $secretValue = ConvertTo-SecureString -String $password -AsPlainText -Force
                Set-AzureKeyVaultSecret -VaultName $vaultName -Name $vaultCredential -SecretValue $secretValue
            }
        }

        $AdminCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $adminUser, (Get-AzureKeyVaultSecret -VaultName $vaultName -Name $adminUser).SecretValue
        $AfCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $afServiceAccountName, (Get-AzureKeyVaultSecret -VaultName $vaultName -Name $afServiceAccountName).SecretValue
        $AnCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $anServiceAccountName, (Get-AzureKeyVaultSecret -VaultName $vaultName -Name $anServiceAccountName).SecretValue
        $VsCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $vsServiceAccountName, (Get-AzureKeyVaultSecret -VaultName $vaultName -Name $vsServiceAccountName).SecretValue
        $SqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sqlServiceAccountName, (Get-AzureKeyVaultSecret -VaultName $vaultName -Name $sqlServiceAccountName).SecretValue

    }


<#
# Call DEPLOY.master.template.json
$DeploymentParams = @{
    ResourceGroupName = $ResourceGroupName
    TemplateFile = (Join-Path $PSScriptRoot '..\nested\core\DEPLOY.core.template.json')
    namePrefix = $VMNamePrefix
    adminUsername = $AdminCredential.UserName
    adminPassword = $AdminCredential.Password
    deploymentStorageAccountKey = ($storageAccountKey | ConvertTo-SecureString -AsPlainText -Force)
    deploymentStorageAccountName = ($ArtifactStorageAccountName | ConvertTo-SecureString -AsPlainText -Force)
    deploymentStorageAccountFileShareName = ($ArtifactStorageAccountFileShareName | ConvertTo-SecureString -AsPlainText -Force)
    _artifactRoot = $artifactRoot
    _artifactSasToken = $sasToken

}

Write-Output -Message "Deploying the core using DEPLOY.core.template.json"
New-AzureRmResourceGroupDeployment @DeploymentParams


# Call Backend Deployment
$backendDeploymentParams = @{
    ResourceGroupName = $ResourceGroupName
    TemplateFile = (Join-Path $PSScriptRoot '..\nested\backend\DEPLOY.backend.template.json')
    namePrefix = $VMNamePrefix
    adminUsername = $AdminCredential.UserName
    adminPassword = $AdminCredential.Password
    afServiceAccountUsername = $AfCredential.UserName
    afServiceAccountPassword = $AfCredential.Password
    anServiceAccountUsername = $AnCredential.UserName
    anServiceAccountPassword = $AnCredential.Password
    deploymentStorageAccountKey = ($storageAccountKey | ConvertTo-SecureString -AsPlainText -Force)
    deploymentStorageAccountName = ($ArtifactStorageAccountName | ConvertTo-SecureString -AsPlainText -Force)
    deploymentStorageAccountFileShareName = ($ArtifactStorageAccountFileShareName | ConvertTo-SecureString -AsPlainText -Force)
    _artifactRoot = $artifactRoot
    _artifactSasToken = $sasToken
}

Write-Output -Message "Deploying the backend using DEPLOY.backend.template.json"
New-AzureRmResourceGroupDeployment @backendDeploymentParams

# Call Frontend Deployment
$backendDeploymentParams = @{
    ResourceGroupName = $ResourceGroupName
    TemplateFile = (Join-Path $PSScriptRoot '..\nested\frontend\DEPLOY.frontend.template.json')
    namePrefix = $VMNamePrefix
    adminUsername = $AdminCredential.UserName
    adminPassword = $AdminCredential.Password
    vsServiceAccountUsername = $VsCredential.UserName
    vsServiceAccountPassword = $VsCredential.Password
    deploymentStorageAccountKey = ($storageAccountKey | ConvertTo-SecureString -AsPlainText -Force)
    deploymentStorageAccountName = ($ArtifactStorageAccountName | ConvertTo-SecureString -AsPlainText -Force)
    deploymentStorageAccountFileShareName = ($ArtifactStorageAccountFileShareName | ConvertTo-SecureString -AsPlainText -Force)
    _artifactRoot = $artifactRoot
    _artifactSasToken = $sasToken
}

Write-Output -Message "Deploying the backend using DEPLOY.backend.template.json"
New-AzureRmResourceGroupDeployment @backendDeploymentParams

#>

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
New-AzureRmResourceGroupDeployment @masterDeploymentParams -Verbose

<#
$loadbalancerDeploymentParams = @{
    ResourceGroupName = $ResourceGroupName
    TemplateFile = (Join-Path $PSScriptRoot '..\nested\base\base.loadbalancer.template.json')
    namePrefix = $VMNamePrefix
    lbType = 'rds'
    lbName = 'testrdslb'
    subnetReference = '/subscriptions/3426c00d-8af9-49c0-b965-8690115f3526/resourceGroups/alex-master-test2/providers/Microsoft.Network/virtualNetworks/ds-vnet0/subnets/Public'
}
Write-Output -Message "Deploying test lb"
New-AzureRmResourceGroupDeployment @loadbalancerDeploymentParams -Verbose
#>

# SIG # Begin signature block
# MIIbzAYJKoZIhvcNAQcCoIIbvTCCG7kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA3G2NjIkz4+9EV
# GzLOXDXJyu9CD4yA4fW4j8HQOjbA4KCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIDbUDuB+lOWU
# AnyAEdSavf6t13v8BdPfZjLPcO3HJnP4MDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQBQ
# LHVF9nlX4uqhDvsSNYAeij1Pl/i3Tzid9rz5hc86HtLSm/yeMfYgFhYRA4lOrU4y
# 6XErwdExwUP4TSN1q7QbYxIgqT6xa2AcgHQeAh77jXePQeR8YEiQ8NyZ4u474h0C
# c5PuhVjiobcshTehL3ViUQm9iYayaj38RO6BkKqhD1tEe39ZXEXdx9FHUoqwVUUP
# dlY7yYzfB6sq6ZFKxt9dbR6K+WQ3M7JGq0sC9Y349RTioUNR65OgN/bSxP3zfn+A
# GSvDSZv8LuB3WJXsw17M65HTrO8BBK/BSsoK87YEQacViAW1pf/bflE4VGu2Wl2o
# 6toLyeohq2cEXw7RMi7ooYIOPTCCDjkGCisGAQQBgjcDAwExgg4pMIIOJQYJKoZI
# hvcNAQcCoIIOFjCCDhICAQMxDTALBglghkgBZQMEAgEwggEPBgsqhkiG9w0BCRAB
# BKCB/wSB/DCB+QIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgCiDx
# x8M9DMDdar26i5jfvGAk2OjPO06f7Ug3hBgazioCFQCpdgx1eSztJGn9P8cobFot
# mFMPXhgPMjAxOTEwMzExNDU5MTNaMAMCAR6ggYakgYMwgYAxCzAJBgNVBAYTAlVT
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
# DQEJBTEPFw0xOTEwMzExNDU5MTNaMC8GCSqGSIb3DQEJBDEiBCCUIgmeDq8LOK9r
# wqyggC9BbY53bNvt/b3vna1yDg6lkDA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDE
# dM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h+DALBgkqhkiG9w0BAQEEggEA
# iHhalyFgavGN7ZCwUJDqk8mUzBUxQqFwQGxW9aY2IvOgGYTdMg3hYWagF2MZjCQe
# HPsW1NMay2X3PpWUq19oL/A37udlBp7l8Z+RrBJK1ekIu8GjiFxPLn7VNxScm2pl
# zubQlepK6+HJ12cqvTEUGSDRNWos/Yf9wOoE3k80qc/tZTu2NxiZUytKEe7i3e8N
# jJfU5qCxlGuVOxwPIVe4+PnMdvs1tC7Deg4qBZeR37V5o6PVAua6P8C18Z7g9ubD
# RR8BPLRGxyuAzpolmxlaA1xM+H35x9ZKm0DcDLZWJeDgNJ8WLSp7Ysq/4J1kZrkb
# uqMSdDd1rPnwORUnwKR4eQ==
# SIG # End signature block
