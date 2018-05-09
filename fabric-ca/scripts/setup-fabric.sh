#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0
#
# 此脚本执行以下操作：
# 1) 向中间层fabric-ca-servers注册Orderer和Peer身份
# 2) 构建通道artifacts（例如，创世区块等）
#

function main {

    log "Beginning building channel artifacts ..."
    # 注册与Orderer和Peer相关的所有用户身份
    registerIdentities
    # 为每一个组织向CA服务端申请根证书，并保存到/${DATA}/orgs/${ORG}/msp
    # 如果ADMINCERTS为true，我们需要登记管理员并将证书保存到msp/admincerts
    getCACerts
    makeConfigTxYaml
    generateChannelArtifacts
    log "Finished building channel artifacts"
    touch /$SETUP_SUCCESS_FILE # 生成setup.successful文件，标记'setup'容器成功执行完所有操作
}

# 登记CA管理员
function enrollCAAdmin {

    # 等待，直至CA服务可用
    waitPort "$CA_NAME to start" 90 $CA_LOGFILE $CA_HOST 7054
    log "Enrolling with $CA_NAME as bootstrap identity ..."
    # 主配置目录
    # fabric-ca-client会在该目录下搜索配置文件
    # 同样，也会在该目录下创建msp目录，存放证书文件
    export FABRIC_CA_CLIENT_HOME=$HOME/cas/$CA_NAME
    # fabric-ca-client enroll 向CA服务端使用CA管理员身份登记时使用
    export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE # CA的根证书
    # 使用CA管理员身份登记
    fabric-ca-client enroll -d -u https://$CA_ADMIN_USER_PASS@$CA_HOST:7054
}

# 为每一个组织向CA服务端申请根证书，并保存到/${DATA}/orgs/${ORG}/msp
# 如果ADMINCERTS为true，我们需要登记管理员并将证书保存到msp/admincerts
function getCACerts {

    log "Getting CA certificates ..."
    for ORG in $ORGS; do
        initOrgVars $ORG
        log "Getting CA certs for organization $ORG and storing in $ORG_MSP_DIR"
        # fabric-ca-client getcacert 向CA服务端申请根证书时使用
        export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE # CA的根证书
        # 向服务端申请根证书，并保存到/${DATA}/orgs/${ORG}/msp/cacerts 与 /${DATA}/orgs/${ORG}/msp/intermediatecerts目录下
        fabric-ca-client getcacert -d -u https://$CA_HOST:7054 -M $ORG_MSP_DIR
        # 如果MSP目录下的tls相关证书目录不存在的话，则创建它们。
        # 执行的操作如下：
        #   1. 创建msp/tlscacerts目录并将msp/cacerts目录下的证书拷贝到其下
        #   2. 创建msp/tlsintermediatecerts目录并将msp/intermediatecerts目录下的证书拷贝到其下
        finishMSPSetup $ORG_MSP_DIR
        # 如果ADMINCERTS为true，我们需要登记管理员并将证书保存到msp/admincerts
        if [ $ADMINCERTS ]; then
            switchToAdminIdentity
        fi
    done
}

# 注册与Orderer和Peer相关的所有用户身份
function registerIdentities {
    log "Registering identities ..."
    # 注册与Orderer相关的所有用户身份
    # 1. 注册所有orderer节点用户
    # 2. 注册orderer组织的管理员用户
    registerOrdererIdentities
    # 注册与Peer相关的所有用户
    # 1. 注册当前peer节点用户
    # 2. 注册组织的管理员用户
    # 3. 注册组织的普通用户
    registerPeerIdentities
}

# 注册与Orderer相关的所有用户身份
# 1. 注册所有orderer节点用户
# 2. 注册orderer组织的管理员用户
function registerOrdererIdentities {

    for ORG in $ORDERER_ORGS; do
        initOrgVars $ORG
        # !!! 执行注册新用户实体的客户端必须已经通过登记认证，并且拥有足够的权限来进行注册 !!!
        enrollCAAdmin
        local COUNT=1
        while [[ "$COUNT" -le $NUM_ORDERERS ]]; do
            initOrdererVars $ORG $COUNT
            log "Registering $ORDERER_NAME with $CA_NAME"
            # 注册当前orderer节点用户
            fabric-ca-client register -d --id.name $ORDERER_NAME --id.secret $ORDERER_PASS --id.type orderer
            COUNT=$((COUNT+1))
        done
        log "Registering admin identity with $CA_NAME"
        # The admin identity has the "admin" attribute which is added to ECert by default
        # 注册orderer组织的管理员用户
        fabric-ca-client register -d --id.name $ADMIN_NAME --id.secret $ADMIN_PASS --id.attrs "admin=true:ecert"
    done
}

# 注册与Peer相关的所有用户
# 1. 注册当前peer节点用户
# 2. 注册组织的管理员用户
# 3. 注册组织的普通用户
function registerPeerIdentities {

    for ORG in $PEER_ORGS; do
        initOrgVars $ORG
        # !!! 执行注册新用户实体的客户端必须已经通过登记认证，并且拥有足够的权限来进行注册 !!!
        enrollCAAdmin
        local COUNT=1
        while [[ "$COUNT" -le $NUM_PEERS ]]; do
            initPeerVars $ORG $COUNT
            log "Registering $PEER_NAME with $CA_NAME"
            # 注册当前peer节点用户
            fabric-ca-client register -d --id.name $PEER_NAME --id.secret $PEER_PASS --id.type peer
            COUNT=$((COUNT+1))
        done
        log "Registering admin identity with $CA_NAME"
        # The admin identity has the "admin" attribute which is added to ECert by default
        # 注册peer组织的管理员用户
        fabric-ca-client register -d --id.name $ADMIN_NAME --id.secret $ADMIN_PASS --id.attrs "hf.Registrar.Roles=client,hf.Registrar.Attributes=*,hf.Revoker=true,hf.GenCRL=true,admin=true:ecert,abac.init=true:ecert"
        log "Registering user identity with $CA_NAME"
        # 注册peer组织的普通用户
        fabric-ca-client register -d --id.name $USER_NAME --id.secret $USER_PASS
    done
}

function makeConfigTxYaml {

    {
    echo "################################################################################
#
#   Profile
#
#   - 可以在这里编写不同的Profile配置，以便将其指定为configtxgen工具的参数
#
################################################################################
Profiles:

    OrgsOrdererGenesis:
        Orderer:
            # Orderer Type：\"solo\" 、 \"kafka\"
            OrdererType: solo
            Addresses:" # Orderers服务地址
                for ORG in $ORDERER_ORGS; do
                    local COUNT=1
                    while [[ "$COUNT" -le $NUM_ORDERERS ]]; do
                        initOrdererVars $ORG $COUNT
                        echo "                - $ORDERER_HOST:7050"
                        COUNT=$((COUNT+1))
                    done
                done
                echo "
            # 创建批量交易的最大超时，一批交易可以构建一个区块
            BatchTimeout: 2s
            # 控制写入到区块中交易的个数
            BatchSize:
                # 一批消息的最大个数
                MaxMessageCount: 10
                # batch最大字节数，任何时候不能超过
                AbsoluteMaxBytes: 99 MB
                # 通常情况下，batch建议字节数；极端情况下，如单个消息就超过该值（但未超过最大限制），仍允许构成区块
                PreferredMaxBytes: 512 KB
            Kafka:
                # Brokers: Kafka brokers作为orderer后端
                # NOTE: 使用IP:port表示法
                Brokers:
                    - 127.0.0.1:9092
            Organizations:" # 属于orderer通道的组织
                for ORG in $ORDERER_ORGS; do
                    initOrgVars $ORG
                    echo "                - *${ORG_CONTAINER_NAME}"
                done

    echo "
        Consortiums: # Orderer所服务的联盟列表。每个联盟中组织彼此使用相同的通道创建策略，可以彼此创建应用通道
            SampleConsortium:
                Organizations:" # SampleConsortium联盟下的组织列表
                    for ORG in $PEER_ORGS; do
                        initOrgVars $ORG
                        echo "                    - *${ORG_CONTAINER_NAME}"
                    done
    echo "
    OrgsChannel:
        Consortium: SampleConsortium # SampleConsortium联盟
        Application:
            <<: *ApplicationDefaults
            Organizations:" # TODO 作用是啥？
                for ORG in $PEER_ORGS; do
                    initOrgVars $ORG
                    echo "                - *${ORG_CONTAINER_NAME}"
                done
    echo "
################################################################################
#
#   Section: Organizations
#
#   - 本节定义了稍后将在配置中引用的不同组织标识
#
################################################################################
Organizations:"

    for ORG in $ORDERER_ORGS; do
        printOrdererOrg $ORG
    done

    for ORG in $PEER_ORGS; do
        printPeerOrg $ORG 1
    done


   echo "
################################################################################
#
#   SECTION: Application
#
#   This section defines the values to encode into a config transaction or
#   genesis block for application related parameters
#
################################################################################
Application: &ApplicationDefaults

    # Organizations is the list of orgs which are defined as participants on
    # the application side of the network
    Organizations:
"
    } > /etc/hyperledger/fabric/configtx.yaml

    # 将configtx.yaml拷贝到/data目录下
    cp /etc/hyperledger/fabric/configtx.yaml /$DATA
}

function generateChannelArtifacts() {

    which configtxgen
    if [ "$?" -ne 0 ]; then
        fatal "configtxgen tool not found. exiting"
    fi

    log "Generating orderer genesis block at $GENESIS_BLOCK_FILE"
    # Note: 由于某些未知原因（至少现在）创世区块不能命名为orderer.genesis.block，否则orderer将无法启动！
    configtxgen -profile OrgsOrdererGenesis -outputBlock $GENESIS_BLOCK_FILE

    if [ "$?" -ne 0 ]; then
        fatal "Failed to generate orderer genesis block"
    fi

    log "Generating channel configuration transaction at $CHANNEL_TX_FILE"
    configtxgen -profile OrgsChannel -outputCreateChannelTx $CHANNEL_TX_FILE -channelID $CHANNEL_NAME
    if [ "$?" -ne 0 ]; then
        fatal "Failed to generate channel configuration transaction"
    fi

    for ORG in $PEER_ORGS; do
        initOrgVars $ORG
        log "Generating anchor peer update transaction for $ORG at $ANCHOR_TX_FILE"
        configtxgen -profile OrgsChannel -outputAnchorPeersUpdate $ANCHOR_TX_FILE \
                 -channelID $CHANNEL_NAME -asOrg $ORG
        if [ "$?" -ne 0 ]; then
            fatal "Failed to generate anchor peer update for $ORG"
        fi
    done
}

# printOrdererOrg <ORG>
function printOrdererOrg {
   initOrgVars $1
   printOrg
}

# printPeerOrg <ORG> <COUNT>
function printPeerOrg {

    initPeerVars $1 $2
    printOrg
    echo "
    AnchorPeers:
       # 锚节点地址，用于跨组织的Gossip通信
       - Host: $PEER_HOST
         Port: 7051"
}

# printOrg
function printOrg {

    echo "
    - &$ORG_CONTAINER_NAME
        Name: $ORG
        # MSP的ID
        ID: $ORG_MSP_ID
        # MSP相关文件所在路径
        # /${DATA}/orgs/${ORG}/msp
        MSPDir: $ORG_MSP_DIR
    "
}

set -e

SDIR=$(dirname "$0")
source $SDIR/env.sh

main