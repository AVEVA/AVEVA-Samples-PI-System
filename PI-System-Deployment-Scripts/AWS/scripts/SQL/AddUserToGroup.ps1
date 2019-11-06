param(

	[Parameter(Mandatory=$True)]
	[string]
	$ServerName,

	[Parameter(Mandatory=$True)]
	[string]
	$GroupName,

	[Parameter(Mandatory=$True)]
	[string]
	$DomainNetBIOSName,

	[Parameter(Mandatory=$True)]
	[string]
	$UserName

)

try {
    Start-Transcript -Path C:\cfn\log\AddUserToGroup.ps1.txt -Append

    $ErrorActionPreference = "Stop"

	$timeoutMinutes=30
	$intervalMinutes=1
	$elapsedMinutes = 0.0
	$startTime = Get-Date
	$stabilized = $false

	While (($elapsedMinutes -lt $timeoutMinutes)) {
		try {
			$de = [ADSI]"WinNT://$ServerName/$GroupName,group"
			$UserPath = ([ADSI]"WinNT://$DomainNetBIOSName/$UserName").path
			$de.psbase.Invoke("Add",$UserPath)
			$stabilized = $true
			break
		} catch {
			Start-Sleep -Seconds $($intervalMinutes * 60)
			$elapsedMinutes = ($(Get-Date) - $startTime).TotalMinutes
		}
	}

	if ($stabilized -eq $false) {
		Throw "Item did not propgate within the timeout of $Timeout minutes"
	}
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
    $_ | Write-AWSQuickStartException
}
