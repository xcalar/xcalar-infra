## KVM


Create a new VM (domain)

    ./vm.sh el7-test3

Destroy domain

    virsh destroy el7-test3


Fix apparmour by appending the following line to /etc/apparmor.d/abstractions/libvirt-qemu


    /var/lib/libvirt/images/** r,
