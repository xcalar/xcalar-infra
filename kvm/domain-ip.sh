#!/bin/bash
arp -an | grep "$(virsh dumpxml "$1" | grep 'mac address' | cut -d\' -f2)" | awk '{print $2}' | tr -d '()'
