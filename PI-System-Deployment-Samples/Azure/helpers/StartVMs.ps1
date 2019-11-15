. "$PSScriptRoot\StartStopTestingVMsFunction.ps1"
 
Get-ChildItem function:\

#$Creds = Get-Credential
$subscription = 'devops-piops-hostedpi-test'
Connect-AzureRmAccount -Subscription $subscription -Credential $Creds

$resourceGroup = 'Final-test'

$dcVmS = (Get-AzureRmVM -ResourceGroupName $resourceGroup | Where-Object {$_.Name -like '*dc*'}).Name
StartStop-AzureRMVMsRunspaces -Subscription $subscription -ResourceGroupName $resourceGroup `
-VMNames $dcVmS -Action 'start' -Credential $Creds

$nondcVmS = (Get-AzureRmVM -ResourceGroupName $resourceGroup | Where-Object {$_.Name -notlike '*dc*'}).Name
StartStop-AzureRMVMsRunspaces -Subscription $subscription -ResourceGroupName $resourceGroup `
-VMNames $nondcVmS -Action 'start' -Credential $Creds

<#
$resourceGroup = 'Single-Experimental'
$dcVmS = (Get-AzureRmVM -ResourceGroupName $resourceGroup | Where-Object {$_.Name -like '*dc*'}).Name
StartStop-AzureRMVMsRunspaces -Subscription $subscription -ResourceGroupName $resourceGroup `
-VMNames $dcVmS -Action 'start' -Credential $Creds

$nondcVmS = (Get-AzureRmVM -ResourceGroupName $resourceGroup | Where-Object {$_.Name -notlike '*dc*'}).Name
StartStop-AzureRMVMsRunspaces -Subscription $subscription -ResourceGroupName $resourceGroup `
-VMNames $nondcVmS -Action 'start' -Credential $Creds

#>