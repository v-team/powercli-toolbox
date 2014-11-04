<# 
.SYNOPSIS 
    This script will compare all advanced settings between 2 ESXi servers
.DESCRIPTION 
    The script will compare each of all advanced settings between a source and a destination ESXi server and will display the difference
.NOTES 
    Author     : Frederic Martin - www.vmdude.fr
.LINK 
    http://www.vmdude.fr
.PARAMETER hostSourceName 
   Name of the host used for source compare
.PARAMETER hostDestinationName 
   Name of the host used for destination compare
.PARAMETER short 
   This switch allows you to bypass some advanced settings thanks to variable named $excludedSettings
.EXAMPLE 
	C:\foo> .\Compare-AdvancedSettings.ps1 -hostSourceName esx01.vmdude.fr -hostDestinationName esx02.vmdude.fr
	
	Description
	-----------
	Display all differences between advanced settings from host esx01.vmdude.fr and host esx02.vmdude.fr
.EXAMPLE 
	C:\foo> .\Compare-AdvancedSettings.ps1 -hostSourceName esx01.vmdude.fr -hostDestinationName esx02.vmdude.fr -short
	
	Description
	-----------
	Display differences (without those in $excludedSettings) between advanced settings from host esx01.vmdude.fr and host esx02.vmdude.fr
#> 

param (
	[Parameter(Mandatory=$True)]
	[string]$hostSourceName,
	[Parameter(Mandatory=$True)]
	[string]$hostDestinationName,
	[switch]$short
)

# Checking if source host exists
if (-Not ($hostSource = Get-VMHost $hostSourceName -ErrorAction SilentlyContinue)) {
	Write-Host -ForegroundColor Red "There is no source host available with name" $hostSourceName
	exit
}

# Checking if destination host exists
if (-Not ($hostDestination = Get-VMHost $hostDestinationName -ErrorAction SilentlyContinue)) {
	Write-Host -ForegroundColor Red "There is no destination host available with name" $hostDestinationName
	exit
}

$diffAdvancedSettings = @()
# Using hastable for easy and fast handle
$advancedSettingsSource = @{}
$advancedSettingsDestination = @{}
# You can filter unwanted advanced settings to be unchecked (regexp)
$excludedSettings = "ScratchConfig.CurrentScratchLocation|ScratchConfig.ConfiguredScratchLocation|Vpx.Vpxa.config.vpxa.|UserVars.ActiveDirectoryPreferredDomainControllers|Config.Defaults.cpuidMask|Mem.HostLocalSwapDir"

# Retrieving advanced settings
Get-AdvancedSetting -Entity $hostSource | %{$advancedSettingsSource.Add($_.Name,$_.Value)}
Get-AdvancedSetting -Entity $hostDestination | %{$advancedSettingsDestination.Add($_.Name,$_.Value)}

# Browsing advanced settings and check for mismatch
ForEach ($advancedSetting in $advancedSettingsSource.GetEnumerator()) {
	if ( ($short -And $advancedSetting.Name -notmatch $excludedSettings -And $advancedSetting.Value -ne $advancedSettingsDestination[$advancedSetting.Name]) -Or (-Not $short -And $advancedSetting.Value -ne $advancedSettingsDestination[$advancedSetting.Name]) ) {
		$line = "" | Select Settings, SourceValue, DestinationValue
		$line.Settings = $advancedSetting.Name
		$line.SourceValue = $advancedSetting.Value
		$line.DestinationValue = $advancedSettingsDestination[$advancedSetting.Name]
		$diffAdvancedSettings += $line
	}
}

# Displaying results
$diffAdvancedSettings

