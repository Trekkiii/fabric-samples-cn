#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

set -e

SDIR=$(dirname "$0")
source $SDIR/scripts/env.sh

log "Stopping docker containers ..."
docker-compose down

# 删除链码容器
docker rm -f $(docker ps -aq --filter name=dev-peer)
# 删除链码镜像
docker rmi -f $(docker images | awk '$1 ~ /dev-peer/ { print $3 }')
log "Docker containers have been stopped"