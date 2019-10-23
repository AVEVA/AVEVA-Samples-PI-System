[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainAdminUser,

    [Parameter(Mandatory=$true)]
    [string]$Server,

    [Parameter(Mandatory=$true)]
    [string]$DomainDNSName,

    [Parameter(Mandatory=$true)]
    [string]$SSMParamName
) 

$timeoutInSeconds = 600
$elapsedSeconds = 0
$intervalSeconds = 1
$startTime = Get-Date
$running = $false

try {
    $ErrorActionPreference = "Stop"
    Start-Transcript -Path C:\cfn\log\$($MyInvocation.MyCommand.Name).log -Append

    While (($elapsedSeconds -lt $timeoutInSeconds )) {
        try {
            $adws = Get-Process -Name Microsoft.ActiveDirectory.WebServices
            if ($adws) {
                $DomainAdminPassword = (Get-SSMParameterValue -Names $SSMParamName).Parameters[0].Value
				Remove-SSMParameter -Name $SSMParamName -Force
				Start-Sleep -Seconds 5
                Write-SSMParameter -Name $SSMParamName -Type SecureString -Value $DomainAdminPassword -Description "Deployment Sample Domain Admin Account"-Overwrite $true
                $Admin = $DomainAdminUser+"@"+$DomainDNSName
                New-ADUser -Name $DomainAdminUser -UserPrincipalName $Admin -AccountPassword (ConvertTo-SecureString $DomainAdminPassword  -AsPlainText -Force) -Enabled $true -PasswordNeverExpires $true -Server $Server
                echo "Successfully Created the Admin User..."
                break
            }           
        }
        catch {
            Start-Sleep -Seconds $intervalSeconds
            $elapsedSeconds = ($(Get-Date) - $startTime).TotalSeconds
            echo "Elapse Seconds" $elapsedSeconds 
            
        }
        if ($elapsedSeconds -ge $timeoutInSeconds) {
            Throw "ADWS did not start or is unreachable in $timeoutInSeconds seconds..."
        }
    }

}
catch {
    $_ | Write-AWSQuickStartException
}
