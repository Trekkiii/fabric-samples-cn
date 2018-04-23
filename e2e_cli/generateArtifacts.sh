#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0


cat << EOF
    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑
    ┃　 *) 基于fabric/release/\$OS_ARCH/bin下的工具生成相关文件　　　 │
    ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
EOF

CHANNEL_NAME=$1
: ${CHANNEL_NAME:="mychannel"}
echo "channel name: $CHANNEL_NAME"

export FABRIC_ROOT=$PWD/../../fabric # fabric源码根路径
export FABRIC_CFG_PATH=$PWD # 配置文件路径
echo

if [ ! -d $FABRIC_ROOT ]; then
    echo "fabric source not exits -> $FABRIC_ROOT"
    exit 1
fi

# 获取系统架构
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')

function generateCerts () {

    # cryptogen 工具
    CRYPTOGEN=$FABRIC_ROOT/release/$OS_ARCH/bin/cryptogen

    if [ -f "$CRYPTOGEN" ]; then
        echo "Using cryptogen -> $CRYPTOGEN"
    else
        echo "Building cryptogen"
        make -C $FABRIC_ROOT release
    fi

    echo
    echo "##########################################################"
    echo "##### Generate certificates using cryptogen tool #########"
    echo "##########################################################"

    $CRYPTOGEN generate --config=./crypto-config.yaml
    echo
}

function replacePrivateKey () {

    ARCH=`uname -s | grep Darwin`

    if [ "$ARCH" == "Darwin" ]; then
        OPTS="-it"
    else
        OPTS="-i"
    fi

    cp ./docker-compose-e2e-template.yaml ./docker-compose-e2e.yaml

    CURRENT_DIR=$PWD # 当前脚本执行的目录

    # shell sed
    #       OPTION：
    #           -i[SUFFIX], --in-place[=SUFFIX]   编辑文件（如果提供SUFFIX，则进行备份）
    #       Function：
    #           s   替换，可以直接进行替换的工作，通常这个 s 的动作可以搭配正规表示法，例如 1,20s/old/new/g 一般是替换符合条件的字符串而不是整行
    #       一般function的前面会有一个地址的限制，例如 [地址]function，表示我们的动作要操作的行。
    #           m,n 表示对m和n行之间的所有行进行操作

    cd crypto-config/peerOrganizations/org1.example.com/ca/ # 进入orderer根证书目录 TODO todo like *_sk
    PRIV_KEY=$(ls *_sk)
    cd $CURRENT_DIR
    sed $OPTS "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" ./docker-compose-e2e.yaml

    cd crypto-config/peerOrganizations/org2.example.com/ca/
    PRIV_KEY=$(ls *_sk)

    cd $CURRENT_DIR
    sed $OPTS "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" ./docker-compose-e2e.yaml
}

function generateChannelArtifacts() {

    CONFIGTXGEN=$FABRIC_ROOT/release/$OS_ARCH/bin/configtxgen
    if [ -f "$CONFIGTXGEN" ]; then
        echo "Using configtxgen -> $CONFIGTXGEN"
    else
        echo "Building configtxgen"
        make -C $FABRIC_ROOT release
    fi

    echo "#################################################################"
    echo "#                    生成orderer创世区块                        #"
    echo "#################################################################"
    # 注意：由于某些未知原因（至少现在）块文件不能命名为orderer.genesis.block，否则orderer将无法启动！
    $CONFIGTXGEN -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block

    echo
    echo "#################################################################"
    echo "#             生成应用通道配置交易文件 'channel.tx'             #"
    echo "#################################################################"
    $CONFIGTXGEN -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME

    echo
    echo "#################################################################"
    echo "#             为组织Org1MSP生成锚节点更新交易文件               #"
    echo "#################################################################"
    $CONFIGTXGEN -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP

    echo
    echo "#################################################################"
    echo "#             为组织Org2MSP生成锚节点更新交易文件               #"
    echo "#################################################################"
    $CONFIGTXGEN -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
    echo
}

# 使用cryptogen工具生成组织证书
generateCerts

# 用生成的私钥名称设置docker-compose-e2e.yaml中对应的私钥名称占位符
replacePrivateKey

# 生成orderer创世区块，应用通道配置交易文件和锚点更新配置文件
generateChannelArtifacts