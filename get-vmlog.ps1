param([string] $vmtarget,$delay="5")
if (!$vmtarget){Write-Host -ForegroundColor Red "no vm input";break} # check vm name

# touch/clear temp logs
set-content -Path "$env:temp\$vmtarget.log" -Value ([String]::Empty) -Force -Confirm:$false
set-content -Path "$env:temp\$vmtarget-full.log" -Value ([String]::Empty) -Force -Confirm:$false

$vmitem = get-vm $vmtarget -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue
if ($Error[0].Exception -match "VM with name '$vmtarget' was not found" ){Write-Host -ForegroundColor Red "vm name error";break} # check vm exists
$vmexitem = $vmitem|get-view -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue

# retreive file path info
$vmtargetdc = ($vmitem|get-datacenter).name
$vmlogds = ($vmexitem.LayoutEx.file|?{$_.name -match "vmware.log"}).name.split("[]")[1]
$vmlogpath = (($vmexitem.LayoutEx.file|?{$_.name -match "vmware.log"}).name.split()[1]).replace("/","\")
$rds = Remove-PSDrive vids -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue
$psd = New-PSDrive -Location (get-datastore $vmlogds) -Name vids -PSProvider VimDatastore -Root '\' -Confirm:$false


for (;;)
	{
	$oldlog = Get-Content "$env:temp\$vmtarget.log" -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue
	$logdump = Copy-DatastoreItem "vids:\$vmlogpath" "$env:temp\$vmtarget.log" -force -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue
	
	# download retry loop : when vmotion or svmotion, the vmware.log file is locked or is moved
	while ($Error[0].Exception -match "Download" -and $Error[0].Exception -match "failed" -and $logdump -eq $null)
		{
		$vmitem = get-vm $vmtarget -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue
		$vmexitem = $vmitem|get-view -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue
		$vmtargetdc = ($vmitem|get-datacenter).name
		$vmlogds = ($vmexitem.LayoutEx.file|?{$_.name -match "vmware.log"}).name.split("[]")[1]
		$vmlogpath = (($vmexitem.LayoutEx.file|?{$_.name -match "vmware.log"}).name.split()[1]).replace("/","\")
		$rds = Remove-PSDrive vids -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue
		$psd = New-PSDrive -Location (get-datastore $vmlogds) -Name vids -PSProvider VimDatastore -Root '\' -Confirm:$false
		$error.clear()
		$logdump = Copy-DatastoreItem "vids:\$vmlogpath" "$env:temp\$vmtarget.log" -force -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue
		sleep $delay
		}
	$newlog = Get-Content "$env:temp\$vmtarget.log"
	
	if ($oldlog -ne $null -and $newlog -ne $null)
		{
		$changelog = Compare-Object $oldlog $newlog -WarningAction:SilentlyContinue -ErrorAction:SilentlyContinue|?{$_.SideIndicator -match "=>"}

			foreach ($line in $changelog)
				{
				$line.InputObject | Out-File "$env:temp\$vmtarget-full.log" -Append -Confirm:$false -Force -Encoding ASCII
				if (($line.InputObject|Measure-Object).count -eq "0")
					{break}
				elseif ($line.InputObject -cmatch "failed|error")
					{Write-Host $line.InputObject -ForegroundColor Red}						
				elseif ($line.InputObject -cmatch "mks")
					{Write-Host $line.InputObject -ForegroundColor Blue}				
				elseif ($line.InputObject -cmatch "DISKLIB-")
					{Write-Host $line.InputObject -ForegroundColor Magenta}
				elseif ($line.InputObject -cmatch "vcpu-0")
					{Write-Host $line.InputObject -ForegroundColor Yellow}
				elseif ($line.InputObject -cmatch "vcpu-")
					{Write-Host $line.InputObject -ForegroundColor Cyan}				
				elseif ($line.InputObject -cmatch "vmx")
					{Write-Host $line.InputObject -ForegroundColor Green}
				else	
					{Write-Host $line.InputObject -ForegroundColor Gray}
	
				}
		}

	sleep $delay

	}