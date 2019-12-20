[CmdletBinding()]
param(

    [Parameter(Mandatory=$false)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$false)]
    [string]$DomainDNSName,

    [Parameter(Mandatory=$false)]
    [string]$ServerName='*'
)

try {
    Start-Transcript -Path C:\cfn\log\EnableCredSsp.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    Enable-WSManCredSSP Client -DelegateComputer $ServerName -Force
    if ($DomainNetBIOSName) {
        Enable-WSManCredSSP Client -DelegateComputer *.$DomainNetBIOSName -Force
    }
    if ($DomainDNSName) {
        Enable-WSManCredSSP Client -DelegateComputer *.$DomainDNSName -Force
    }
    Enable-WSManCredSSP Server -Force

    # Sometimes Enable-WSManCredSSP doesn't get it right, so we set some registry entries by hand
    $parentkey = "hklm:\SOFTWARE\Policies\Microsoft\Windows"
    $key = "$parentkey\CredentialsDelegation"
    $freshkey = "$key\AllowFreshCredentials"
    $ntlmkey = "$key\AllowFreshCredentialsWhenNTLMOnly"
    New-Item -Path $parentkey -Name 'CredentialsDelegation' -Force
    New-Item -Path $key -Name 'AllowFreshCredentials' -Force
    New-Item -Path $key -Name 'AllowFreshCredentialsWhenNTLMOnly' -Force
    New-ItemProperty -Path $key -Name AllowFreshCredentials -Value 1 -PropertyType Dword -Force
    New-ItemProperty -Path $key -Name ConcatenateDefaults_AllowFresh -Value 1 -PropertyType Dword -Force
    New-ItemProperty -Path $key -Name AllowFreshCredentialsWhenNTLMOnly -Value 1 -PropertyType Dword -Force
    New-ItemProperty -Path $key -Name ConcatenateDefaults_AllowFreshNTLMOnly -Value 1 -PropertyType Dword -Force
    New-ItemProperty -Path $freshkey -Name 1 -Value "WSMAN/$ServerName" -PropertyType String -Force
    New-ItemProperty -Path $ntlmkey -Name 1 -Value "WSMAN/$ServerName" -PropertyType String -Force
    if ($DomainNetBIOSName) {
        New-ItemProperty -Path $freshkey -Name 2 -Value "WSMAN/$ServerName.$DomainNetBIOSName" -PropertyType String -Force
        New-ItemProperty -Path $ntlmkey -Name 2 -Value "WSMAN/$ServerName.$DomainNetBIOSName" -PropertyType String -Force
    }
    if ($DomainDNSName) {
        New-ItemProperty -Path $freshkey -Name 2 -Value "WSMAN/$ServerName.$DomainDNSName" -PropertyType String -Force
        New-ItemProperty -Path $ntlmkey -Name 2 -Value "WSMAN/$ServerName.$DomainDNSName" -PropertyType String -Force
    }

}
catch {
    $_ | Write-AWSQuickStartException
}
