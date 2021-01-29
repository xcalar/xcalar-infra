#!/bin/bash

total=0.0
echo "Bucket		GBs"
while read sz bucket; do
    gb="$(echo "(${sz}.0+1023.0^3)/(1024.0^3)" | bc)"
    total="$(echo "$total + $gb" | bc)"
    echo "$bucket		$gb"
done < <(gsutil du -s)

echo
echo "GBs   : $total"
printf "Total : %.2f/month\n\n" $(echo "$total * 0.026" | bc)
