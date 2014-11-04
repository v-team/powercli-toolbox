<# 
.SYNOPSIS 
    This script will display map for CPU, MEM or disk resources
.DESCRIPTION 
    This script will display ASCII ART map for CPU, MEM or disk resources in order to get basic inventory stats
.NOTES 
    Author     : Frederic Martin - www.vmdude.fr
.LINK 
    http://www.vmdude.fr
.PARAMETER CPU 
   Switch in order to retrieve CPU resource map
.PARAMETER MEM 
   Switch in order to retrieve MEM resource map
.PARAMETER Disk 
   Switch in order to retrieve Disk resource map
.PARAMETER ExportData 
   Switch will export data in csv file(s)
.EXAMPLE 
	C:\foo> .\Get-ResourceMap.ps1 -CPU
	
	Description
	-----------
	Display CPU resource map
.EXAMPLE 
	C:\foo> .\Get-ResourceMap.ps1 -MEM
	
	Description
	-----------
	Display memory resource map
.EXAMPLE 
	C:\foo> .\Get-ResourceMap.ps1 -Disk
	
	Description
	-----------
	Display disk resource map
.EXAMPLE 
	C:\foo> .\Get-ResourceMap.ps1 -CPU -MEM
	
	Description
	-----------
	Display CPU and memory resource map
.EXAMPLE 
	C:\foo> .\Get-ResourceMap.ps1 -CPU -MEM -ExportData
	
	Description
	-----------
	Export CPU and memory resource map in CSV files
#> 

PARAM(
	[switch]$CPU,
	[switch]$MEM,
	[switch]$Disk,
	[switch]$ExportData
)

# If no switch CPU/MEM/Disk is put, we get all of configuration catalog
$Full = $false
if (-Not ($CPU -Or $MEM -Or $Disk)) { $Full = $true }

# Retrieving data from vSphere managed objects
$vmView = Get-View -Viewtype VirtualMachine -Property config.hardware.NumCPU,config.hardware.MemoryMB,config.hardware.Device

# This function will be used to diplay fancy ASCII ART bar
function Show-PercentageGraph([int]$percent, [int]$maxSize=20) {
	if ($percent -gt 100) { $percent = 100 }
	if ($percent -eq 100) { write-host -nonewline "$percent% [ " } elseif ($percent -ge 10) { write-host -nonewline " $percent% [ " } else { write-host -nonewline "  $percent% [ " }
	for ($i=1; $i -le ($barValue = ([math]::floor($percent * $maxSize / 100)));$i++) {
		if ($i -le (60 * $maxSize / 100)) { write-host -nonewline -foregroundcolor darkgreen ([char]9632) }
		elseif ($i -le (80 * $maxSize / 100)) { write-host -nonewline -foregroundcolor yellow ([char]9632) }
		else { write-host -nonewline -foregroundcolor red ([char]9632) }
	}
	for ($i=1; $i -le ($traitValue = $maxSize - $barValue);$i++) { write-host -nonewline "-" }
	write-host -nonewline " ]"
}

# Creating SortedDictionnary objects in order to use sorted collection
$cpuMap = New-Object 'System.Collections.Generic.SortedDictionary[int,int]'
$memMap = New-Object 'System.Collections.Generic.SortedDictionary[int,int]'
$diskMap = New-Object 'System.Collections.Generic.SortedDictionary[int,int]'

# Retrieving configuration catalog
foreach ($vm in $vmView) {
	if ($CPU -Or $Full) {
		$nbCPU = $vm.config.hardware.NumCPU
		$cpuMap[$nbCPU] += 1
	}
	
	if ($MEM -Or $Full) {
		$nbMEM = $vm.config.hardware.MemoryMB
		$memMap[$nbMEM] += 1
	}
	
	if ($Disk -Or -$Full) {
		$sizeDisk = [int][Math]::Round(($vm.config.hardware.Device | ?{$_ -is [VMware.Vim.VirtualDisk]} | Measure-Object -Property CapacityInKB -Sum).Sum/1024/1024,0)
		$diskMap[$sizeDisk] += 1
	}
}

# Displaying CPU infos
if ($CPU -Or $Full) {
	$maxCPU = ($cpuMap.GetEnumerator() | Sort -Desc Value | Select -First 1).Value
	foreach ($cpuValue in $cpuMap.GetEnumerator()) {
		Write-Host -NoNewLine $cpuValue.Key "vCPU"
		Write-Host -NoNewLine -ForegroundColor DarkYellow (" "*(3-($cpuValue.Key).ToString().length)) "["$cpuValue.Value"]" (" "*(7-($cpuValue.Value).ToString().length))
		Show-PercentageGraph ($cpuValue.Value*100/$maxCPU) 50
		Write-Host ""
	}
	Write-Host ""
	if ($ExportData) { $cpuMap.GetEnumerator() | Export-Csv -NoTypeInformation -Delimiter ";" -Path ".\CPU_ConfigurationCatalog.csv" }
}

# Displaying MEM infos
if ($MEM -Or $Full) {
	$maxMem = ($memMap.GetEnumerator() | Sort -Desc Value | Select -First 1).Value
	foreach ($memValue in $memMap.GetEnumerator()) {
		Write-Host -NoNewLine $memValue.Key "MB"
		Write-Host -NoNewLine -ForegroundColor DarkYellow (" "*(7-($memValue.Key).ToString().length)) "["$memValue.Value"]" (" "*(8-($memValue.Value).ToString().length))
		Show-PercentageGraph ($memValue.Value*100/$maxMem) 50
		Write-Host ""
	}
	Write-Host ""
	if ($ExportData) { $memMap.GetEnumerator() | Export-Csv -NoTypeInformation -Delimiter ";" -Path ".\Memory_ConfigurationCatalog.csv" }
}

# Displaying disk size infos
if ($Disk -Or -$Full) {
	$maxDisk = ($diskMap.GetEnumerator() | Sort -Desc Value | Select -First 1).Value
	foreach ($diskValue in $diskMap.GetEnumerator()) {
		Write-Host -NoNewLine $diskValue.Key "GB"
		Write-Host -NoNewLine -ForegroundColor DarkYellow (" "*(6-($diskValue.Key).ToString().length)) "["$diskValue.Value"]" (" "*(7-($diskValue.Value).ToString().length))
		Show-PercentageGraph ($diskValue.Value*100/$maxDisk) 50
		Write-Host ""
	}
	Write-Host ""
	if ($ExportData) { $diskMap.GetEnumerator() | Export-Csv -NoTypeInformation -Delimiter ";" -Path ".\DiskSize_ConfigurationCatalog.csv" }
}