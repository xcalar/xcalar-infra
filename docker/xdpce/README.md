## Xcalar Desktop Edition
Single node XDP running inside el7 docker container(with single node license valid till 22/12/2017).

### Sample invocations through make

    make run-xcalar INSTALLER_PATH=/netstore/builds/foo-installer    # run el7 container, install and start Xcalar

    MAKEFLAGS="" make docker-image INSTALLER_PATH=/netstore/builds/foo-installer  # run el7 container, install XDP, commit & save docker image

    make logsf   # to follow the logs, press Ctrl-C to stop

    make xccli   # to connect to xccli inside container

    make stop    # stop the container

    make clean   # remove container

### Run XCDE on any system where docker is installed

    docker load < xcde.tar.gz

    CONTAINER_ARGS="--cap-add=ALL --cap-drop=MKNOD --security-opt seccomp:unconfined --ulimit core=0:0 --ulimit nofile=64960 --ulimit nproc=140960:140960 --ulimit memlock=-1:-1 --ulimit stack=-1:-1 --shm-size=10g --memory-swappiness=10 -e IN_DOCKER=1 -e XLRDIR=/opt/xcalar -e container=docker -v /var/run/docker.sock:/var/run/docker.sock --name xcde -p 443:443 -p 5000:5000 -p 8000:8000 -p 8443:8443 -p 9090:9090 -p 8889:8889 -p 12124:12124 -p 18552:18552 -p 8080:8080 xcde"

### Run docker
### On Mac
    docker run -v /Volumes:/mnt/Volumes -v /Users:/mnt/Users -d -t --user xcalar $CONTAINER_ARGS bash && docker exec -it --user xcalar xcde /opt/xcalar/bin/xcalarctl start
### On all other platforms
    docker run -d -t --user xcalar $CONTAINER_ARGS bash && docker exec -it --user xcalar xcde /opt/xcalar/bin/xcalarctl start


    # Remove older container with same name if you see 'The name "/xcde" is already in use by container' error
    docker rm -f xcde

### Start chrome browser
    Open http://127.0.0.1:8080 (username/password: admin/admin)
    Xcalar adventure datasets can be found under /datasets
