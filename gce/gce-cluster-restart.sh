#!/bin/bash

$XLRINFRADIR/gce/gce-cluster-stop.sh "$@"
$XLRINFRADIR/gce/gce-cluster-start.sh "$@"
