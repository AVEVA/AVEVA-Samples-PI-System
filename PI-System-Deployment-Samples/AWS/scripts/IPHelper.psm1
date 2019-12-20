function Get-AWSDefaultGateway{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({[System.Net.IPAddress]::Parse($_)})]
        [string]
        $IPAddress
    )
    
    try {
        Write-Verbose "Formatting IP gateway"
        $octets = $IPAddress.Split('.')
        $gateway = "{0}.{1}.{2}.{3}" -f $octets[0], $octets[1], $octets[2], "1"

        Write-Verbose "Returning gateway address"
        Write-Output $gateway    
    }
    catch {
        $_ | Write-AWSQuickStartException
    }
}

function Get-AWSSubnetMask {
    [CmdletBinding()]
    param(
        [string]
        $SubnetCIDR
    )

    try {
        Write-Verbose "Returning subnet bits"
        Write-Output $SubnetCIDR.Split('/')[1]    
    }
    catch {
        $_ | Write-AWSQuickStartException
    }    
}