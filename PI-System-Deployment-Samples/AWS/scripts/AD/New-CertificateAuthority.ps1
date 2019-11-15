[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Username,

    [Parameter(Mandatory=$true)]
    [string]$DomainDNSName,

    [Parameter(Mandatory=$false)]
    [string]$Password,

    [Parameter(Mandatory=$false)]
    [string]$SSMParamName
)

<#
    Requires xAdcsDeployment DSC Resource: https://www.powershellgallery.com/packages/xAdcsDeployment/1.4.0.0
#>
$SSMParamUsed = $false

if (([string]::IsNullOrEmpty($Password)) -and ([string]::IsNullOrEmpty($SSMParamName))) {
   Throw "You must pass either a Password or an SSMParamName argument"   
}
Elseif(-not ([string]::IsNullOrEmpty($SSMParamName))) {
   echo "SSMParamName argument used"
   $SSMParamUsed = $true
}
Else {
   echo "Password argument used"
}

if ($SSMParamUsed -eq "True") {
   $Password = (Get-SSMParameterValue -Names $SSMParamName -WithDecryption $True).Parameters[0].Value
}


$Pass = ConvertTo-SecureString $Password -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential -ArgumentList "$Username@$DomainDNSName", $Pass

$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName = $env:COMPUTERNAME
            PSDscAllowPlainTextPassword = $true
        }
    )
}

Configuration CertificateAuthority {      
    Import-DscResource -ModuleName xAdcsDeployment -ModuleVersion 1.4.0.0
       
    Node $AllNodes.NodeName
    {   
        WindowsFeature ADCS-Cert-Authority 
        { 
               Ensure = 'Present' 
               Name = 'ADCS-Cert-Authority' 
        } 
        xADCSCertificationAuthority ADCS 
        { 
            Ensure = 'Present' 
            Credential = $Credential
            CAType = 'EnterpriseRootCA' 
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority'               
        } 
        WindowsFeature ADCS-Web-Enrollment 
        { 
            Ensure = 'Present' 
            Name = 'ADCS-Web-Enrollment' 
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority' 
        } 
        WindowsFeature RSAT-ADCS 
        { 
            Ensure = 'Present' 
            Name = 'RSAT-ADCS' 
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority' 
        } 
        WindowsFeature RSAT-ADCS-Mgmt 
        { 
            Ensure = 'Present' 
            Name = 'RSAT-ADCS-Mgmt' 
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority' 
        } 
        xADCSWebEnrollment CertSrv 
        { 
            Ensure = 'Present' 
            IsSingleInstance = 'Yes'
            Credential = $Credential
            DependsOn = '[WindowsFeature]ADCS-Web-Enrollment','[xADCSCertificationAuthority]ADCS' 
        }  
    }   
}

try {
    $ErrorActionPreference = "Stop"
    Start-Transcript -Path C:\cfn\log\$($MyInvocation.MyCommand.Name).log -Append
    CertificateAuthority -ConfigurationData $ConfigurationData
    Start-DscConfiguration -Path .\CertificateAuthority -Wait -Verbose -Force
    Get-ChildItem .\CertificateAuthority *.mof -ErrorAction SilentlyContinue | Remove-Item -Confirm:$false -ErrorAction SilentlyContinue

    Get-ChildItem C:\Windows\system32\CertSrv\CertEnroll *.crt | Copy-Item -Destination c:\inetpub\wwwroot\cert.crt

}

catch {
    $_ | Write-AWSQuickStartException
}