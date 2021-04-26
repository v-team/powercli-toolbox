$All_Vms = Get-View -ViewType VirtualMachine -Property Name
$All_Clusters = Get-View -ViewType ClusterComputeResource -Property Name, ConfigurationEx

$VsanObjectSystem = Get-VSANView -Id VsanObjectSystem-vsan-cluster-object-system

$PbmServiceInstance = Get-SpbmView -Id PbmServiceInstance-ServiceInstance
$PbmProfileManager = Get-SpbmView -id $PbmServiceInstance.PbmRetrieveServiceContent().ProfileManager
$PbmProfiles = $PbmProfileManager.PbmRetrieveContent($($PbmProfileManager.PbmQueryProfile($($PbmProfileManager.PbmFetchResourceType()),"REQUIREMENT")))

$All_Vms_table = @{}
foreach ($All_Vm in $All_Vms) {
    if (!$All_Vms_table[$All_Vm.moref]) {
        $All_Vms_table.add($All_Vm.moref, $All_Vm)
    }
}

$PbmProfiles_table = @{}
foreach ($PbmProfile in $PbmProfiles) {
    if (!$PbmProfiles_table[$PbmProfile.ProfileId.UniqueId]) {
        $PbmProfiles_table.add($PbmProfile.ProfileId.UniqueId, $PbmProfile.name)
    }
}

$AllVsanObjectsDetails = @()

foreach ($All_Cluster in $All_Clusters|?{$_.ConfigurationEx.VsanConfigInfo.Enabled}) {
    $All_Cluster_ObjectIdentities = $VsanObjectSystem.VsanQueryObjectIdentities($All_Cluster.moref,$null,$null,$true,$true,$false)

    $All_Cluster_ObjectIdentities_table = @{}
    foreach ($All_Cluster_ObjectIdentity in $All_Cluster_ObjectIdentities.Identities) {
        if (!$All_Cluster_ObjectIdentities_table[$All_Cluster_ObjectIdentity.Uuid]) {
            $All_Cluster_ObjectIdentities_table.add($All_Cluster_ObjectIdentity.Uuid, $All_Cluster_ObjectIdentity)
        }
    }

    $All_Cluster_ObjectHealthDetail_table = @{}
    foreach ($All_Cluster_ObjectHealthDetail in $All_Cluster_ObjectIdentities.Health.ObjectHealthDetail) {
        if ($All_Cluster_ObjectHealthDetail.ObjUuids) {
            foreach ($All_Cluster_ObjectHealthDetail_ObjUuid in $All_Cluster_ObjectHealthDetail.ObjUuids) {
                if (!$All_Cluster_ObjectHealthDetail_table[$All_Cluster_ObjectHealthDetail_ObjUuid]) {
                    $All_Cluster_ObjectHealthDetail_table.add($All_Cluster_ObjectHealthDetail_ObjUuid, $All_Cluster_ObjectHealthDetail.Health)
                }
            }
        }
    }

    $All_Cluster_VsanObjectQuerySpec = $All_Cluster_ObjectIdentities.Identities|%{New-Object VMware.Vsan.Views.VsanObjectQuerySpec -Property @{uuid=$_.Uuid}}
    $All_Cluster_VsanObjectInformation = $VsanObjectSystem.VosQueryVsanObjectInformation($All_Cluster.moref,$All_Cluster_VsanObjectQuerySpec)

    $All_Cluster_VsanObjectInformation_table = @{}
    foreach ($All_Cluster_VsanObjectInf in $All_Cluster_VsanObjectInformation) {
        if (!$All_Cluster_VsanObjectInformation_table[$All_Cluster_VsanObjectInf.VsanObjectUuid]) {
            $All_Cluster_VsanObjectInformation_table.add($All_Cluster_VsanObjectInf.VsanObjectUuid, $All_Cluster_VsanObjectInf)
        }
    }

    foreach ($All_Cluster_ObjectIdentity_key in $All_Cluster_ObjectIdentities_table.keys) {

        $VsanObjectDetails = "" | Select-Object vCenter, Cluster, Uuid, Vm, Description, Type, ComplianceStatus, SpbmProfile, Health

        $VsanObjectDetails.vCenter = $($global:DefaultVIServer.name)
        $VsanObjectDetails.Cluster = $($All_Cluster.name)

        $VsanObjectDetails.Uuid = $All_Cluster_ObjectIdentity_key

        try {
            $VsanObjectDetails.Vm = $($All_Vms_table[$All_Cluster_ObjectIdentities_table[$All_Cluster_ObjectIdentity_key].vm].name)
        } catch {
            $VsanObjectDetails.Vm = "N/A"
        }

        try {
            $VsanObjectDetails.Description = $($All_Cluster_ObjectIdentities_table[$All_Cluster_ObjectIdentity_key].Description)
        } catch {
            $VsanObjectDetails.Description = "N/A"
        }

        try {
            $VsanObjectDetails.Type = $($All_Cluster_ObjectIdentities_table[$All_Cluster_ObjectIdentity_key].Type)
        } catch {
            $VsanObjectDetails.Type = "N/A"
        }

        try {
            $VsanObjectDetails.ComplianceStatus = $($All_Cluster_VsanObjectInformation_table[$All_Cluster_ObjectIdentities_table[$All_Cluster_ObjectIdentity_key].Uuid].SpbmComplianceResult.ComplianceStatus)
        } catch {
            $VsanObjectDetails.ComplianceStatus = "N/A"
        }

        try {
            $VsanObjectDetails.SpbmProfile = $($PbmProfiles_table[$All_Cluster_VsanObjectInformation_table[$All_Cluster_ObjectIdentities_table[$All_Cluster_ObjectIdentity_key].Uuid].SpbmProfileUuid])
        } catch {
            $VsanObjectDetails.SpbmProfile = "N/A"
        }

        try {
            $VsanObjectDetails.Health = $($All_Cluster_ObjectHealthDetail_table[$All_Cluster_ObjectIdentities_table[$All_Cluster_ObjectIdentity_key].Uuid])
        } catch {
            $VsanObjectDetails.Health = "N/A"
        }

        $AllVsanObjectsDetails += $VsanObjectDetails
    }
}

# $AllVsanObjectsDetails|?{$_.Type -notmatch "vmswap"}|Group-Object VM|select name, {$_.group.SpbmProfile|sort -unique}, {$_.group.ComplianceStatus|sort -unique}

# https://kb.vmware.com/s/article/70774
# https://kb.vmware.com/s/article/70726