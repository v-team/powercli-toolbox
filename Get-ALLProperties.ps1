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
