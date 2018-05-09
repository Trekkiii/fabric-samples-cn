#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0
#
# 用于构建运行该实例所需要的镜像
#

# 它使得脚本只要发生错误，就终止执行
# set +e表示关闭-e选项
set -e
# 当前脚本的路径
SDIR=$(dirname "$0")
source $SDIR/scripts/env.sh

# 删除使用镜像名称包含hyperledger创建的docker容器
dockerContainers=$(docker ps -a | awk '$2~/hyperledger/ {print $1}')
if [ "$dockerContainers" != "" ]; then
   log "Deleting existing docker containers ..."
   docker rm -f $dockerContainers > /dev/null
fi

# 删除链码的docker镜像
chaincodeImages=`docker images | grep "^dev-peer" | awk '{print $3}'`
if [ "$chaincodeImages" != "" ]; then
   log "Removing chaincode docker images ..."
   docker rmi -f $chaincodeImages > /dev/null
fi

function assertOnMasterBranch {

    if [ "`git rev-parse --abbrev-ref HEAD`" != "master" ]; then
        fatal "You must switch to the master branch in `pwd`"
    fi
}

# Perform docker clean for fabric-ca
log "Cleaning fabric-ca docker images ..."
cd $GOPATH/src/github.com/hyperledger/fabric-ca
assertOnMasterBranch
make docker-clean

# Perform docker clean for fabric and rebuild
log "Cleaning and rebuilding fabric docker images ..."
cd $GOPATH/src/github.com/hyperledger/fabric
assertOnMasterBranch
make docker-clean docker

# Perform docker clean for fabric and rebuild against latest fabric images just built
log "Rebuilding fabric-ca docker images ..."
cd $GOPATH/src/github.com/hyperledger/fabric-ca
FABRIC_TAG=latest make docker

log "Setup completed successfully.  You may run the tests multiple times by running start.sh."