#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

# up/down/restart
UP_DOWN="$1"

# Channel Name
CH_NAME="$2"

# CLI超时
CLI_TIMEOUT="$3"
# CLI如果不设置，默认为10000毫秒
: ${CLI_TIMEOUT:="10000"}

# 状态数据库是否使用CouchDB数据库
IF_COUCHDB="$4"

COMPOSE_FILE=./docker-compose-cli.yaml
COMPOSE_FILE_COUCH=./docker-compose-couch.yaml
# COMPOSE_FILE=./docker-compose-e2e.yaml

function printHelp () {
	echo -e "Usage: ./network_setup <up|down> <\$channel-name> <\$cli_timeout> <couchdb>.\nThe arguments must be in order."
}

function validateArgs () {
    if [ -z "${UP_DOWN}" ]; then
        echo "Option up / down / restart not mentioned"
        printHelp
        exit 1
    fi

    # 如果未指定通道名称，则设置默认值：mychannel
    if [ -z "${CH_NAME}" ]; then
        echo "setting to default channel 'mychannel'"
        CH_NAME=mychannel
    fi
}

function networkUp () {

    if [ -d "./crypto-config" ]; then
         echo "crypto-config directory already exists."
    else
        # 生成所有的文件，包括组织证书、orderer创世区块
        # 通道配置交易文件
        source generateArtifacts.sh $CH_NAME
    fi

    # 使用docker-compose启动docker容器
    # docker-compose-cli.yaml 中会用到 ${CHANNEL_NAME}、$TIMEOUT
    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        CHANNEL_NAME=$CH_NAME TIMEOUT=$CLI_TIMEOUT docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH up -d 2>&1
    else
        CHANNEL_NAME=$CH_NAME TIMEOUT=$CLI_TIMEOUT docker-compose -f $COMPOSE_FILE up -d 2>&1
    fi

    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Unable to pull the images "
        exit 1
    fi
    docker logs -f cli
}

function clearAllContainers () {

    CONTAINER_IDS=$(docker ps -aq)

    if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" = "" ]; then
        echo "---- No containers available for deletion ----"
    else
        docker rm -f $CONTAINER_IDS
    fi
}

function removeUnwantedImages() {

    DOCKER_IMAGE_IDS=$(docker images | grep "dev\|none\|test-vp\|peer[0-9]-" | awk '{print $3}')
    if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" = "" ]; then
            echo "---- No images available for deletion ----"
    else
            docker rmi -f $DOCKER_IMAGE_IDS
    fi
}

function networkDown () {

    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH down
    else
        docker-compose -f $COMPOSE_FILE down
    fi

    # 删除docker中的所有容器
    clearAllContainers

    # 删除链码镜像
    removeUnwantedImages

    # 删除orderer创世区块、配置交易文件、身份证书
    rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config
}

validateArgs

if [ "${UP_DOWN}" == "up" ]; then # 创建网络
    networkUp
elif [ "${UP_DOWN}" == "down" ]; then # 关闭网络
	networkDown
elif [ "${UP_DOWN}" == "restart" ]; then # 重启网络
	networkDown
	networkUp
else
	printHelp
	exit 1
fi