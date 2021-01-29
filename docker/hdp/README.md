


## Source

Downloaded from https://hortonassets.s3.amazonaws.com/2.5/HDP_2.5_docker.tar.gz

Script : https://github.com/hortonworks/tutorials/blob/hdp-2.5/tutorials/hortonworks/hortonworks-sandbox-hdp2.5-guide/start_sandbox.sh

## Running

https://hortonworks.com/hadoop-tutorial/hortonworks-sandbox-guide/#section_4

    $ gzip -dc HDP_2.5_docker.tar.gz | docker load
    $ curl -sSL https://github.com/hortonworks/tutorials/raw/hdp-2.5/tutorials/hortonworks/hortonworks-sandbox-hdp2.5-guide/start_sandbox.sh > start_sandbox.sh
    $ bash ./start_sandbox.sh
    $ ssh -oPort=2222 root@localhost # password = 'hadoop'
    $ ambari-admin-password-reset

Browse to your http://localhost:8888
