#!/bin/bash

GraphiteStore="/opt/graphite/storage/whisper/stats"
OlderThan=${OlderThan:-14} # in days

# Delete counters
ssh graphite "docker exec -it kamon-grafana-dashboard /bin/bash -c \"find \\\"$GraphiteStore/counters/prod/tests -type d -mtime $OlderThan -exec rm -rf {} \\;\""

# Delete gauges
ssh graphite "docker exec -it kamon-grafana-dashboard /bin/bash -c \"find \\\"$GraphiteStore/gauges/prod/tests -type d -mtime $OlderThan -exec rm -rf {} \\;\""

# Delete tags
ssh graphite "docker exec -it kamon-grafana-dashboard /bin/bash -c \"find \\\"$GraphiteStore/gauges/prod/tags -type d -mtime $OlderThan -exec rm -rf {} \\;\""
