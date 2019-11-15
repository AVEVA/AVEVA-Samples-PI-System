[CmdletBinding()]

param(

    [Parameter(Mandatory=$true)]
    [string]
    $SQLServerVersion

)

try {
    Start-Transcript -Path C:\cfn\log\DownloadSQLEE.ps1.txt -Append

    $ErrorActionPreference = "Stop"

    $DestPath = "C:\sqlinstall"
    New-Item "$DestPath" -Type directory -Force

    if($SQLServerVersion -eq "2014") {
        #$source = "http://download.microsoft.com/download/6/1/9/619E068C-7115-490A-BFE3-09BFDEF83CB9/SQLServer2014-x64-ENU.iso"
        $source = "http://care.dlservice.microsoft.com/dl/download/6/D/9/6D90C751-6FA3-4A78-A78E-D11E1C254700/SQLServer2014SP2-FullSlipstream-x64-ENU.iso"
    }
    elseif ($SQLServerVersion -eq "2016") {
        #$source = "http://download.microsoft.com/download/F/E/9/FE9397FA-BFAB-4ADD-8B97-91234BC774B2/SQLServer2016-x64-ENU.iso"
        $source = "https://download.microsoft.com/download/9/0/7/907AD35F-9F9C-43A5-9789-52470555DB90/ENU/SQLServer2016SP1-FullSlipstream-x64-ENU.iso"
        $ssmssource = "http://download.microsoft.com/download/4/7/2/47218E85-5903-4EF4-B54E-3B71DD558017/SSMS-Setup-ENU.exe"
    }
    elseif ($SQLServerVersion -eq "2017") {
        $source = "https://download.microsoft.com/download/E/F/2/EF23C21D-7860-4F05-88CE-39AA114B014B/SQLServer2017-x64-ENU.iso"
        $ssmssource = "https://download.microsoft.com/download/3/C/7/3C77BAD3-4E0F-4C6B-84DD-42796815AFF6/SSMS-Setup-ENU.exe"
    }

    $tries = 5
    while ($tries -ge 1) {
        try {
            Start-BitsTransfer -Source $source -Destination "$DestPath" -ErrorAction Stop
            if ($SQLServerVersion -in @("2016", "2017")) {
                Start-BitsTransfer -Source $ssmssource -Destination "$DestPath" -ErrorAction Stop
            }
            break
        }
        catch {
            $tries--
            Write-Verbose "Exception:"
            Write-Verbose "$_"
            if ($tries -lt 1) {
                throw $_
            }
            else {
                Write-Verbose "Failed download. Retrying again in 5 seconds"
                Start-Sleep 5
            }
        }
    }
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
    $_ | Write-AWSQuickStartException
}
