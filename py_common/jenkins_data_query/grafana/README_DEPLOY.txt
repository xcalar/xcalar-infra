Push new container to the registry:

    docker tag jdq-grafana-datasource registry.service.consul/xcalar-qa/jdq-grafana-datasource
    docker push registry.service.consul/xcalar-qa/jdq-grafana-datasource

Do the nomad stuff:
    Job file here:
        nomad/jobs/jdq-grafana-datasource.nomad
    Make any adjustments

    Tell nomad to pick up new containers:
        nomad job plan jdq-grafana-datasource.nomad
        nomad job run <whatever the above tells you to do>

Eyeball here:
    https://hashi-ui.service.consul/nomad/global/jobs

Datasource URL config for nomad containers:
    http://jdq-grafana-datasource.service.consul:9999/
