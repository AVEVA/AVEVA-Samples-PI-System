[CmdletBinding()]
param(
    [string[]]
    [Parameter(Position=0)]
    $Groups = @('domain admins','schema admins','enterprise admins'),

    [string[]]
    [Parameter(Mandatory=$true, Position=1)]
    $Members
)

$timeoutInSeconds = 300
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
                $Groups | ForEach-Object{
                    Add-ADGroupMember -Identity $_ -Members $Members
                }
                break
            }           
        }
        catch {
            Start-Sleep -Seconds $elapsedSeconds
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