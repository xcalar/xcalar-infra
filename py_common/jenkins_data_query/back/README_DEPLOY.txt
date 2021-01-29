Push new container to the registry:

    docker tag jdq-back registry.service.consul/xcalar-qa/jdq-back
    docker push registry.service.consul/xcalar-qa/jdq-back

Do the nomad stuff:
    Job file here:
        nomad/jobs/jdq-back.nomad
    Make any adjustments

    Tell nomad to pick up new containers:
        nomad job plan jdq-back.nomad
        nomad job run <whatever the above tells you to do>

Eyeball here:
    https://hashi-ui.service.consul/nomad/global/jobs

Datasource URL config for nomad containers:
    http://jdq-back.service.consul:9999/
