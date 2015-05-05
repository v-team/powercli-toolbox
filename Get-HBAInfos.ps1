# 23.05.2012 vmdude.fr

######################
# EMULEX export sample
######################
# ~ # head -9 /proc/scsi/lpfc820/7
# Emulex LightPulse Fibre Channel SCSI driver 8.2.1.30.1-58vmw
# IBM 42C2071 4Gb 2-Port PCIe FC HBA for System x on PCI bus 0000:1e device 00 irq 200 port 0
# BoardNum: 0
# Firmware Version: 2.82A3 (Z3F2.82A3)
# Portname: XXX   Nodename: XXX
# 
# SLI Rev: 3
#    NPIV Unsupported by Fabric
#    RPIs max 512  RPIs used 1
##########################
# ~ # /usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -a
# Emulex LightPulse FC SCSI 10.2.455.0
# IBM Flex System FC5054 95Y2393 4-port 16Gb FC Adapter on PCI bus 0000:20 device 00 fn 1 port 3 Logical Link Speed: 16000 Mbps
#
# BoardNum: 3
# FW Version: 10.2.470.14
# HW Version: 0000000b
# ROM Version: 10.2.470.14
# SerialNum: ******************************************
# Vendor Id: e20010df
#
# Emulex LightPulse FC SCSI 10.2.455.0
# IBM Flex System FC5054 95Y2393 4-port 16Gb FC Adapter on PCI bus 0000:20 device 00 fn 0 port 2 Logical Link Speed: 16000 Mbps
#
# BoardNum: 2
# FW Version: 10.2.470.14
# HW Version: 0000000b
# ROM Version: 10.2.470.14
# SerialNum: *****************************************
# Vendor Id: e20010df
##########################
# end EMULEX export sample
##########################

######################
# QLOGIC export sample
######################
# ~ # head -8 /proc/scsi/qla2xxx/9
# QLogic PCI to Fibre Channel Host Adapter for QLE2460:
#        FC Firmware version 5.02.00 (496), Driver version 831.k
#
# Host Device Name vmhba5
#
# BIOS version 1.28
# FCODE version 1.24
# EFI version 1.08
##########################
# end QLOGIC export sample
##########################


PARAM (
	[Parameter(HelpMessage="Default path for plink executable file ('plink.exe').", Mandatory=$true)][string] $PlinkPath,
	[Parameter(HelpMessage="ESXi account used for SSH connection/command.", Mandatory=$true)][string] $Username,
	[Parameter(HelpMessage="ESXi account's password.", Mandatory=$true)][string] $Password,
	[Parameter(HelpMessage="Path for csv export file.", Mandatory=$false)][string] $CSVPath
)

$report = @()
$hostsview = Get-View -ViewType HostSystem -Property ("runtime", "name", "config", "hardware", "ConfigManager")
$progressCount = 1
foreach ($esx in $hostsview | ?{$_.runtime.PowerState -match "poweredOn"} | Sort Name) {
	# Trick for the 'The server's host key is not cached in the registry' error
	$tmpStr = [string]::Format('echo y | & "{0}" {1} "{2}"', $PlinkPath, "-ssh " + $Username + "@" + $esx.Name + " -pw $Password" , "exit")
	Invoke-Expression $tmpStr | Out-Null
	Write-Progress -Id 1 -Activity "Getting ESX HBA information" -Status ("[$progressCount/"+($hostsview | ?{$_.runtime.PowerState -match "poweredOn"}).count+"] "+$esx.Name) -PercentComplete (($progressCount*100)/(($hostsview | ?{$_.runtime.PowerState -match "poweredOn"}).count))
	if (-Not (get-view $esx.ConfigManager.ServiceSystem).ServiceInfo|%{$_.service|?{$_.Key -eq "TSM-SSH"}}.running) {
		(get-view $esx.ConfigManager.ServiceSystem).StartService("TSM-SSH")
	}
	foreach ($hba in $esx.Config.StorageDevice.HostBusAdapter | ?{$_.GetType().Name -eq "HostFibreChannelHba"}) {
		$line = "" | Select HostName,HostProduct,HbaDevice,HbaWWN,HbaDriver,HbaModel,HbaFirmwareVersion,HbaDriverVersion,HWModel
		$line.HostName = $esx.name
		$line.HostProduct = $esx.config.product.fullName
		$line.HbaDevice = $hba.device
		$line.HbaWWN = ([regex]::matches("{0:x}" -f $hba.PortWorldWideName, '.{2}') | %{$_.value}) -join ':'
		$line.HbaDriver = $hba.driver
		$line.HbaModel = $hba.model
		# Managing ESXi 5.5 native drivers
		if ($esx.Config.Product.Version -ge "5.5") {
			if ($hba.driver -match "lpfc") {
				$remoteCommand = "/usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -a | grep -A13 " + $hba.device + "| grep -i 'FW Version' | sed 's/FW Version:.* \(.*\)/\1/'"
			} elseif ($hba.driver -match "qla|qlnativefc") {
				$remoteCommand = "/usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -a | grep -B2 " + $hba.device + "| grep -i 'firmware version' | sed 's/.*Firmware version \(.*\), Driver version.*/\1/'"
			}
			$tmpStr = [string]::Format('& "{0}" {1} "{2}"', $PlinkPath, "-ssh " + $Username + "@" + $esx.Name + " -pw $Password" , $remoteCommand + ";exit")
			$line.HbaFirmwareVersion = Invoke-Expression $tmpStr
			if ($hba.driver -match "lpfc") {
				$remoteCommand = "/usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -a | grep -A9 " + $hba.device + "| grep -i 'emulex lightpulse FC SCSI' | sed 's/Emulex LightPulse FC SCSI \(.*\)/\1/'"
			} elseif ($hba.driver -match "qla|qlnativefc") {
				$remoteCommand = "/usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -a | grep -B2 " + $hba.device + "| grep -i 'firmware version' | sed 's/.*Firmware version .*, Driver version \(.*\)/\1/'"
			}
			$tmpStr = [string]::Format('& "{0}" {1} "{2}"', $PlinkPath, "-ssh " + $Username + "@" + $esx.Name + " -pw $Password" , $remoteCommand + ";exit")
			$line.HbaDriverVersion = Invoke-Expression $tmpStr
		} else {
			if ($hba.driver -match "lpfc") {
				$remoteCommand = "head -9 /proc/scsi/lpfc*/* | grep -B1 " + $line.HbaWWN + " | grep -i 'firmware version' | sed 's/Firmware Version:\{0,1\} \(.*\)/\1/'"
			} elseif ($hba.driver -match "qla") {
				$remoteCommand = "head -8 /proc/scsi/qla*/* | grep -B2 " + $hba.device + " | grep -i 'firmware version' | head -1 | sed 's/.*Firmware version \(.*\), Driver version.*/\1/'"
			}
			$tmpStr = [string]::Format('& "{0}" {1} "{2}"', $PlinkPath, "-ssh " + $Username + "@" + $esx.Name + " -pw $Password" , $remoteCommand + ";exit")
			$line.HbaFirmwareVersion = Invoke-Expression $tmpStr
			if ($hba.driver -match "lpfc") {
				$remoteCommand = "head -4 /proc/scsi/lpfc*/* | grep -B4 " + $hba.device + " | grep -i 'emulex lightpulse FC SCSI' | sed 's/Emulex LightPulse FC SCSI \(.*\)/\1/'"
			} elseif ($hba.driver -match "qla") {
				$remoteCommand = "head -8 /proc/scsi/qla*/* | grep -B2 " + $hba.device + " | grep -i 'firmware version' | sed 's/.*Firmware version .*, Driver version \(.*\)/\1/'"
			}
			$tmpStr = [string]::Format('& "{0}" {1} "{2}"', $PlinkPath, "-ssh " + $Username + "@" + $esx.Name + " -pw $Password" , $remoteCommand + ";exit")
			$line.HbaDriverVersion = Invoke-Expression $tmpStr
		}
		$line.HWModel = $esx.hardware.systemInfo.model
		$report += $line
	}
	$progressCount++
}

if ($CSVPath) {
	# CSV file export sample usage
	$report | Export-CSV -NoTypeInformation -Delimiter ";" -Encoding ASCII -Path $CSVPath
} else {
	# Displaying result
	$report
}
