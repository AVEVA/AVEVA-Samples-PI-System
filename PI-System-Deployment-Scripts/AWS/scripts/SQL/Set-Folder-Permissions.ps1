[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$DomainAdminUser,

    [Parameter(Mandatory=$true)]
    [string]$FileServerNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$SQLServiceAccount,

    # Name Prefix for the stack resource tagging.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$NamePrefix

)

Try{
    Start-Transcript -Path C:\cfn\log\Set-Folder-Permissions.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    # Get exisitng service account password from AWS System Manager Parameter Store.
    $DomainAdminPassword =  (Get-SSMParameterValue -Name "/$NamePrefix/$DomainAdminUser" -WithDecryption $True).Parameters[0].Value
    
    $DomainAdminFullUser = $DomainNetBIOSName + '\' + $DomainAdminUser
    $DomainAdminSecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $DomainAdminCreds = New-Object System.Management.Automation.PSCredential($DomainAdminFullUser, $DomainAdminSecurePassword)

    $SetPermissions={
        $ErrorActionPreference = "Stop"
        $timeoutMinutes=30
        $intervalMinutes=1
        $elapsedMinutes = 0.0
        $startTime = Get-Date
        $stabilized = $false

        While (($elapsedMinutes -lt $timeoutMinutes)) {
            try {
                $acl = Get-Acl C:\witness
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule( $Using:obj, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
                $acl.AddAccessRule($rule)
                Set-Acl C:\witness $acl
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

    $obj = $DomainNetBIOSName + '\WSFCluster1$'
    Invoke-Command -ScriptBlock $SetPermissions -ComputerName $FileServerNetBIOSName -Credential $DomainAdminCreds

    $obj = $DomainNetBIOSName + '\' + $SQLServiceAccount
    Invoke-Command -ScriptBlock $SetPermissions -ComputerName $FileServerNetBIOSName -Credential $DomainAdminCreds

}
Catch{
    $_ | Write-AWSQuickStartException
}
