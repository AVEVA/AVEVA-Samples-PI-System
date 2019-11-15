[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$PublicSubnet1CIDR,

    [Parameter(Mandatory=$true)]
    [string]$PublicSubnet2CIDR,

    [Parameter(Mandatory=$true)]
    [string]$PrivateSubnet1CIDR,

    [Parameter(Mandatory=$true)]
    [string]$PrivateSubnet2CIDR,

    [Parameter(Mandatory=$true)]
    [string]$Server   
)


$timeoutInSeconds = 300
$elapsedSeconds = 0
$intervalSeconds = 1
$startTime = Get-Date
$running = $false

try {
    While (($elapsedSeconds -lt $timeoutInSeconds )) {
        try {
            $adws = Get-Process -Name Microsoft.ActiveDirectory.WebServices
            if ($adws) {
                $ErrorActionPreference = "Stop"
                Start-Transcript -Path C:\cfn\log\$($MyInvocation.MyCommand.Name).log -Append

                Get-ADObject -SearchBase (Get-ADRootDSE).ConfigurationNamingContext -filter {Name -eq 'Default-First-Site-Name'} | Rename-ADObject -NewName AZ1
                New-ADReplicationSite AZ2 -Server $Server
                New-ADReplicationSubnet -Name $PublicSubnet1CIDR -Site AZ1 -Server $Server
                New-ADReplicationSubnet -Name $PublicSubnet2CIDR -Site AZ2
                New-ADReplicationSubnet -Name $PrivateSubnet1CIDR -Site AZ1
                New-ADReplicationSubnet -Name $PrivateSubnet2CIDR -Site AZ2
                Get-ADReplicationSiteLink -Filter * | Set-ADReplicationSiteLink -SitesIncluded @{add='AZ2'} -ReplicationFrequencyInMinutes 15
                echo "Successfully Configured the AD Sites..."
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