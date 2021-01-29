# scheduledShutdown


Use this ARM template to attach an automated shutdown schedule to your RG/VM. The
`vmName` parameter is the basename of the vm without the number. For xdp-standard-vm0,
that would be `xdp-standard-vm`. Use `scaleNumber` to indicated how many VMs to apply
to.

    az group deployment create -n shutdown1 -g xdp-customer7-4-rg --template-file scheduledShutdown.json --parameters vmName=xdp-customer7-3-vm time=2359 timeZoneId='Pacific Standard Time' scaleNumber=10

A function to this on a resourceGroup level:

    shutdownRg() {
        local group="$1"
        local -a vms=($(az vm list -g $group --query '[].id' -otsv))
        local count="${#vms[@]}"
        local vm0="${vms[0]}"
        vm0="${vm0##*/}"
        az group deployment create -n shutdown1 -g $group --template-file $XLRINFRADIR/azure/arm/scheduledShutdown/scheduledShutdown.json --parameters vmName="${vm0%[0-9]*}" time=2359 timeZoneId='Pacific Standard Time' scaleNumber=$count -ojson
    }
