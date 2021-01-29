#!/bin/bash
set -e
DOCKER_COMPOSE_VERSION=1.26.0
curl -fL https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose-${DOCKER_COMPOSE_VERSION}
chmod +x /usr/local/bin/docker-compose-${DOCKER_COMPOSE_VERSION}
ln -sfn docker-compose-${DOCKER_COMPOSE_VERSION} /usr/local/bin/docker-compose
case "$OSID" in
    amzn2) amazon-linux-extras install -y docker ;;
    amzn*) yum install -y docker ;;
    *) curl -fsSL https://get.docker.com | bash ;;
esac
