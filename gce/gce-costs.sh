#!/bin/bash

count() {
    grep "$@" | wc -l
}

sum_column() {
    awk 'BEGIN{x=0}{x=x+$'$1'}END{print x}'
}

TMPDIR="${TMPDIR:-/tmp}/$LOGNAME/gce/$$"
mkdir -p $TMPDIR
trap "rm -rf $TMPDIR" EXIT

gcloud compute disks list | tail -n+2 >"$TMPDIR/disks.txt"
gcloud compute instances list >"$TMPDIR/gce.txt"
gcloud compute snapshots list | tail -n+2 >"$TMPDIR/snapshot.txt"
cat "$TMPDIR/gce.txt" | grep RUNNING | grep -v 'true' >"$TMPDIR/instances.txt"
cat "$TMPDIR/gce.txt" | grep RUNNING | grep 'true' >"$TMPDIR/instances_pe.txt"

snapshot=$(cat "$TMPDIR/snapshot.txt" | sum_column 2)
pd_standard=$(grep pd-standard "$TMPDIR/disks.txt" | sum_column 3)
pd_ssd=$(grep pd-ssd "$TMPDIR/disks.txt" | sum_column 3)
g1_small="$(count g1-small "$TMPDIR/instances.txt")"
n1_standard_1="$(count n1-standard-1 "$TMPDIR/instances.txt")"
n1_standard_4="$(count n1-standard-4 "$TMPDIR/instances.txt")"
n1_standard_4pe="$(count n1-standard-4 "$TMPDIR/instances_pe.txt")"
n1_standard_8="$(count n1-standard-8 "$TMPDIR/instances.txt")"
n1_standard_8pe="$(count n1-standard-8 "$TMPDIR/instances_pe.txt")"
n1_highmem_8="$(count n1-highmem-8 "$TMPDIR/instances.txt")"
n1_highmem_8pe="$(count n1-highmem-8 "$TMPDIR/instances_pe.txt")"
n1_highmem_16="$(count n1-highmem-16 "$TMPDIR/instances.txt")"
n1_highmem_16pe="$(count n1-highmem-16 "$TMPDIR/instances_pe.txt")"

# Hourly cost without sustained discount
names=(snapshot pd-standard "pd-ssd   " g1-small n1-standard-1 n1-standard-4 n1-standard-4pe n1-standard-8 n1-standard-8pe n1-highmem-8 n1-highmem-8pe n1-highmem-16 n1-highmem-16pe)
count=($snapshot $pd_standard $pd_ssd $g1_small $n1_standard_1 $n1_standard_4 $n1_standard_4pe $n1_standard_8 $n1_standard_8pe $n1_highmem_8 $n1_highmem_8pe $n1_highmem_16 $n1_highmem_16pe)
costs=(0.026 0.04 0.17 0.027 0.05 0.20 0.06 0.40 0.12 0.504 0.140 1.008 0.280)
scale=(1.00 1.00 1.00 720.0 720.0 720.0 720.0 720.0 720.0 720.0 720.0 720.0 720.0)
total=0.0
sustained_discount=0.0
echo "Item				Count			Monthly"
for i in $(seq 0 $((${#names[@]} - 1))); do
    cost="$(echo "${count[$i]}*${costs[$i]}*${scale[i]}" | bc)"
    if [[ $cost == "0" ]]; then
        :
    fi
    name="${names[$i]}"
    if [[ $name =~ ^snapshot ]] || [[ $name =~ ^pd- ]] || [[ $name =~ pe$ ]]; then
        :
    else
        # Sustained use discount of 30% if you run the instance for the entire month
        sustained_discount="$(echo "$sustained_discount + $cost * 0.3" | bc)"
    fi
    total="$(echo $total + $cost | bc)"
    printf "${names[$i]}			${count[$i]}			%.2f\n" $cost
done

echo
printf "Sub-total              : %.2f\n" $total
printf "Sustained use discount : %.2f\n" $sustained_discount
printf "Total                  : %.2f\n\n" $(echo "$total - $sustained_discount" | bc)
