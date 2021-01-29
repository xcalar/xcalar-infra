Push new container to the registry:

    docker tag sql-perf-grafana-datasource registry.service.consul/xcalar-qa/sql-perf-grafana-datasource
    docker push registry.service.consul/xcalar-qa/sql-perf-grafana-datasource

Do the nomad stuff:
    Job file here:
        nomad/jobs/sql-perf-grafana-datasource.nomad
    Make any adjustments

    Tell nomad to pick up new containers:
        export NOMAD_ADDR=http://nomad.service.consul:4646/
        nomad job plan sql-perf-grafana-datasource.nomad
        nomad job run <whatever the above tells you to do>

Eyeball here:
    https://hashi-ui.service.consul/nomad/global/jobs

Datasource URL config for nomad containers:
    http://sql-perf-grafana-datasource.service.consul:9999/
