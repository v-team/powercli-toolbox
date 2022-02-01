param([switch] $Report, [switch] $Quarantine, [switch] $Kill, [switch] $TrueSize, [switch] $ReportEmptyFolders, [String] $Skip)

# https://www.lucd.info/2016/09/13/orphaned-files-revisited/
# http://www.hypervisor.fr/?p=3612
# https://blogs.vmware.com/vsphere/2012/10/stop-vs-pause-with-vsphere-replication.html
# https://docs.microsoft.com/en-us/powershell/scripting/developer/help/examples-of-comment-based-help?view=powershell-7.2

$log = Start-Transcript
Write-Host " "
Write-Host -ForegroundColor Cyan "$((Get-Date).ToString("s")) [INFO] Log file: $($log.path)"

if ($($global:DefaultVIServers|Measure-Object).count -ne 1 -or $global:DefaultVIServer.ProductLine -notmatch "vpx") {
    Write-Host -ForegroundColor Red "$((Get-Date).ToString("s")) [ERROR] You must be connected to only ONE vCenter"
    exit 0
} else {
    Write-Host -ForegroundColor White "$((Get-Date).ToString("s")) [INFO] You are connected to vCenter $($global:DefaultVIServer.Name)"
}

if ($Report) {
    Write-Host -ForegroundColor Green "$((Get-Date).ToString("s")) [INFO] Report Mode : Lost files to a csv file only"

    if (!$TrueSize) {
        Write-Host -ForegroundColor Yellow "$((Get-Date).ToString("s")) [INFO] Thin or vSAN provisioned vmdk reported size wont be accurate unless you use the -TrueSize parameter (MUCH slower)"
        $SearchSpecDetails = New-Object VMware.Vim.FileQueryFlags -property @{FileSize = $true ; Modification = $true}
    } else {
        Write-Host -ForegroundColor Yellow "$((Get-Date).ToString("s")) [INFO] TrueSize Mode : Please be patient ..."
        $SearchSpecDetails = New-Object VMware.Vim.FileQueryFlags -property @{FileSize = $true ; Modification = $true ; FileType = $true}
    }

    try {
        Write-Host -ForegroundColor White "$((Get-Date).ToString("s")) [INFO] Collecting objects ..."
        $Datastores = Get-View -ViewType Datastore -Property Name, Browser -Filter @{"summary.accessible" = "true"}|Sort-Object name -unique
        $Vms = Get-View -ViewType virtualmachine -Property LayoutEx -Filter @{"Runtime.ConnectionState" = "connected$"}
        $DatastoresBrowser = Get-View $Datastores.Browser
    } catch {
        Write-Host -ForegroundColor Red "$($Error[0])"
        Stop-Transcript
        exit 0
    }

    $DatastoresHash = @{}
    foreach ($Datastore in $Datastores) {
        if (!$DatastoresHash[$Datastore.Browser.Value]) {
            $DatastoresHash.add($Datastore.Browser.Value, $Datastore.name)
        }
    }
    
    $VmFiles = @()
    $DatastoreFiles = @()
    $LostFiles = @()
    $SearchSpecMatchPattern = @("*zdump*", "*.xml", "*.vmsn", "*.vmsd", "*.vswp*", "*.vmx", "*.vmdk", "*.vmss", "*.nvram", "*.vmxf")

    try {
        Write-Host -ForegroundColor White "$((Get-Date).ToString("s")) [INFO] Searching in datastores ..."

        foreach ($DatastoreBrowser in $DatastoresBrowser) {
        
            # $DatastoreSearch = $($DatastoreBrowser.SearchDatastoreSubFolders($("[" + $DatastoresHash[$DatastoreBrowser.MoRef.Value] + "]"),(New-Object VMware.Vim.HostDatastoreBrowserSearchSpec -property @{matchPattern = $SearchSpecMatchPattern ; details = $SearchSpecDetails ; query = $SearchSpecQuery}))|?{$_.file})
            $DatastoreSearch = $($DatastoreBrowser.SearchDatastoreSubFolders($("[" + $DatastoresHash[$DatastoreBrowser.MoRef.Value] + "]"),(New-Object VMware.Vim.HostDatastoreBrowserSearchSpec -property @{matchPattern = $SearchSpecMatchPattern ; details = $SearchSpecDetails}))|?{$_.file})
        
            foreach ($DatastoreFolder in $DatastoreSearch) {
                if ($DatastoreFolder.FolderPath.ToCharArray()[-1] -ne "/") {
                    $DatastoreFolderPath = $DatastoreFolder.FolderPath + "/"
                } else {
                    $DatastoreFolderPath = $DatastoreFolder.FolderPath
                }
                foreach ($DatastoreFile in $DatastoreFolder.file) {
                    $DatastoreFiles += $DatastoreFile|?{$_.Path -notmatch "-ctk.vmdk|esxconsole.vmdk|esxconsole-flat.vmdk"}|Select-Object @{n="Path";e={$DatastoreFolderPath + $DatastoreFile.path}}, FileSize, Modification|?{$_.path -notmatch ".zfs|.snapshot|var/tmp/cache|/hostCache/|.lck"}
                }
            }
        }

    } catch {
        Write-Host -ForegroundColor Red "$($Error[0])"
        Stop-Transcript
        exit 0
    }
    
    foreach ($VmFile in $Vms.layoutex.file) {
        $VmFiles += $VmFile|?{$_.type -ne "log"}|Select-Object @{n="Path";e={$_.name}}
    }
    
    $RawLostFiles = Compare-Object -passthru -property Path $DatastoreFiles $VmFiles|?{$_.SideIndicator -eq "<="}
    
    foreach ($RawLostFile in $RawLostFiles) {
        if ($Skip) {
            if ($RawLostFile.Path -notmatch $Skip) {
                $LostFiles += $RawLostFile|Select-Object Path, @{n="FileSizeMB";e={[math]::Round($_.FileSize/1MB,0)}}, Modification
            }
        } else {
            $LostFiles += $RawLostFile|Select-Object Path, @{n="FileSizeMB";e={[math]::Round($_.FileSize/1MB,0)}}, Modification
        }
    }
    
    $ExportFileName = ".\LostFileHunterReport_" + $($global:DefaultVIServer.Name) + "_" + $((Get-Date).ToString("s").Replace(":","-")) + ".csv"

    $LostFiles|Export-Csv -Path $ExportFileName

    Write-Host -ForegroundColor Cyan "$((Get-Date).ToString("s")) [INFO] Report file: $ExportFileName"
    if (!$Skip) {
        Write-Host -ForegroundColor White "$((Get-Date).ToString("s")) [INFO] Consider -Skip parameter to filter VM or Datastores names" '(i.e. -Skip "hbrdisk|hbrcfg|kubernetes-dynamic-pvc|content-lib")'
    }
    Stop-Transcript
    exit 0   

} elseif ($Quarantine) {
    Write-Host -ForegroundColor Yellow "$((Get-Date).ToString("s")) [INFO] Quarantine Mode : Lost files will be moved to a quarantine folder"
} elseif ($Kill) {
    Write-Host -ForegroundColor Red "$((Get-Date).ToString("s")) [INFO] Kill Mode : Quarantine folders will be deleted"
    # $Quizz = $null
    # While ($Quizz -cne "YES" -and $Quizz -cne "NO") {
    #     Write-Host ""
    #     Write-Host -ForegroundColor Red "Continue ?"
    #     $Quizz = (Read-Host "[YES/NO]")
    # }                                                                                                          
    # if ($Quizz -ceq "NO") {
    #     Write-Host -ForegroundColor Red "$((Get-Date).ToString("s")) Exiting ..."
    #     Stop-Transcript
    #     exit 1
    # }
} elseif ($ReportEmptyFolders) {

} else {
    Write-Host -ForegroundColor Red "Please select -Report, -Quarantine, -Kill or -ReportEmptyFolders"
    Stop-Transcript
    exit 1
}