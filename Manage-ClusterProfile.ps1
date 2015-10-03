param( [string]$ManagedCluster, [string]$ProfilePath, [string]$Action, [int]$SendMail="0", [int]$ForceImport="0", [int]$NoOld="0")

if (!$global:DefaultVIServers){Write-Host -ForegroundColor Red "Not connected to vcenter !";break} #check vcenter connection
$ErrorActionPreference = "SilentlyContinue"
$WarningPreference = "SilentlyContinue"
#version 1.5
$SMTPSRV = ""
$EmailFrom = ""
$EmailTo = ""

$css = '<style type="text/css">
             body { background-color:#EEEEEE; }
             body,table,td,th { font-family:Tahoma; color:Black; Font-Size:10pt }
             th { font-weight:bold; background-color:#CCCCCC; }
             td { background-color:white; }
             </style>'

if (($ManagedClusterObject = Get-View -ViewType ClusterComputeResource -Filter @{"name" = "^$ManagedCluster$"}) -isnot [VMware.Vim.ComputeResource])
       {Write-Host -ForegroundColor Red "Cluster $ManagedCluster does NOT exist !";break} #check Cluster name
       
if ($Action -ne "import" -and $Action -ne "export" -and $Action -ne "check")
       {Write-Host -ForegroundColor Red "Action not supported; Try import|export|check !";break} #check Action

if (!(Get-ChildItem $ProfilePath) -and $action -ne "check")
       {Write-Host -ForegroundColor Red "ProfilePath does NOT exist !";break} #check ProfilePath
elseif ($ProfilePath -eq $null -or $ProfilePath -eq ".\" -or $ProfilePath -eq "")
       {$ProfilePath = "."}

function Send-SMTPmail($to, $from, $subject, $smtpserver, $body) {
       $mailer = new-object Net.Mail.SMTPclient($smtpserver)
       $msg = new-object Net.Mail.MailMessage($from,$to,$subject,$body)
       $msg.IsBodyHTML = $true
       $mailer.send($msg)
}

Function Get-ALLProperties
{

       param([string]$VariableName)

       # Function that lists the properties

       function Show-Properties
       {
       Param($BaseName)
             If ((Invoke-Expression $BaseName) -ne $null)
             {
                    $Children = (Invoke-Expression $BaseName) | Get-Member -MemberType Property,ScriptProperty
                    ForEach ($Child in ($Children | Where {$_.Name -ne "Length" -and $_.Name -notmatch "Dynamic[Property|Type]" -and $_.Name -ne ""}))
                    {
                           #Write-Host -ForegroundColor Yellow $NextBase
                           if ($Child.Name -and !($Child.Name -eq "value" -and $Child.MemberType -eq "ScriptProperty"))
                                  {$NextBase = ("{0}.{1}" -f $BaseName, $Child.Name)}
                           elseif ($NextBase -is [object])
                                  {
                                  $NextBase = $BaseName
                                  
                                  $myObj = "" | Select Name, Value
                                  $myObj.Name = $NextBase.Replace("$VariableName.","")
                                  $myObj.Value = $Invocation
                                  $myObj
                                  break
                                  }
                           else
                                  {break}
                           $Invocation = (Invoke-Expression $NextBase)
                           If ($Invocation -ne $null)
                           {
                                  If ($Invocation -is [Array] -or $Invocation.pstypenames[0] -match "VMware.Vim.OptionValue|ClusterDasVmConfigInfo|ClusterDpmHostConfigInfo|ClusterDrsVmConfigInfo|ClusterGroupInfo|ClusterRuleInfo")
                                  {
                                        $ArrayCounter = 0
                                        while ((Invoke-Expression $($NextBase + '[' + $ArrayCounter + ']')) -ne $null)
                                        {
                                               Show-Properties $($NextBase + '[' + $ArrayCounter + ']')
                                               $ArrayCounter++
                                        }
                                  }
                                  #ElseIf ($Child.Definition -notlike "System*")
					ElseIf ($Invocation.pstypenames[0] -notlike "System*" -and $Child.Definition -notmatch "System.Nullable") #powershell v3
                                  {
                                        Show-Properties $NextBase
                                  }
                                  Else
                                  {
                                        $myObj = "" | Select Name, Value
                                        $myObj.Name = $NextBase.Replace("$VariableName.","")
                                        $myObj.Value = $Invocation
                                        $myObj
                                  }
                           }
                           Clear-Variable Invocation -ErrorAction SilentlyContinue
                           Clear-Variable NextBase -ErrorAction SilentlyContinue
                    }
             }
             Else
             {
                    Write-Warning "Expand Failed for $BaseName"
             }
       }
       Show-Properties $VariableName
}

$ManagedClusterProperties = Get-ALLProperties '$ManagedClusterObject.ConfigurationEx'

if ($Action -eq "export" -and (Test-Path $ProfilePath -PathType container))
       {
       if ((get-item "$ProfilePath\$($ManagedCluster)-profile.xml").Exists)
             {
             if ((get-item "$ProfilePath\$($ManagedCluster)-profile.old").Exists -and $NoOld -eq 0){Remove-Item -Force "$ProfilePath\$($ManagedCluster)-profile.old"}
             Rename-Item -Force "$ProfilePath\$($ManagedCluster)-profile.xml" "$ProfilePath\$($ManagedCluster)-profile.old"
             }
       $ManagedClusterObject.ConfigurationEx|Export-Clixml "$ProfilePath\$($ManagedCluster)-profile.xml" -Depth 999 -Force -Confirm:$false
       }
elseif ($Action -eq "import" -and (Get-ChildItem "$ProfilePath" -ErrorAction SilentlyContinue).extension -eq ".xml")
       {
       if ($ForceImport -ne "1")
             {
             Write-Host -ForegroundColor RED "Import $ProfilePath ?"
             Remove-Variable -name "Quizz" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
             While ($Quizz -cne "YES" -and $Quizz -cne "NO")
                    {
                    $Quizz = (Read-Host "Go ? [YES/NO]")
                    }
                    if ($Quizz -ceq "NO")
                           {Write-Host -ForegroundColor Yellow "Bye";break}
             }
       if (($ManagedClusterProfile = Import-Clixml $ProfilePath).pstypenames[0] -ne "Deserialized.VMware.Vim.ClusterConfigInfoEx"){Write-Host -ForegroundColor Red "Not a Cluster Profile !";break} #check xml file
       $ManagedClusterProfileProperties = Get-ALLProperties '$ManagedClusterProfile'
       
       #http://pubs.vmware.com/vsphere-50/topic/com.vmware.wssdk.apiref.doc_50/vim.cluster.ConfigSpecEx.html
       $ComputeResourceConfigurationEx = New-Object VMware.Vim.ClusterConfigSpecEx
             #dasConfig
             if ($ManagedClusterProfile.dasConfig.Enabled -eq "true")
                    {
                    $ComputeResourceConfigurationEx.dasConfig = New-Object VMware.Vim.ClusterDasConfigInfo
                           if ($ManagedClusterProfile.dasConfig.admissionControlEnabled -eq "true")
                                  {
                                  $ComputeResourceConfigurationEx.dasConfig.admissionControlEnabled = $ManagedClusterProfile.dasConfig.admissionControlEnabled
                                  #admissionControlPolicy
                                  $ComputeResourceConfigurationEx.dasConfig.admissionControlPolicy = New-Object $($ManagedClusterProfile.dasConfig.AdmissionControlPolicy.PSObject.TypeNames[0].Replace("Deserialized.",""))
                                  if ($ManagedClusterProfile.dasConfig.AdmissionControlPolicy.PSObject.TypeNames[0].Replace("Deserialized.VMware.Vim.","") -eq "ClusterFailoverLevelAdmissionControlPolicy")
                                         {$ComputeResourceConfigurationEx.dasConfig.admissionControlPolicy.failoverLevel = $ManagedClusterProfile.dasConfig.AdmissionControlPolicy.failoverLevel}
                                  elseif ($ManagedClusterProfile.dasConfig.AdmissionControlPolicy.PSObject.TypeNames[0].Replace("Deserialized.VMware.Vim.","") -eq "ClusterFailoverResourcesAdmissionControlPolicy")
                                        {
                                         $ComputeResourceConfigurationEx.dasConfig.admissionControlPolicy.cpuFailoverResourcesPercent = $ManagedClusterProfile.dasConfig.AdmissionControlPolicy.cpuFailoverResourcesPercent
                                         $ComputeResourceConfigurationEx.dasConfig.admissionControlPolicy.memoryFailoverResourcesPercent = $ManagedClusterProfile.dasConfig.AdmissionControlPolicy.memoryFailoverResourcesPercent
                                        }
                                  }
                           else 
                                  {$ComputeResourceConfigurationEx.dasConfig.admissionControlEnabled = "false"}
                           #defaultVmSettings
                           $ComputeResourceConfigurationEx.dasConfig.defaultVmSettings = New-Object VMware.Vim.ClusterDasVmSettings
                                  $ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.isolationResponse = $ManagedClusterProfile.dasConfig.defaultVmSettings.isolationResponse
                                  $ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.restartPriority = $ManagedClusterProfile.dasConfig.defaultVmSettings.restartPriority
                                  #ClusterVmToolsMonitoringSettings
                                  if ($ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.enabled -eq "true" -or $ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.vmMonitoring -ne "vmMonitoringDisabled")
                                        {
                                         $ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.vmToolsMonitoringSettings = New-Object VMware.Vim.ClusterVmToolsMonitoringSettings
                                        $ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.clusterSettings = $ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.clusterSettings
                                        if ($ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.enabled){$ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.enabled = $ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.enabled}
                                        $ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.failureInterval = $ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.failureInterval
                                         $ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.maxFailures = $ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.maxFailures
                                       $ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.maxFailureWindow = $ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.maxFailureWindow
                                         $ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.minUpTime = $ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.minUpTime
                                        if ($ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.vmMonitoring){$ComputeResourceConfigurationEx.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.vmMonitoring = $ManagedClusterProfile.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.vmMonitoring}
                                        }
                           $ComputeResourceConfigurationEx.dasConfig.enabled = $ManagedClusterProfile.dasConfig.enabled
                           if ($ManagedClusterProfile.dasConfig.failoverLevel){$ComputeResourceConfigurationEx.dasConfig.failoverLevel = $ManagedClusterProfile.dasConfig.failoverLevel}
                           if ($ManagedClusterProfile.dasConfig.hBDatastoreCandidatePolicy){$ComputeResourceConfigurationEx.dasConfig.hBDatastoreCandidatePolicy = $ManagedClusterProfile.dasConfig.hBDatastoreCandidatePolicy}
                           $ComputeResourceConfigurationEx.dasConfig.hostMonitoring = $ManagedClusterProfile.dasConfig.hostMonitoring
                           #option
                           if ($ManagedClusterProfile.DasConfig.Option.count -gt 0)
                                  {
                                  $ComputeResourceConfigurationEx.dasConfig.option = New-Object VMware.Vim.OptionValue[] ($ManagedClusterProfile.DasConfig.Option.count)
                                  $DasOptions = 0
                                  while ($DasOptions -lt $ManagedClusterProfile.DasConfig.Option.count)
                                        {
                                        $ComputeResourceConfigurationEx.dasConfig.option[$DasOptions] = New-Object VMware.Vim.OptionValue
                                        $ComputeResourceConfigurationEx.dasConfig.option[$DasOptions].key = $ManagedClusterProfile.DasConfig.Option[$DasOptions].key
                                         $ComputeResourceConfigurationEx.dasConfig.option[$DasOptions].value = $ManagedClusterProfile.DasConfig.Option[$DasOptions].value
                                        $DasOptions++
                                        }
                                  }
                           $ComputeResourceConfigurationEx.dasConfig.vmMonitoring = $ManagedClusterProfile.dasConfig.vmMonitoring
                    }
             #dpmConfig
             if ($ManagedClusterProfile.dpmConfigInfo.Enabled -eq "true")
                    {            
                    $ComputeResourceConfigurationEx.dpmConfig = New-Object VMware.Vim.ClusterDpmConfigInfo
                           $ComputeResourceConfigurationEx.dpmConfig.defaultDpmBehavior = $ManagedClusterProfile.dpmConfigInfo.defaultDpmBehavior.value
                           $ComputeResourceConfigurationEx.dpmConfig.enabled = $ManagedClusterProfile.dpmConfigInfo.enabled
                           $ComputeResourceConfigurationEx.dpmConfig.HostPowerActionRate = $ManagedClusterProfile.dpmConfigInfo.HostPowerActionRate
                           #option
                           if ($ManagedClusterProfile.dpmConfig.Option.count -gt 0)
                                  {
                                  $ComputeResourceConfigurationEx.dpmConfig.option = New-Object VMware.Vim.OptionValue[] ($ManagedClusterProfile.ConfigurationEx.DpmConfigInfo.Option.count)
                                  $DpmOptions = 0
                                  while ($DpmOptions -lt $ManagedClusterProfile.ConfigurationEx.dpmConfig.Option.count)
                                        {
                                        $ComputeResourceConfigurationEx.dpmConfig.option[$DpmOptions] = New-Object VMware.Vim.OptionValue
                                        $ComputeResourceConfigurationEx.dpmConfig.option[$DpmOptions].key = $ManagedClusterProfile.ConfigurationEx.DpmConfigInfo.Option[$DpmOptions].key
                                         $ComputeResourceConfigurationEx.dpmConfig.option[$DpmOptions].value = $ManagedClusterProfile.ConfigurationEx.DpmConfigInfo.Option[$DpmOptions].value
                                        $DpmOptions++
                                        }
                                  }                   
                    }
             #drsConfig
             if ($ManagedClusterProfile.drsConfig.Enabled -eq "true")
                    {            
                    $ComputeResourceConfigurationEx.drsConfig = New-Object VMware.Vim.ClusterDrsConfigInfo
                           $ComputeResourceConfigurationEx.drsConfig.defaultVmBehavior = $ManagedClusterProfile.drsConfig.defaultVmBehavior.value
                           $ComputeResourceConfigurationEx.drsConfig.enabled = $ManagedClusterProfile.drsConfig.enabled
                           $ComputeResourceConfigurationEx.drsConfig.enableVmBehaviorOverrides = $ManagedClusterProfile.drsConfig.enableVmBehaviorOverrides
                           #option
                           if ($ManagedClusterProfile.drsConfig.Option.count -gt 0)
                                  {
                                  $ComputeResourceConfigurationEx.drsConfig.option = New-Object VMware.Vim.OptionValue[] ($ManagedClusterProfile.drsConfig.Option.count)
                                  $DrsOptions = 0
                                  while ($DrsOptions -lt $ManagedClusterProfile.drsConfig.Option.count)
                                        {
                                        $ComputeResourceConfigurationEx.drsConfig.option[$DrsOptions] = New-Object VMware.Vim.OptionValue
                                        $ComputeResourceConfigurationEx.drsConfig.option[$DrsOptions].key = $ManagedClusterProfile.drsConfig.Option[$DrsOptions].key
                                         $ComputeResourceConfigurationEx.drsConfig.option[$DrsOptions].value = $ManagedClusterProfile.drsConfig.Option[$DrsOptions].value
                                        $DrsOptions++
                                        }
                                  }                          
                           $ComputeResourceConfigurationEx.drsConfig.vmotionRate = $ManagedClusterProfile.drsConfig.vmotionRate
                    }
             $ComputeResourceConfigurationEx.VmSwapPlacement = $ManagedClusterProfile.VmSwapPlacement
       
       $ManagedClusterObjectReconfigureComputeResourceTask = $ManagedClusterObject.ReconfigureComputeResource_Task($ComputeResourceConfigurationEx, $true)
       
       }
elseif ($Action -eq "check" -and (Get-ChildItem "$ProfilePath" -ErrorAction SilentlyContinue).extension -eq ".xml")
       {
       if (($ManagedClusterProfile = Import-Clixml $ProfilePath).pstypenames[0] -ne "Deserialized.VMware.Vim.ClusterConfigInfoEx"){Write-Host -ForegroundColor Red "Not a Cluster Profile !";break} #check xml file
       $ManagedClusterProfileProperties = Get-ALLProperties '$ManagedClusterProfile'
       $ManagedClusterProfilePropertiesMismatch = @()
       Foreach ($ManagedClusterProfileProperty in $ManagedClusterProfileProperties)
             {
             $ManagedClusterProfilePropertyMismatch = Compare-Object -ReferenceObject $ManagedClusterProfileProperty -DifferenceObject ($ManagedClusterProperties|?{$_.name -eq $ManagedClusterProfileProperty.name}) -Property value 
             if ($? -eq $false)
                    {
                    $ManagedClusterProfilePropertyMismatch = ""|
                    select ClusterSetting,ClusterValue,ProfileValue
                    $ManagedClusterProfilePropertyMismatch.ClusterSetting = $ManagedClusterProfileProperty.name
                    $ManagedClusterProfilePropertyMismatch.ClusterValue = ($ManagedClusterProperties|?{$_.name -eq $ManagedClusterProfileProperty.name}).value
                    $ManagedClusterProfilePropertyMismatch.ProfileValue = $ManagedClusterProfileProperty.value
                    $ManagedClusterProfilePropertiesMismatch += $ManagedClusterProfilePropertyMismatch
                    }            
             
             elseif ($ManagedClusterProfilePropertyMismatch)
                    {
                    $ManagedClusterProfilePropertyMismatch = ""|
                    select ClusterSetting,ClusterValue,ProfileValue
                    $ManagedClusterProfilePropertyMismatch.ClusterSetting = $ManagedClusterProfileProperty.name
                    $ManagedClusterProfilePropertyMismatch.ClusterValue = ($ManagedClusterProperties|?{$_.name -eq $ManagedClusterProfileProperty.name}).value
                    $ManagedClusterProfilePropertyMismatch.ProfileValue = $ManagedClusterProfileProperty.value
                    $ManagedClusterProfilePropertiesMismatch += $ManagedClusterProfilePropertyMismatch
                    }
             }
       Foreach ($ManagedClusterProperty in $ManagedClusterProperties)
             {
             $ManagedClusterPropertyMismatch = Compare-Object -ReferenceObject $ManagedClusterProperty -DifferenceObject ($ManagedClusterProfileProperties|?{$_.name -eq $ManagedClusterProperty.name}) -Property value 
             if ($? -eq $false)
                    {
                    $ManagedClusterPropertyMismatch = ""|
                    select ClusterSetting,ClusterValue,ProfileValue
                    $ManagedClusterPropertyMismatch.ClusterSetting = $ManagedClusterProperty.name
                    $ManagedClusterPropertyMismatch.ClusterValue = $ManagedClusterProperty.value
                    $ManagedClusterPropertyMismatch.ProfileValue = ($ManagedClusterProfileProperties|?{$_.name -eq $ManagedClusterProperty.name}).value
                    $ManagedClusterProfilePropertiesMismatch += $ManagedClusterPropertyMismatch
                    }            
             
             elseif ($ManagedClusterPropertyMismatch)
                    {
                    $ManagedClusterPropertyMismatch = ""|
                    select ClusterSetting,ClusterValue,ProfileValue
                    $ManagedClusterPropertyMismatch.ClusterSetting = $ManagedClusterProperty.name
                    $ManagedClusterPropertyMismatch.ClusterValue = $ManagedClusterProperty.value
                    $ManagedClusterPropertyMismatch.ProfileValue = ($ManagedClusterProfileProperties|?{$_.name -eq $ManagedClusterProperty.name}).value
                    $ManagedClusterProfilePropertiesMismatch += $ManagedClusterPropertyMismatch
                    }
             }
             $ManagedClusterProfilePropertiesMismatch = $ManagedClusterProfilePropertiesMismatch|Sort-Object ClusterSetting -Unique
       if (($ManagedClusterProfilePropertiesMismatch|Measure-Object).count -gt 0)
             {
             if ($SendMail -ne "1")
                    {
                    $originalColor = $Host.UI.RawUI.ForegroundColor
                    $Host.ui.rawui.foregroundcolor = "yellow"
                    $ManagedClusterProfilePropertiesMismatch|ft -AutoSize
                    $Host.UI.RawUI.ForegroundColor  = $originalColor
                    }
             
             if ($SMTPSRV -and $EmailFrom -and $EmailTo -and $SendMail -eq "1")
                    {send-SMTPmail $EmailTo $EmailFrom "[VMware] $ManagedCluster is not compliant with Cluster Profile ($(($ManagedClusterProfilePropertiesMismatch|Measure-Object).count))" $SMTPSRV ($ManagedClusterProfilePropertiesMismatch|ConvertTo-Html -head $css -Title "Cluster Profile Report")}
             }
       else {Write-Host -ForegroundColor Green "$ManagedCluster match Cluster Profile"}
       }
elseif ($Action -eq "check" -and !(Get-ChildItem "$ProfilePath" -ErrorAction SilentlyContinue))
       {
       if ($SMTPSRV -and $EmailFrom -and $EmailTo -and $SendMail -eq "1")
             {send-SMTPmail $EmailTo $EmailFrom "[VMware] No Cluster Profile found for $ManagedCluster" $SMTPSRV $null}
             Write-Host -ForegroundColor yellow "no cluster profile found for $ManagedCluster";break
       }
else
       {Write-Host -ForegroundColor Red "Something's wrong. Please check parameters (i bet on xml path) !";break} #check parameters 
