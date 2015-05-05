param( 
	[array]$SrcDatastores,
	[array]$DstDatastores = $SrcDatastores,
	[string]$vDiskFormat = "as-source",
	[int]$FreeSpaceDeviation = "10",
	[int]$Force = "0",
	[int]$DatastoreFreeLimit = "10",
	[int]$mailcheck = "0",
	[string]$clustername,
	[int]$bypass = "0",
	[int]$vi5 = "0",
	[int]$drainreport = "0",
	[int]$StoragePod = "0",
	[string]$exclude = "a1b2c3d4e5f6g7h8i9"
)

#version 3.9

$error.clear()
$FailedVM = "vm-0"

# SMTP settings
$SMTPSRV = "127.0.0.1"
$EmailFrom = "relocate@vmware.local"
$EmailTo = "admin@vmware.local"

$css = '<style type="text/css">
		body { background-color:#EEEEEE; }
		body,table,td,th { font-family:"Courier New"; color:Black; Font-Size:10pt }
		th { font-weight:bold; background-color:#CCCCCC; }
		td { background-color:white; }
		</style>'

function Send-SMTPmail($to, $from, $subject, $smtpserver, $body) {
	$mailer = new-object Net.Mail.SMTPclient($smtpserver)
	$msg = new-object Net.Mail.MailMessage($from,$to,$subject,$body)
	$msg.IsBodyHTML = $true
	$mailer.send($msg)
}

function DatastoreFreeSpaceDeviation ($DatastoreList) {
	$DatastoreListView = $DatastoreList|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}}
	$DatastoreListView|%{$_.RefreshDatastore()}
	$DatastoreBigFreePct = (($DatastoreListView|sort {$_.summary.FreeSpace} -Descending|select -First 1).summary.FreeSpace/($DatastoreListView|sort {$_.summary.FreeSpace} -Descending|select -First 1).summary.Capacity)
	$DatastoreSlimFreePct = (($DatastoreListView|sort {$_.summary.FreeSpace}|select -First 1).summary.FreeSpace/($DatastoreListView|sort {$_.summary.FreeSpace}|select -First 1).summary.Capacity)
	Return ($DatastoreBigFreePct-$DatastoreSlimFreePct)
}

function equalize-datastore ($Datastores, $vDiskFormat, $FreeSpaceDeviation, $DatastoreFreeLimit) {
	while ((DatastoreFreeSpaceDeviation $Datastores) -gt ($FreeSpaceDeviation/100)) {
		$DatastoreListView = $Datastores|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}}
		$DatastoresSlimFree = $DatastoreListView|sort {$_.summary.FreeSpace}|select -First 1
		if ($Bypass -eq 0 -and $vi5 -eq 0)
			{$VMToMove = $DatastoresSlimFree|%{$_.vm}|%{get-view $_}|?{$_.name -notmatch $exclude -and $_.moref -notmatch $failedvm}|?{$_.Runtime.ConnectionState -eq "connected"}|?{-not $_.Config.Template}|?{!($_.DisabledMethod|?{$_ -eq "RelocateVM_Task"})}|?{($_.LayoutEx.file|?{$_.type -notmatch "swap"}|%{$_.name.split()[0]}|sort -Unique|Measure-Object).count -eq 1}|?{!$_.Snapshot}|?{($_|%{$_.Config.Hardware.Device}|?{$_.GetType().Name -eq "VirtualDisk"}|%{$_.Backing.CompatibilityMode}|Measure-Object).count -eq 0}|?{($_|%{$_.Config.Hardware.Device}|?{$_ -is [VMware.Vim.VirtualSCSIController]}|?{$_.SharedBus -ne "noSharing"}|Measure-Object).count -eq 0}}
		elseif ($Bypass -eq 0 -and $vi5 -eq 1)
			{$VMToMove = $DatastoresSlimFree|%{$_.vm}|%{get-view $_}|?{$_.name -notmatch $exclude -and $_.moref -notmatch $failedvm}|?{$_.Runtime.ConnectionState -eq "connected"}|?{-not $_.Config.Template}|?{!($_.DisabledMethod|?{$_ -eq "RelocateVM_Task"})}|?{($_.LayoutEx.file|?{$_.type -notmatch "swap"}|%{$_.name.split()[0]}|sort -Unique|Measure-Object).count -eq 1}|?{($_|%{$_.Config.Hardware.Device}|?{$_.GetType().Name -eq "VirtualDisk"}|%{$_.Backing.CompatibilityMode}|Measure-Object).count -eq 0}|?{($_|%{$_.Config.Hardware.Device}|?{$_ -is [VMware.Vim.VirtualSCSIController]}|?{$_.SharedBus -ne "noSharing"}|Measure-Object).count -eq 0}}			
		else
			{$VMToMove = $DatastoresSlimFree|%{$_.vm}|%{get-view $_}|?{$_.name -notmatch $exclude -and $_.moref -notmatch $failedvm}|?{$_.Runtime.ConnectionState -eq "connected"}|?{-not $_.Config.Template}}
		if (!$VMToMove){Write-Host -ForegroundColor Red "no vm to move or incompatible";break}
		if ($vDiskFormat -eq "as-source" -or $vDiskFormat -eq "thin")
			{$VMSlimToMove = ($VMToMove|sort {$_.Summary.storage.Committed})|select -First 1}
		elseif ($vDiskFormat -eq "thick")
			{$VMSlimToMove = ($VMToMove|sort {$_.summary.storage.committed + $_.summary.storage.uncommitted})|select -First 1}
		
		$DatastoreBigFree = ($DatastoreListView|sort {$_.summary.FreeSpace} -Descending)|select -First 1

		if ($Bypass -eq 0) 	{
			if (($vDiskFormat -eq "as-source" -or $vDiskFormat -eq "thin") -and !(($DatastoreBigFree.info.freespace - $VMSlimToMove.Summary.storage.Committed)/$DatastoreBigFree.summary.Capacity -ge (($DatastoreFreeLimit)/100))){Write-Host -ForegroundColor Red "Not enough free space on $($DatastoreBigFree.name)";break}
			if ($vDiskFormat -eq "thick" -and !(($DatastoreBigFree.info.freespace - $VMSlimToMove.Summary.storage.Committed + $VMSlimToMove.Summary.storage.uncommitted)/$DatastoreBigFree.summary.Capacity -ge (($DatastoreFreeLimit)/100))){Write-Host -ForegroundColor Red "Not enough free space on $($DatastoreBigFree.name)";break}
		}
			
		if (($vDiskFormat -eq "as-source" -or $vDiskFormat -eq "thin") -and ($VMSlimToMove.summary.storage.committed -gt ($DatastoreBigFree.summary.FreeSpace - ((get-datastore ($VMSlimToMove.LayoutEx.file|?{$_.type -notmatch "swap"}|%{$_.name.split()[0]}|sort -Unique).split("[]")[1]|get-view -property summary).summary.FreeSpace)))){Write-Host -ForegroundColor Red "No need to move";break}
		if ($vDiskFormat -eq "thick" -and (($VMSlimToMove.summary.storage.committed + $VMSlimToMove.summary.storage.uncommitted) -gt ($DatastoreBigFree.summary.FreeSpace - ((get-datastore ($VMSlimToMove.LayoutEx.file|?{$_.type -notmatch "swap"}|%{$_.name.split()[0]}|sort -Unique).split("[]")[1]|get-view -property summary).summary.FreeSpace)))){Write-Host -ForegroundColor Red "No need to move";break}

		if ($vDiskFormat -eq "as-source")
			{$VMMove = Get-VM $VMSlimToMove.name|Move-VM -Datastore $DatastoreBigFree.name -RunAsync}
		elseif ($vDiskFormat -eq "thin")
			{$VMMove = Get-VM $VMSlimToMove.name|Move-VM -Datastore $DatastoreBigFree.name -DiskStorageFormat thin -RunAsync}
		elseif ($vDiskFormat -eq "thick")
			{$VMMove = Get-VM $VMSlimToMove.name|Move-VM -Datastore $DatastoreBigFree.name -DiskStorageFormat thick -RunAsync}

		if ($Force -eq "0"){Write-Host -ForegroundColor Magenta "Equalize $($VMSlimToMove.name) from $($VMSlimToMove|%{($_.LayoutEx.file|?{$_.type -notmatch "swap"}|%{$_.name.split()[0]}|sort -Unique).split("[]")[1]}) to $($DatastoreBigFree.name) ..."}
		While ((Get-Task|?{$_.id -match $VMMove.id}).state -match "Running") { sleep 15 }
		if (!((Get-Task|?{$_.id -match $VMMove.id}).state -match "Succes")) {
			Write-Host -ForegroundColor Red "$($VMSlimToMove.name) dmotion failed, skipping..."
			$FailedVM = $FailedVM + "|"
			$FailedVM += [string]$VMSlimToMove.moref.value
		}	
	}
	if ($FailedVM.length -eq "4") {return "ok"}
}

function drain-datastore ($SrcDatastores, $DstDatastores, $vDiskFormat, $DatastoreFreeLimit, $excluded) {
	$drainedvms = @()
	while ((($SrcDatastores|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}})|%{$_.vm|?{$_.value -notmatch $FailedVM}}|Measure-Object).count -gt $excluded) {
		$DstDatastoreListView = $DstDatastores|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}}
		$DstDatastoreSlimFree = ($DstDatastoreListView|sort {$_.summary.FreeSpace} )|select -First 1
		$SrcDatastoreListView = $SrcDatastores|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}}
		$SrcDatastoresSlimFree = $SrcDatastoreListView|sort {$_.summary.FreeSpace}
		
		if ($Bypass -eq 0 -and $vi5 -eq 0)
			{$VMToMove = $SrcDatastoresSlimFree|%{$_.vm|?{$_.value -notmatch $FailedVM}}|%{get-view $_}|?{$_.name -notmatch $exclude}|?{-not $_.Config.Template}|?{$_.Runtime.ConnectionState -eq "connected"}|?{!($_.DisabledMethod|?{$_ -eq "RelocateVM_Task"})}|?{($_.LayoutEx.file|?{$_.type -notmatch "swap"}|%{$_.name.split()[0]}|sort -Unique|Measure-Object).count -eq 1}|?{!$_.Snapshot}|?{($_|%{$_.Config.Hardware.Device}|?{$_.GetType().Name -eq "VirtualDisk"}|%{$_.Backing.CompatibilityMode}|Measure-Object).count -eq 0}|?{($_|%{$_.Config.Hardware.Device}|?{$_ -is [VMware.Vim.VirtualSCSIController]}|?{$_.SharedBus -ne "noSharing"}|Measure-Object).count -eq 0}}
		elseif ($Bypass -eq 0 -and $vi5 -eq 1)
			{$VMToMove = $SrcDatastoresSlimFree|%{$_.vm|?{$_.value -notmatch $FailedVM}}|%{get-view $_}|?{$_.name -notmatch $exclude}|?{-not $_.Config.Template}|?{$_.Runtime.ConnectionState -eq "connected"}|?{!($_.DisabledMethod|?{$_ -eq "RelocateVM_Task"})}|?{($_.LayoutEx.file|?{$_.type -notmatch "swap"}|%{$_.name.split()[0]}|sort -Unique|Measure-Object).count -eq 1}|?{($_|%{$_.Config.Hardware.Device}|?{$_.GetType().Name -eq "VirtualDisk"}|%{$_.Backing.CompatibilityMode}|Measure-Object).count -eq 0}|?{($_|%{$_.Config.Hardware.Device}|?{$_ -is [VMware.Vim.VirtualSCSIController]}|?{$_.SharedBus -ne "noSharing"}|Measure-Object).count -eq 0}}			
		else
			{$VMToMove = $SrcDatastoresSlimFree|%{$_.vm|?{$_.value -notmatch $FailedVM}}|%{get-view $_}|?{$_.name -notmatch $exclude}|?{-not $_.Config.Template}|?{$_.Runtime.ConnectionState -eq "connected"}}
		if (!$VMToMove){Write-Host -ForegroundColor Red "no vm to move or incompatible";break}
		
		if ($vDiskFormat -eq "as-source" -or $vDiskFormat -eq "thin")
			{$VMSlimToMove = ($VMToMove|sort {$_.Summary.storage.Committed})|select -First 1}
		elseif ($vDiskFormat -eq "thick")
			{$VMSlimToMove = ($VMToMove|sort {$_.summary.storage.committed + $_.summary.storage.uncommitted})|select -First 1}
				
		$DatastoreBigFree = ($DstDatastoreListView|sort {$_.summary.FreeSpace} -Descending)|select -First 1

		if ($Bypass -eq 0) {
			if (($vDiskFormat -eq "as-source" -or $vDiskFormat -eq "thin") -and !(($DatastoreBigFree.info.freespace - $VMSlimToMove.Summary.storage.Committed)/$DatastoreBigFree.summary.Capacity -ge (($DatastoreFreeLimit)/100))){Write-Host -ForegroundColor Red "Not enough free space on $($DatastoreBigFree.name)";break}
			if ($vDiskFormat -eq "thick" -and !(($DatastoreBigFree.info.freespace - $VMSlimToMove.Summary.storage.Committed + $VMSlimToMove.Summary.storage.uncommitted)/$DatastoreBigFree.summary.Capacity -ge (($DatastoreFreeLimit)/100))){Write-Host -ForegroundColor Red "Not enough free space on $($DatastoreBigFree.name)";break}
		}
			
		if ($vDiskFormat -eq "as-source")
			{$VMMove = Get-VM $VMSlimToMove.name|Move-VM -Datastore $DatastoreBigFree.name -RunAsync}
		elseif ($vDiskFormat -eq "thin")
			{$VMMove = Get-VM $VMSlimToMove.name|Move-VM -Datastore $DatastoreBigFree.name -DiskStorageFormat thin -RunAsync}
		elseif ($vDiskFormat -eq "thick")
			{$VMMove = Get-VM $VMSlimToMove.name|Move-VM -Datastore $DatastoreBigFree.name -DiskStorageFormat thick -RunAsync}

		if ($Force -eq "0"){Write-Host -ForegroundColor Cyan "Drain $($VMSlimToMove.name) from $($VMSlimToMove|%{($_.LayoutEx.file|?{$_.type -notmatch "swap"}|%{$_.name.split()[0]}|sort -Unique).split("[]")[1]}) to $($DatastoreBigFree.name) ..."}
		sleep 5
		While ((Get-Task|?{$_.id -match $VMMove.id}).state -match "Running") { sleep 15 }
		if (!((Get-Task|?{$_.id -match $VMMove.id}).state -match "Succes")) {
			Write-Host -ForegroundColor Red "$($VMSlimToMove.name) dmotion failed, skipping..."
			$FailedVM = $FailedVM + "|"
			$FailedVM += [string]$VMSlimToMove.moref.value
		}
	
		$movedvm = "" | select VMname, CommittedGB, ProvisionedGB, SourceDS, DestinationDS, State, TotalMinutes
		$movedvm.VMname = $VMSlimToMove.name
		$movedvm.CommittedGB = [math]::round($VMSlimToMove.Summary.Storage.Committed/1GB,1)
		$movedvm.ProvisionedGB = [math]::round(($VMSlimToMove.Summary.Storage.Committed + $VMSlimToMove.Summary.Storage.Uncommitted)/1GB,1)
		$movedvm.SourceDS = ($VMSlimToMove|%{($_.LayoutEx.file|?{$_.type -notmatch "swap"}|%{$_.name.split()[0]}|sort -Unique).split("[]")[1]})
		$movedvm.DestinationDS = $DatastoreBigFree.name
		$movedvm.State = (Get-Task|?{$_.id -match $VMMove.id}).state
		$movedvm.TotalMinutes = [math]::round(((Get-Task|?{$_.id -match $VMMove.id}).FinishTime - (Get-Task|?{$_.id -match $VMMove.id}).StartTime).TotalMinutes,0)
		$drainedvms += $movedvm
	}
	if ($vmleft=[string](($SrcDatastores|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"} -property vm})|?{$_.vm}|%{Get-view $_.vm -property name}|sort name).name)
		{Write-Host -ForegroundColor Yellow "VM left on datastore(s) $vmleft"}
	return ,$drainedvms
}

function bargraph ($used, $total){
	$used = (($used*100)/$total)/2
	$total = 50

	$ref = 0
	$bar = "["
	while ($ref -lt $used){
		$bar += "+"
		$ref++
	}
	while ($ref -lt $total){
		$bar += "-"
		$ref++
	}
	$bar = $bar + "]"
	Return $bar
}

if (!$global:DefaultVIServers){Write-Host -ForegroundColor Red "Not connected to vcenter!";return} #check vcenter connection
if ($global:DefaultVIServers.count -ne "1"){Write-Host -ForegroundColor Red "Multiple vcenter connections not supported.";brreturneak} #check DefaultVIServerMode
if (!$SrcDatastores -or !$DstDatastores) {Write-Host -ForegroundColor Red "Src or Dst Datastores missing";return} #check args
	
if ($StoragePod -eq "1") {
	if (!($Pod = get-view -ViewType "StoragePod" -Filter @{"Name" = "^$SrcDatastores$"} -ErrorAction SilentlyContinue)) {
		Write-Host -ForegroundColor Red "Src StoragePod $SrcDatastores is not valid"
		return
	} else {
		$DstDatastores = $SrcDatastores = $Pod.ChildEntity|%{(get-view $_ -property name).name}
	}
}

foreach ($SrcDatastore in $SrcDatastores) {
	if (!(get-view -ViewType "datastore" -Filter @{"Name" = "^$SrcDatastore$"} -ErrorAction SilentlyContinue)) {
		Write-Host -ForegroundColor Red "Src Datastore $SrcDatastore is not valid"
		return
	}
}
	
foreach ($DstDatastore in $DstDatastores) {
	if (!(get-view -ViewType "datastore" -Filter @{"Name" = "^$DstDatastore$"} -ErrorAction SilentlyContinue)) {
		Write-Host -ForegroundColor Red "Dst Datastore $DstDatastore is not valid"
		return
	}
	if ((get-view -ViewType "datastore" -Filter @{"Name" = "^$DstDatastore$"} -ErrorAction SilentlyContinue).Summary.MaintenanceMode -eq "inMaintenance") {
		Write-Host -ForegroundColor Red "Dst Datastore $DstDatastore is in maintenance mode"
		return
	}
}

if ($mailcheck -eq 0) {
	if ($Force -ne "1") {
		Write-Host " "
		if ($bypass -eq "0" -and $vi5 -eq "0") {
			Write-Host -ForegroundColor yellow "VM with snapshots or RDM or multiple datastores or bus-sharing engaged SCSI controller will be skipped"
		} elseif ($bypass -eq "0" -and $vi5 -eq "1") {
			Write-Host -ForegroundColor yellow "VM with RDM or multiple datastores or bus-sharing engaged SCSI controller will be skipped"
		} else {
			Write-Host -ForegroundColor yellow -BackGroundColor WHITE "VMs and Datastores are NOT checked, error loop may occurs!!!"
		}
		Write-Host " "
		$SrcDatastores+$DstDatastores|sort -Unique|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}}|%{$_.RefreshDatastore()}
		($SrcDatastores+$DstDatastores|sort -Unique|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}})|%{Write-Host "$($_.name) " -ForegroundColor white -NoNewline;bargraph ($_.summary.Capacity - $_.summary.FreeSpace) $_.summary.Capacity}
		Write-Host " "
		While ($Quizz -cne "YES" -and $Quizz -cne "NO") {
			$Quizz = (Read-Host "Go ? [YES/NO]")
		}                                                                                                          
		if ($Quizz -ceq "NO") {
			Write-Host -ForegroundColor Yellow "Bye"
			break
		}
		Write-Host ""
	}
	$BeginTime = get-date
	if ((compare-object $SrcDatastores $DstDatastores|Measure-Object).count -eq 0) {
		$equalize_task = equalize-datastore $DstDatastores $vDiskFormat $FreeSpaceDeviation $DatastoreFreeLimit
		if ($equalize_task -ne "ok" -and $Force -eq "0" -and $bypass -eq "0") {
			Write-Host "";Write-Host -ForegroundColor Red "Equalize Failed"
		} else {
			Write-Host "";Write-Host -ForegroundColor Magenta "Datastores Equalized!"
		}
	} elseif ((compare-object $SrcDatastores $DstDatastores|Measure-Object).count -gt 0) {
		$DrainSrcDatastores = compare-object $SrcDatastores $DstDatastores|?{$_.SideIndicator -eq "<="}|%{$_.InputObject}
		$excluded = ($SrcDatastores|sort -Unique|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"} -Property VM}|%{$_.VM}|%{Get-View $_ -property Name}|?{$_.name -match $exclude}|select name  -Unique|measure-object).count
		$drain_task = drain-datastore $DrainSrcDatastores $DstDatastores $vDiskFormat $DatastoreFreeLimit $excluded 
		if (!$drain_task -and $Force -eq "0" -and $bypass -eq "0") {
			Write-Host "";Write-Host -ForegroundColor Red "Drain Failed"
		} else {
			Write-Host "";Write-Host -ForegroundColor Cyan "Datastore(s) Drained!"
		}
		if (($DstDatastores|Measure-Object).count -gt 1) {
			$equalize_task = equalize-datastore $DstDatastores $vDiskFormat $FreeSpaceDeviation $DatastoreFreeLimit
			if ($equalize_task -ne "ok" -and $Force -eq "0" -and $bypass -eq "0") {
				Write-Host "";Write-Host -ForegroundColor Red "equalize failed"
			} else {
				Write-Host "";Write-Host -ForegroundColor Magenta "Datastores Equalized!"
			}
		}
	}
	
	$EndTime = get-date

	if ($Force -eq "0") {
		Write-Host "";($SrcDatastores+$DstDatastores|sort -Unique|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}})|%{Write-Host "$($_.name) " -ForegroundColor white -NoNewline
		bargraph ($_.summary.Capacity - $_.summary.FreeSpace) $_.summary.Capacity}
		Write-Host ""
		Write-Host "Migration Time: " $([math]::round(($EndTime - $BeginTime).TotalMinutes,0)) "min"
		Write-Host ""
	}
} elseif ($mailcheck -eq 1) {
	$SrcDatastores+$DstDatastores|sort -Unique|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}}|%{$_.RefreshDatastore()}
	if (($DatastoresDeviation = DatastoreFreeSpaceDeviation $DstDatastores) -gt ($FreeSpaceDeviation/100)) {
		$DatastoresDeviationPct = [math]::round($DatastoresDeviation * 100,1)
		$DatastoreMonitor = ($SrcDatastores+$DstDatastores|sort -Unique|%{get-view -ViewType "datastore" -Filter @{"Name" = "^$_$"}})|select name, @{n="Size GB";e={$_.summary.Capacity/1GB}}, @{n="Space";e={(bargraph ($_.summary.Capacity - $_.summary.FreeSpace) $_.summary.Capacity)}}
		if ($clustername) {
			Send-SMTPmail $EmailTo $EmailFrom "[VMware] $clustername Datastores Deviation Check ($DatastoresDeviationPct%)" $SMTPSRV $($DatastoreMonitor|ConvertTo-Html -head $css -Title "$clustername Datastores Equalizer Check")
		} elseif ($StoragePod) {
			Send-SMTPmail $EmailTo $EmailFrom "[VMware] $($Pod.name) Pod Deviation Check ($DatastoresDeviationPct%)" $SMTPSRV $($DatastoreMonitor|ConvertTo-Html -head $css -Title "$($Pod.name) Pod Equalizer Check")
		}
	}
}
	
if ($drainreport -eq 1) {
	Send-SMTPmail $EmailTo $EmailFrom "Moved VM from $SrcDatastores to $DstDatastores in $([math]::round(($EndTime - $BeginTime).TotalMinutes,0)) min" $SMTPSRV $($drain_task|ConvertTo-Html -head $css -Title "Datastore-Equalizer Report")
}
