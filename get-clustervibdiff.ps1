param ([string]$cluname, [int]$fullviblist=$null, [int]$compactviblist=$null, [string]$compactviblistout=$null)

if ($global:DefaultVIServer.ProductLine -ne "vpx"){Write-Host -ForegroundColor Red "You must be connected to a vCenter to run this script!";break}

#version 1.1
$csvdelimiter = ";"

function get-vibdiff ()
	{
		if ($cluname)
			{
				$esxhosts = Get-View -ViewType ClusterComputeResource -Filter @{"Name" = $cluname } -Property Host|select -ExpandProperty Host|%{get-view $_ -property name,runtime}|?{$_.Runtime.ConnectionState -eq "Connected" -or $_.Runtime.ConnectionState -eq "Maintenance"}|sort name
			}
		else
			{
				Write-Host -ForegroundColor Red "No cluster!";break
			}
			
		foreach ($esxhost in $esxhosts){New-Variable -Name "$($esxhost.name.split(".")[0])_viblist" -Value (Get-VMHost $esxhost.name|Get-EsxCli).software.vib.list() -force}

		$vibreflist = $esxhosts|%{invoke-expression $("$" + $_.name.split(".")[0] + "_viblist")}|sort name -unique

		$vibfulldifflist = @()

		foreach ($vibrefname in $vibreflist|select name)
			{
				$vibdiff = ""|select vibname
				$vibdiff.vibname = [string]$vibrefname.name
				foreach ($esxhost in $esxhosts)
					{
						$vibdiff | Add-Member –MemberType NoteProperty –Name "$($esxhost.name.split(".")[0])" -Value $(invoke-expression $("$" + $esxhost.name.split(".")[0] + "_viblist")|?{$_.name -eq $vibdiff.vibname}).Version
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
					if ([System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($($vibfulldifflist|%{$_."$($esxhost.name.split(".")[0])"})))) -ne $md5refesxhost)
						{$hostdiflist += $esxhost.name}
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
									if ($(invoke-expression $("$" + $esxhost.split(".")[0] + "_viblist")|?{$_.name -eq $vibdiff.vibname}).Version -ne $(invoke-expression $("$" + $vibrefesxhost + "_viblist")|?{$_.name -eq $vibdiff.vibname}).Version)
										{
										$vibdiff | Add-Member –MemberType NoteProperty –Name "$($esxhost.split(".")[0])" -Value $(invoke-expression $("$" + $esxhost.split(".")[0] + "_viblist")|?{$_.name -eq $vibdiff.vibname}).Version
										}
									else
										{
										$vibdiff | Add-Member –MemberType NoteProperty –Name "$($esxhost.split(".")[0])" -Value "=="
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
					write-host -foreground red "vib diff in $cluname ($($hostdiflist|%{$_.split(".")[0]}))"
					$vibcompactdifflist|Export-Csv "./vibdiff_$cluname.csv" -NoTypeInformation -Delimiter $csvdelimiter -Force
					}
				elseif ($compactviblistout -eq "view")
					{
					write-host -foreground red "vib diff in $cluname ($($hostdiflist|%{$_.split(".")[0]}))"
					$vibcompactdifflist|out-gridview -title "$cluname vib diff list"
					}
				else
					{
					write-host -foreground red "vib diff in $cluname ($($hostdiflist|%{$_.split(".")[0]}))"
					$vibcompactdifflist|ft -autosize
					}
			}
		else
			{
			write-host -foreground red "vib diff in $cluname ($($hostdiflist|%{$_.split(".")[0]}))"
			}
	}
	
get-vibdiff $cluname
