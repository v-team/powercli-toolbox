function Get-Load {
<#
.SYNOPSIS
  Get load average for multiple object
.DESCRIPTION
  The function will display average load for vSphere object passed through pipeline.
.NOTES  
  Author:  www.vmdude.fr
.PARAMETER LoadType
  Specify wich load to display when cmdlet run on standalone
  Valid LoadType are 'VirtualMachine', 'HostSystem', 'ClustercomputeResource'
.PARAMETER Quickstat
  Switch, when true the method to get stats is based
  on quickstats through summary child properties.
  If not, the method will use PerfManager instance
  with QueryPerf method in order to get non computed stats.
  The default for this switch is $true.
.EXAMPLE
  PS> Get-Load -LoadType ClusterComputeResource
  PS> Get-Cluster | Get-Load
  Get a graphical list for all cluster load
.EXAMPLE
  PS> Get-VMHost ESX01, ESX02 | Get-Load
  Get a graphical list for host load for ESX01 and 02
.EXAMPLE
  PS> Get-VM "vmtest*" | Get-Load
  Get a graphical load list for all VM with name started with vmtest
#>

	[CmdletBinding(DefaultParameterSetName='GetViewByVIObject')]
	param(
		[Parameter(ParameterSetName='GetViewByVIObject', Position=0, ValueFromPipeline=$true)]
		[ValidateNotNullOrEmpty()]
		[VMware.VimAutomation.Sdk.Types.V1.VIObject[]]
		${VIObject},
		[Parameter(ParameterSetName='GetEntity', Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]
		${LoadType},
		[parameter(Mandatory = $false)]
		[switch]$Quickstat = $true
	)
	
	begin{
		function Show-PercentageGraph([int]$percent, [int]$maxSize=20) {
			if ($percent -gt 100) { $percent = 100 }
			$warningThreshold = 60 # percent
			$alertThreshold = 80 # percent
			[string]$g = [char]9632 #this is the graph character, use [char]9608 for full square character
			if ($percent -lt 10) { write-host -nonewline "0$percent [ " } else { write-host -nonewline "$percent [ " }
			for ($i=1; $i -le ($barValue = ([math]::floor($percent * $maxSize / 100)));$i++) {
				if ($i -le ($warningThreshold * $maxSize / 100)) { write-host -nonewline -foregroundcolor darkgreen $g }
				elseif ($i -le ($alertThreshold * $maxSize / 100)) { write-host -nonewline -foregroundcolor yellow $g }
				else { write-host -nonewline -foregroundcolor red $g }
			}
			for ($i=1; $i -le ($traitValue = $maxSize - $barValue);$i++) { write-host -nonewline "-" }
			write-host -nonewline " ]"
		}
		
		function Show-GetLoadUsage() {
			Write-Host -Foreground Yellow "Standalone usage for this cmdlet : Get-Load -LoadType <LoadType>"`n
			Write-Host -Foreground Yellow "Valid LoadType are:"
			Write-Host -Foreground Yellow "'VirtualMachine' for virtual machine"
			Write-Host -Foreground Yellow "'HostSystem' for ESXi hosts"
			Write-Host -Foreground Yellow "'ClustercomputeResource' for vSphere cluster"
		}
		
		function VM-Load([VMware.VimAutomation.Sdk.Types.V1.VIObject]$VMName) {
			$VM = Get-View $VMName -Property summary,name
			if ($Quickstat) {
				if ($VM.name.length -gt 20) { write-host -nonewline $VM.name.substring(0, 22 -5) "... CPU:" } else { write-host -nonewline $VM.name (" "*(20-$VM.name.length)) "CPU:"	}
				# using QuickStat for getting "realtime"-ish stats
				if ($VM.summary.quickStats.overallCpuUsage -ne $null -And $VM.summary.quickStats.guestMemoryUsage -ne $null -And $VM.summary.runtime.powerState -eq "poweredOn") {
					Show-PercentageGraph([math]::floor(($VM.summary.quickStats.overallCpuUsage*100)/($VM.summary.config.numCpu * $VM.summary.runtime.maxCpuUsage)))
					write-host -nonewline `t"MEM:"
					Show-PercentageGraph([math]::floor(($VM.summary.quickStats.guestMemoryUsage*100)/($VM.summary.config.memorySizeMB)))
				} else {
					Show-PercentageGraph(0)
					write-host -nonewline `t"MEM:"
					Show-PercentageGraph(0)
				}
				write-host ""
			} else { 
				# using PerfManager instance in order to bypass Get-Stat cmdlet for speed
				# but this method is quite low to get stats
				if ($VM.name.length -gt 20) { write-host -nonewline $VM.name.substring(0, 22 -5) "... CPU:" } else { write-host -nonewline $VM.name (" "*(20-$VM.name.length)) "CPU:"	}
				Show-PercentageGraph([math]::floor((($objPerfManager.QueryPerf((New-Object VMware.Vim.PerfQuerySpec -property @{entity = $VM.moref;format = "normal";IntervalId = "300";StartTime=((Get-Date).AddDays(-1));EndTime=(Get-Date);MetricId = (New-Object VMware.Vim.PerfMetricId -property @{instance = "";counterId = $avgUsageCpuCounter})})) |%{$_.value}|%{$_.value}|measure -Average).average/100)))
				write-host -nonewline `t"MEM:"
				Show-PercentageGraph([math]::floor((($objPerfManager.QueryPerf((New-Object VMware.Vim.PerfQuerySpec -property @{entity = $VM.moref;format = "normal";IntervalId = "300";StartTime=((Get-Date).AddDays(-1));EndTime=(Get-Date);MetricId = (New-Object VMware.Vim.PerfMetricId -property @{instance = "";counterId = $avgConsumedMemCounter})})) |%{$_.value}|%{$_.value}|measure -Average).average/100)))
				write-host ""
			}
		}
		
		function VMHost-Load([VMware.VimAutomation.Sdk.Types.V1.VIObject]$VMHostName) {
			$VMHost = Get-View $VMHostName -Property summary,name
			if ($Quickstat) {
				if ($VMHost.name.length -gt 20) { write-host -nonewline $VMHost.name.substring(0, 22 -5) "... CPU:" } else { write-host -nonewline $VMHost.name (" "*(20-$VMHost.name.length)) "CPU:"	}
				# using QuickStat for getting "realtime"-ish stats
				if ($VMHost.summary.quickStats.overallCpuUsage -ne $null -And $VMHost.summary.quickStats.overallMemoryUsage -ne $null -And $VMHost.summary.runtime.powerState -eq "poweredOn") {
					Show-PercentageGraph([math]::floor(($VMHost.summary.quickStats.overallCpuUsage*100)/($VMHost.summary.hardware.numCpuCores * $VMHost.summary.hardware.cpuMhz)))
					write-host -nonewline `t"MEM:"
					Show-PercentageGraph([math]::floor(($VMHost.summary.quickStats.overallMemoryUsage*1024*1024*100)/($VMHost.summary.hardware.memorySize)))
				} else {
					Show-PercentageGraph(0)
					write-host -nonewline `t"MEM:"
					Show-PercentageGraph(0)
				}
				write-host ""
			} else { 
				# using PerfManager instance in order to bypass Get-Stat cmdlet for speed
				# but this method is quite low to get stats
				if ($VMHost.name.length -gt 20) { write-host -nonewline $VMHost.name.substring(0, 22 -5) "... CPU:" } else { write-host -nonewline $VMHost.name (" "*(20-$VMHost.name.length)) "CPU:"	}
				Show-PercentageGraph([math]::floor((($objPerfManager.QueryPerf((New-Object VMware.Vim.PerfQuerySpec -property @{entity = $VMHost.moref;format = "normal";IntervalId = "300";StartTime=((Get-Date).AddDays(-1));EndTime=(Get-Date);MetricId = (New-Object VMware.Vim.PerfMetricId -property @{instance = "";counterId = $avgUsageCpuCounter})})) |%{$_.value}|%{$_.value}|measure -Average).average/100)))
				write-host -nonewline `t"MEM:"
				Show-PercentageGraph([math]::floor((($objPerfManager.QueryPerf((New-Object VMware.Vim.PerfQuerySpec -property @{entity = $VMHost.moref;format = "normal";IntervalId = "300";StartTime=((Get-Date).AddDays(-1));EndTime=(Get-Date);MetricId = (New-Object VMware.Vim.PerfMetricId -property @{instance = "";counterId = $avgConsumedMemCounter})})) |%{$_.value}|%{$_.value}|measure -Average).average/100)))
				write-host ""
			}
		}
		
		function Cluster-Load([VMware.VimAutomation.Sdk.Types.V1.VIObject]$ClusterName) {
			$cluster = Get-View $ClusterName -Property resourcePool,name
			if ($Quickstat) {
				if ($cluster.name.length -gt 20) { write-host -nonewline $cluster.name.substring(0, 2 -5) "... CPU:" } else { write-host -nonewline $cluster.name (" "*(20-$cluster.name.length)) "CPU:"	}
				# using QuickStat for getting "realtime"-ish stats
				$rootResourcePool = get-view $cluster.resourcePool -Property summary
				if ($rootResourcePool.summary.runtime.cpu.maxUsage -ne 0 -And $rootResourcePool.summary.runtime.memory.maxUsage -ne 0) {
					Show-PercentageGraph([math]::floor(($rootResourcePool.summary.runtime.cpu.overallUsage*100)/($rootResourcePool.summary.runtime.cpu.maxUsage)))
					write-host -nonewline `t"MEM:"
					Show-PercentageGraph([math]::floor(($rootResourcePool.summary.runtime.memory.overallUsage*100)/($rootResourcePool.summary.runtime.memory.maxUsage)))
				} else {
					Show-PercentageGraph(0)
					write-host -nonewline `t"MEM:"
					Show-PercentageGraph(0)
				}
				write-host ""
			} else {
				# using PerfManager instance in order to bypass Get-Stat cmdlet for speed
				# but this method is quite low to get stats
				if ($cluster.name.length -gt 20) { write-host -nonewline $cluster.name.substring(0, 22 -5) "... CPU:" } else { write-host -nonewline $cluster.name (" "*(20-$cluster.name.length)) "CPU:"	}
				Show-PercentageGraph([math]::floor((($objPerfManager.QueryPerf((New-Object VMware.Vim.PerfQuerySpec -property @{entity = $cluster.moref;format = "normal";IntervalId = "300";StartTime=((Get-Date).AddDays(-1));EndTime=(Get-Date);MetricId = (New-Object VMware.Vim.PerfMetricId -property @{instance = "";counterId = $avgUsageCpuCounter})})) |%{$_.value}|%{$_.value}|measure -Average).average/100)))
				write-host -nonewline `t"MEM:"
				Show-PercentageGraph([math]::floor((($objPerfManager.QueryPerf((New-Object VMware.Vim.PerfQuerySpec -property @{entity = $cluster.moref;format = "normal";IntervalId = "300";StartTime=((Get-Date).AddDays(-1));EndTime=(Get-Date);MetricId = (New-Object VMware.Vim.PerfMetricId -property @{instance = "";counterId = $avgConsumedMemCounter})})) |%{$_.value}|%{$_.value}|measure -Average).average/100)))
				write-host ""
			}
		}
		
		$objPerfManager = Get-View (Get-View ServiceInstance -Property content).content.PerfManager
		$avgConsumedMemCounter = ($objPerfManager.PerfCounter | ?{ $_.groupinfo.key -match "mem" } | ?{ $_.nameinfo.key -match "usage$" } | ?{ $_.RollupType -match "average" -And $_.Level -eq 1}).key
		$avgUsageCpuCounter = ($objPerfManager.PerfCounter | ?{ $_.groupinfo.key -match "cpu" } | ?{ $_.nameinfo.key -match "usage$" } | ?{ $_.RollupType -match "average" -And $_.Level -eq 1 }).key
	}

	process{
		# Test if function is used through a pipeline or as a regular cmdlet
		if ($VIObject) {
			# get all objects passed by pipeline or specified in command
			foreach ($objVI in $VIObject) {
				# Differents load method regarding VIobject type
				switch ($objVI.gettype()) {
					"VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl" { VM-Load($objVI) }
					"VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl" { VMHost-Load($objVI) }
					"VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl" { Cluster-Load($objVI) }
					default { Write-Error -Message ("Unknown type " + $objVI.gettype() + " for object " + $objVI.name) }
				}
			}
		} else {
			switch ($LoadType) {
				"VirtualMachine" { Get-VM | %{ VM-Load($_) } }
				"HostSystem" { Get-VMHost | %{ VMHost-Load($_) } }
				"ClustercomputeResource" { Get-Cluster | %{ Cluster-Load($_) } }
				default { Show-GetLoadUsage }
			}
		}
	}
}