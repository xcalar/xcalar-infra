Overview:

This tool will provision VMs on Ovirt.
Additionally, it can install Xcalar for you on the VMs,
and form them in to a Xcalar cluster.
You can customize the memory and cores on the VMs,
as well as which xcalar installation to use.

Basic Examples:

    ./ovirttool.sh --count=2 --vmbasename=vms                # create 2 VMs (vms-vm0 and vms-vm1) with latest BuildTrunk prod build, and form into a cluster
    ./ovirttool.sh --count=2 --vmbasename=abc --nocluster    # create 2 VMs (abc-vm0 and abc-vm1) with latest BuildTrunk prod build, do not form into cluster
    ./ovirttool.sh --count=2 --vmbasename=dec --noinstaller  # create 2 VMs (dec-vm0 and dec-vm1) only; no xcalar install

-----------------------------------------------------

Setup:

(1) Clone the xcalar-infra repository, if you do not already have it

    mkdir ~/xcalar-infra
    git clone -o gerrit ssh://yourusername@gerrit.int.xcalar.com:29418/xcalar-infra xcalar-infra

(2) Install Required python libraries

    pip3 install --user ovirt-engine-sdk-python
    pip3 install --user paramiko
    pip3 install --user requests

(3) Xcalar License File

Copy the latest license file from the xcalar repo,
in to the directory you will execute this script from
(In the following example, make sure to substitute '~/xcalar/'
for the dir your own xcalar repo is in, and ~/xcalar-infra/'
for the dir your own xcalar-infra repo is in)

If you do not have a Xcalar repo, skip this step, and instead
please contact jolsen@xcalar.com and cc: abakshi@xcalar.com,
and we will provide you a license key.

    cp ~/xcalar/src/data/XcalarLic.key ~/xcalar-infra/ovirt

Note, that if you have the lic file somewhere local on
your machine, you can always specify its path directly
when you invoke the script:

    --licfile=<filepath to XcalarLic.key>

----------------------------------------------------

Help Menu:

    ./ovirttool.sh --help

----------------------------------------------------

More Examples:

Create 4 node Xcalar cluster using VMs with defaults (8 GB RAM, 4 cores,
latestBuildTrunk prod build, and VMs created on node2-cluster in Ovirt)
The VMs will be named myvms-vm0, myvms-vm1, myvms-vm2, and myvms-vm3.

    ./ovirttool.sh --count=4 --vmbasename=myvms

Create a single VM called anewvm, with no Xcalar installation

    ./ovirttool.sh --count=1 --vmbasename=anewvm --noinstaller

Create a 2 node cluster with defaults, but make VMs on node2-cluster (feynman is default).
The VMs are called vmname-vm0 and vmname-vm1, respectively.

    ./ovirttool.sh --count=2 --vmbasename=vmname --ovirtcluster=node2-cluster

Create a 4 node cluster, with VMs having 16GB memory and 2 cores each

    ./ovirttool.sh --count=4 --vmbasename=myvms --ram=16 --cores=2

Create a 4 node cluster, but use latest RC debug installation.
(the --installer arg to specify must be an URL you can curl, for an RPM installer
on netstore)

    ./ovrittool.sh --count=4 --vmbasename=myvms --installer=http://netstore/builds/Release/xcalar-latest-installer-debug

Create a 4 node cluster, but use an installer from a BuildCustom job on Jenkins

    ./ovrittool.sh --count=4 --vmbasename=myvms --installer=http://netstore/builds/byJob/BuildCustom/10384/prod/xcalar-1.3.0-10384-installer

Create just a single VM with the latest BuildTrunk prod build, called myvms

    ./ovirttool.sh --count=1 --vmbasename=myvms

Create 2 single VMs with latest RC build, and do not make them in to a cluster after install

    ./ovirttool.sh --count=2 --vmbasename=myvms --nocluster

Create 2 single VMs but don't install Xcalar on them

    ./ovirttool.sh --count=2 --vmbasename=myvms --no-installer

To save time, you can supply your username when you call the script, to bypass script prompting you for this information

    ./ovirttool.sh --user=you <other args>

----------------------------------------------

Delete VMs:::

This tool can also delete VMs from Ovirt.  To delete VMs you
no longer need, supply the name or IP of the VM you'd like to
remove, or a comma sep list of such values.  Please be careful.

Delete VM with IP 10.10.2.88, as well as VM with name ovirt-vm-auto-105

    ./ovirttool.sh --delete=10.10.2.88,ovirt-vm-auto-105

You can provision new VMs and delete existing ones, in the same run.
(The tool will always handle the deletions first, to free up resources.)

Delete VM with IP 10.10.2.89, and then create a 2 node cluster

    ./ovirttool.sh --count=2 --vmbasename=myvms --delete=10.10.2.89

----------------------------------------------

[[
    VM specs::
    Operating System: Red Hat Enterprise Linux 7.x x64
]]


