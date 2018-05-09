#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0
#
# 该脚本执行运行fabric CA sample所需的一切
#

set -e

SDIR=$(dirname "$0") # 当前目录
source ${SDIR}/scripts/env.sh

cd ${SDIR}

# 删除fabric容器（其镜像名称包含hyperledger的）
dockerContainers=$(docker ps -a | awk '$2~/hyperledger/ {print $1}')
if [ "$dockerContainers" != "" ]; then
   log "Deleting existing docker containers ..."
   docker rm -f $dockerContainers > /dev/null
fi

# 删除链码容器
docker rm -f $(docker ps -aq --filter name=dev-peer)

# 删除链码镜像
chaincodeImages=`docker images | grep "^dev-peer" | awk '{print $3}'`
if [ "$chaincodeImages" != "" ]; then
   log "Removing chaincode docker images ..."
   docker rmi -f $chaincodeImages > /dev/null
fi

# 删除data目录
DDIR=${SDIR}/${DATA}
if [ -d ${DDIR} ]; then
   log "Cleaning up the data directory from previous run at $DDIR"
   rm -rf ${DDIR}
fi
mkdir -p ${DDIR}/logs

# 创建docker-compose.yml文件
${SDIR}/makeDocker.sh

# 创建docker容器
log "Creating docker containers ..."
docker-compose up -d

# 等待'setup'容器完成注册身份、创建创世区块以及其它artifacts
# 完成的标志是'setup'容器创建setup.successful文件
dowait "the 'setup' container to finish registering identities, creating the genesis block and other artifacts" 90 $SDIR/$SETUP_LOGFILE $SDIR/$SETUP_SUCCESS_FILE

# 等待'run'容器启动，随后tail -f run.sum
dowait "the docker 'run' container to start" 60 ${SDIR}/${SETUP_LOGFILE} ${SDIR}/${RUN_SUMFILE}

tail -f ${SDIR}/${RUN_SUMFILE}&
TAIL_PID=$!

# 等待'run'容器执行完成
while true; do
    if [ -f ${SDIR}/${RUN_SUCCESS_FILE} ]; then
        kill -9 $TAIL_PID
        exit 0
    elif [ -f ${SDIR}/${RUN_FAIL_FILE} ]; then
        kill -9 $TAIL_PID
        exit 1
    else
        sleep 1
    fi
done