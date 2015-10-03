param ([string]$cluname, [switch]$fullviblist, [switch]$compactviblist, [string]$compactviblistout=$null)

if ($global:DefaultVIServer.ProductLine -ne "vpx"){Write-Host -ForegroundColor Red "You must be connected to a vCenter to run this script!";break}

#version 1.2
$csvdelimiter = ";"

function get-vibdiff ()
	{
		if ($cluname)
			{
				$esxhosts = Get-View -ViewType ClusterComputeResource -Filter @{"Name" = $cluname } -Property Host|select -ExpandProperty Host|%{get-view $_ -property name,runtime,config.network.dnsConfig.hostName}|?{$_.Runtime.ConnectionState -eq "Connected" -or $_.Runtime.ConnectionState -eq "Maintenance"}|sort name
			}
		else
			{
				Write-Host -ForegroundColor Red "No cluster!";break
			}
			
		foreach ($esxhost in $esxhosts){New-Variable -Name "$($esxhost.config.network.dnsConfig.hostName.replace("-","_"))_viblist" -Value (Get-VMHost $esxhost.name|Get-EsxCli).software.vib.list() -force}

		$vibreflist = $esxhosts|%{invoke-expression $("$" + $_.config.network.dnsConfig.hostName.replace("-","_") + "_viblist")}|sort name -unique

		$vibfulldifflist = @()

		foreach ($vibrefname in $vibreflist|select name)
			{
				$vibdiff = ""|select vibname
				$vibdiff.vibname = [string]$vibrefname.name
				foreach ($esxhost in $esxhosts)
					{
						$vibdiff | Add-Member –MemberType NoteProperty –Name "$($esxhost.config.network.dnsConfig.hostName.replace("-","_"))" -Value $(invoke-expression $("$" + $esxhost.config.network.dnsConfig.hostName.replace("-","_") + "_viblist")|?{$_.name -eq $vibdiff.vibname}).Version
					}
				$vibfulldifflist += $vibdiff
			}

		$vibshortdifflist = $vibfulldifflist|?{$_|select * -ExcludeProperty vibname|?{($_.psobject.Properties|sort Value -Unique|measure-object).count -gt 1}}

		if ($vibshortdifflist)
			{
				$vibrefesxhost = ((($vibfulldifflist|?{$_|select * -ExcludeProperty vibname|?{($_.psobject.Properties|sort Value -Unique|measure-object).count -gt 1}}|select * -ExcludeProperty vibname)|%{$_.psobject.Properties|?{$_.value -ne $null}}|group value|sort count|select -last 1).group|select -last 1).name

				$hostdiflist = @()

				$md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
				$utf8 = new-object -TypeName System.Text.UTF8Encoding

				$md5refesxhost=[System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($($vibfulldifflist|%{$_."$vibrefesxhost"}))))

				foreach ($esxhost in $esxhosts)
					{
					if ([System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($($vibfulldifflist|%{$_."$($esxhost.config.network.dnsConfig.hostName.replace("-","_"))"})))) -ne $md5refesxhost)
						{$hostdiflist += $esxhost.config.network.dnsConfig.hostName.replace("-","_")}
					}

				$vibcompactdifflist = @()

				if ($vibshortdifflist)
					{
					foreach ($vibrefname in $vibshortdifflist|select vibname)
						{
							$vibdiff = ""|select vibname,majority
							$vibdiff.vibname = [string]$vibrefname.vibname
							$vibdiff.majority = $(invoke-expression $("$" + $vibrefesxhost + "_viblist")|?{$_.name -eq $vibdiff.vibname}).Version
							foreach ($esxhost in $hostdiflist)
								{
									if ($(invoke-expression $("$" + $esxhost.config.network.dnsConfig.hostName.replace("-","_") + "_viblist")|?{$_.name -eq $vibdiff.vibname}).Version -ne $(invoke-expression $("$" + $vibrefesxhost + "_viblist")|?{$_.name -eq $vibdiff.vibname}).Version)
										{
										$vibdiff | Add-Member –MemberType NoteProperty –Name "$($esxhost.config.network.dnsConfig.hostName.replace("-","_"))" -Value $(invoke-expression $("$" + $esxhost.split(".")[0] + "_viblist")|?{$_.name -eq $vibdiff.vibname}).Version
										}
									else
										{
										$vibdiff | Add-Member –MemberType NoteProperty –Name "$($esxhost.config.network.dnsConfig.hostName.replace("-","_"))" -Value "=="
										}
								}
							$vibcompactdifflist += $vibdiff
						}
					}
			}
			
		if ($fullviblist)
			{$vibfulldifflist|out-gridview -title "$cluname full vib list"}
		elseif (!$fullviblist -and !$vibcompactdifflist)
			{write-host -foreground green "no vib diff in $cluname"}
		elseif ($compactviblist)
			{
				if ($compactviblistout -eq "csv")
					{
					write-host -foreground red "vib diff in $cluname $hostdiflist"
					$vibcompactdifflist|Export-Csv "./vibdiff_$cluname.csv" -NoTypeInformation -Delimiter $csvdelimiter -Force
					}
				elseif ($compactviblistout -eq "view")
					{
					write-host -foreground red "vib diff in $cluname $hostdiflist"
					$vibcompactdifflist|out-gridview -title "$cluname vib diff list"
					}
				else
					{
					write-host -foreground red "vib diff in $cluname $hostdiflist"
					$vibcompactdifflist|ft -autosize
					}
			}
		else
			{
			write-host -foreground red "vib diff in $cluname $hostdiflist"
			}
	}
	
get-vibdiff $cluname
