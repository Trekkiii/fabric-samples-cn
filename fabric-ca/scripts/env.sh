#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

# 以下变量描述了拓扑结构，并且可以对其进行修改以提供不同的组织名称或每个peers组织中的peers数量。

# docker-compose网络的名称
NETWORK=fabric-ca

# orderer组织的名称
ORDERER_ORGS="org0"

# peer组织的名称
PEER_ORGS="org1 org2"

# 每一个peer组织的peers数量
NUM_PEERS=2

#
# 该文件的其余部分包含通常不会更改的变量
#

# 所有组织名称
ORGS="$ORDERER_ORGS $PEER_ORGS"

# 设置为true以填充msp的"admincerts"文件夹
ADMINCERTS=true

# orderer节点的数量
NUM_ORDERERS=1

# 挂载的目录，以在容器间共享数据
DATA=data

# 创世区块的路径
GENESIS_BLOCK_FILE=/$DATA/genesis.block

# 应用通道配置交易文件的路径
CHANNEL_TX_FILE=/$DATA/channel.tx

# 应用通道的名称
CHANNEL_NAME=mychannel

# 查询超时，单位秒
QUERY_TIMEOUT=15

# 'setup'容器的超时，单位秒
SETUP_TIMEOUT=120

# Log日志目录
LOGDIR=$DATA/logs # data/logs
LOGPATH=/$LOGDIR

# 'setup'容器执行注册身份、创建创世区块以及其它artifacts后创建setup.successful文件，标记'setup'容器成功执行完所有操作
SETUP_SUCCESS_FILE=${LOGDIR}/setup.successful
# 'setup'容器的日志文件
SETUP_LOGFILE=${LOGDIR}/setup.log

# 'run'容器的日志文件
RUN_LOGFILE=${LOGDIR}/run.log
# 'run'容器的摘要日志文件
RUN_SUMFILE=${LOGDIR}/run.sum
RUN_SUMPATH=/${RUN_SUMFILE}
# 'run'容器成功和失败的日志文件
RUN_SUCCESS_FILE=${LOGDIR}/run.success
RUN_FAIL_FILE=${LOGDIR}/run.fail

# 在本示例中，Affiliation并不用于限制用户，因此只需将所有身份置于相同的affiliation中。
export FABRIC_CA_CLIENT_ID_AFFILIATION=org1

# 启用中间层CA证书
USE_INTERMEDIATE_CA=true

# 配置区块文件
CONFIG_BLOCK_FILE=/tmp/config_block.pb

# 配置更新交易文件
CONFIG_UPDATE_ENVELOPE_FILE=/tmp/config_update_as_envelope.pb

# initOrgVars <ORG>
function initOrgVars {

    if [ $# -ne 1 ]; then
        echo "Usage: initOrgVars <ORG>"
        exit 1
    fi

    ORG=$1
    # https://blog.csdn.net/lee244868149/article/details/49781257
    # 记忆的方法：
    #    # 是去掉左边（键盘上#在$的左边）
    #    %是去掉右边（键盘上%在$的右边）
    # 单一符号是最小匹配；两个符号是最大匹配
    # 也可以对变量值里的字符串作替换：
    #    ${file/dir/path}：将第一个dir 替换为path：/path1/dir2/dir3/my.file.txt
    #    ${file//dir/path}：将全部dir 替换为path：/path1/path2/path3/my.file.txt
    ORG_CONTAINER_NAME=${ORG//./-}
    ROOT_CA_HOST=rca-${ORG}
    ROOT_CA_NAME=rca-${ORG}
    ROOT_CA_LOGFILE=$LOGDIR/${ROOT_CA_NAME}.log
    INT_CA_HOST=ica-${ORG}
    INT_CA_NAME=ica-${ORG}
    INT_CA_LOGFILE=$LOGDIR/${INT_CA_NAME}.log

    # Root CA admin identity
    # 根CA管理员
    ROOT_CA_ADMIN_USER=rca-${ORG}-admin
    ROOT_CA_ADMIN_PASS=${ROOT_CA_ADMIN_USER}pw
    # 根CA服务初始化时指定的用户名和密码，用于<fabric-ca-server init -b>
    ROOT_CA_ADMIN_USER_PASS=${ROOT_CA_ADMIN_USER}:${ROOT_CA_ADMIN_PASS}

    # Root CA intermediate identity to bootstrap the intermediate CA
    ROOT_CA_INT_USER=ica-${ORG}
    ROOT_CA_INT_PASS=${ROOT_CA_INT_USER}pw
    ROOT_CA_INT_USER_PASS=${ROOT_CA_INT_USER}:${ROOT_CA_INT_PASS}

    # Intermediate CA admin identity
    # 中间层CA管理员
    INT_CA_ADMIN_USER=ica-${ORG}-admin
    INT_CA_ADMIN_PASS=${INT_CA_ADMIN_USER}pw
    # 中间层CA服务初始化时指定的用户名和密码，用于<fabric-ca-server init -b -u>
    INT_CA_ADMIN_USER_PASS=${INT_CA_ADMIN_USER}:${INT_CA_ADMIN_PASS}

    # Admin identity for the org
    # 组织管理员，通过CA注册
    ADMIN_NAME=admin-${ORG}
    ADMIN_PASS=${ADMIN_NAME}pw
    # Typical user identity for the org
    # 组织的普通用户，用于peer组织向CA注册普通用户身份
    USER_NAME=user-${ORG}
    USER_PASS=${USER_NAME}pw

    ROOT_CA_CERTFILE=/${DATA}/${ORG}-ca-cert.pem
    INT_CA_CHAINFILE=/${DATA}/${ORG}-ca-chain.pem
    ANCHOR_TX_FILE=/${DATA}/orgs/${ORG}/anchors.tx
    ORG_MSP_ID=${ORG}MSP
    ORG_MSP_DIR=/${DATA}/orgs/${ORG}/msp
    ORG_ADMIN_CERT=${ORG_MSP_DIR}/admincerts/cert.pem
    ORG_ADMIN_HOME=/${DATA}/orgs/$ORG/admin

    if test "$USE_INTERMEDIATE_CA" = "true"; then
        CA_NAME=$INT_CA_NAME
        CA_HOST=$INT_CA_HOST
        CA_CHAINFILE=$INT_CA_CHAINFILE
        CA_ADMIN_USER_PASS=$INT_CA_ADMIN_USER_PASS
        CA_LOGFILE=$INT_CA_LOGFILE
    else
        CA_NAME=$ROOT_CA_NAME
        CA_HOST=$ROOT_CA_HOST
        CA_CHAINFILE=$ROOT_CA_CERTFILE
        CA_ADMIN_USER_PASS=$ROOT_CA_ADMIN_USER_PASS
        CA_LOGFILE=$ROOT_CA_LOGFILE
    fi
}

# 等待进程开始监听特定的主机和端口
# Usage: waitPort <what> <timeoutInSecs> <errorLogFile> <host> <port>
function waitPort {

    set +e
    local what=$1
    local secs=$2
    local logFile=$3
    local host=$4
    local port=$5

    # 端口扫描
    # -z 参数告诉netcat使用0 IO，连接成功后立即关闭连接，不进行数据交换
    nc -z $host $port > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log -n "Waiting for $what ..."
        local starttime=$(date +%s)
        while true; do
            sleep 1
            nc -z $host $port > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                break
            fi
            if [ "$(($(date +%s)-starttime))" -gt "$secs" ]; then
                fatal "Failed waiting for $what; see $logFile"
            fi
            echo -n "."
        done
        echo ""
    fi
    set -e
}

# 等待多个文件生成
# Usage: dowait <what> <timeoutInSecs> <errorLogFile> <file> [<file> ...]
function dowait {

    # 传参不能小于4个
    if [ $# -lt 4 ]; then
        fatal "Usage: dowait: $*"
    fi

    local what=$1
    local secs=$2
    local logFile=$3
    shift 3
    local logit=true
    local starttime=$(date +%s)

    for file in $*; do
        # 直至$file是一个文件，否则一直循环
        until [ -f $file ]; do
            if [ "$logit" = true ]; then
                log -n "Waiting for $what ..."
                logit=false
            fi
            sleep 1
            if [ "$(($(date +%s)-starttime))" -gt "$secs" ]; then
                echo ""
                fatal "Failed waiting for $what ($file not found); see $logFile"
            fi
            echo -n "."
        done
    done
    echo ""
}

# initOrdererVars <NUM>
function initOrdererVars {

    if [ $# -ne 2 ]; then
        echo "Usage: initOrdererVars <ORG> <NUM>"
        exit 1
    fi

    initOrgVars $1
    NUM=$2

    ORDERER_HOST=orderer${NUM}-${ORG}
    ORDERER_NAME=orderer${NUM}-${ORG}
    ORDERER_PASS=${ORDERER_NAME}pw
    ORDERER_NAME_PASS=${ORDERER_NAME}:${ORDERER_PASS}
    ORDERER_LOGFILE=$LOGDIR/${ORDERER_NAME}.log

    MYHOME=/etc/hyperledger/orderer
    TLSDIR=$MYHOME/tls

    export FABRIC_CA_CLIENT=$MYHOME
    export ORDERER_GENERAL_LOGLEVEL=debug
    export ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
    export ORDERER_GENERAL_GENESISMETHOD=file
    export ORDERER_GENERAL_GENESISFILE=$GENESIS_BLOCK_FILE
    export ORDERER_GENERAL_LOCALMSPID=$ORG_MSP_ID
    export ORDERER_GENERAL_LOCALMSPDIR=$MYHOME/msp
    # enabled TLS
    export ORDERER_GENERAL_TLS_ENABLED=true
    export ORDERER_GENERAL_TLS_PRIVATEKEY=$TLSDIR/server.key # TLS开启时指定签名私钥位置
    export ORDERER_GENERAL_TLS_CERTIFICATE=$TLSDIR/server.crt # TLS开启时指定身份证书位置
    export ORDERER_GENERAL_TLS_ROOTCAS=[$CA_CHAINFILE] # TLS开启时指定信任的根CA证书位置
}

# initPeerVars <ORG> <NUM>
function initPeerVars {

    if [ $# -ne 2 ]; then
        echo "Usage: initPeerVars <ORG> <NUM>: $*"
        exit 1
    fi

    initOrgVars $1
    NUM=$2

    PEER_HOST=peer${NUM}-${ORG}
    PEER_NAME=peer${NUM}-${ORG}
    PEER_PASS=${PEER_NAME}pw
    PEER_NAME_PASS=${PEER_NAME}:${PEER_PASS}
    PEER_LOGFILE=$LOGDIR/${PEER_NAME}.log

    MYHOME=/opt/gopath/src/github.com/hyperledger/fabric/peer
    TLSDIR=$MYHOME/tls

    export FABRIC_CA_CLIENT=$MYHOME
    export CORE_PEER_ID=$PEER_HOST
    export CORE_PEER_ADDRESS=$PEER_HOST:7051
    export CORE_PEER_LOCALMSPID=$ORG_MSP_ID
    export CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
    # the following setting starts chaincode containers on the same
    # bridge network as the peers
    # https://docs.docker.com/compose/networking/
    # export CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=${COMPOSE_PROJECT_NAME}_${NETWORK}
    export CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=${COMPOSE_PROJECT_NAME}_${NETWORK}
    # export CORE_LOGGING_LEVEL=ERROR
    export CORE_LOGGING_LEVEL=DEBUG
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_TLS_CLIENTAUTHREQUIRED=true # 与Orderer端点相互通信时使用TLS
    export CORE_PEER_TLS_ROOTCERT_FILE=$CA_CHAINFILE # TLS开启时指定信任的根CA证书位置
    export CORE_PEER_TLS_CLIENTCERT_FILE=/$DATA/tls/$PEER_NAME-cli-client.crt # Peer节点的PEM编码的X509公钥文件(代表peer用户身份)，用于与Orderer端点进行相互TLS通信
    export CORE_PEER_TLS_CLIENTKEY_FILE=/$DATA/tls/$PEER_NAME-cli-client.key # Peer节点的PEM编码的私钥文件(代表peer用户身份)，用于与Orderer端点进行相互TLS通信
    export CORE_PEER_PROFILE_ENABLED=true
    # gossip variables
    export CORE_PEER_GOSSIP_USELEADERELECTION=true
    export CORE_PEER_GOSSIP_ORGLEADER=false
    export CORE_PEER_GOSSIP_EXTERNALENDPOINT=$PEER_HOST:7051 # 节点被组织外节点感知时的地址
    if [ $NUM -gt 1 ]; then
        # 启动节点后向哪些节点发起gossip连接，以加入网络。这些节点与本地节点需要属于同一组织。
        export CORE_PEER_GOSSIP_BOOTSTRAP=peer1-${ORG}:7051
    fi

    # run-fabric.sh 脚本使用
    # 连接Orderer端点的连接属性
    #       -o, --orderer string    Orderer服务地址
    #       --tls    在与Orderer端点通信时使用TLS
    #       --cafile string     Orderer节点的TLS证书，PEM格式编码，启用TLS时有效
    #       --clientauth    与Orderer端点相互通信时使用TLS
    #       --certfile string    Peer节点的PEM编码的X509公钥文件(代表peer用户身份)，用于与Orderer端点进行相互TLS通信
    #       --keyfile string    Peer节点的PEM编码的私钥文件(代表peer用户身份)，用于与Orderer端点进行相互TLS通信
    export ORDERER_CONN_ARGS="$ORDERER_PORT_ARGS --keyfile $CORE_PEER_TLS_CLIENTKEY_FILE --certfile $CORE_PEER_TLS_CLIENTCERT_FILE"
}

# 如果MSP目录下的tls相关证书目录不存在的话，则创建它们
function finishMSPSetup {

    if [ $# -ne 1 ]; then
        fatal "Usage: finishMSPSetup <targetMSPDIR>"
    fi
    if [ ! -d $1/tlscacerts ]; then
        mkdir $1/tlscacerts
        cp $1/cacerts/* $1/tlscacerts
        if [ -d $1/intermediatecerts ]; then
            mkdir $1/tlsintermediatecerts
            cp $1/intermediatecerts/* $1/tlsintermediatecerts
        fi
    fi
}

# 切换到当前组织的管理员身份。如果之前没有登记，则登记。
function switchToAdminIdentity {

    if [ ! -d $ORG_ADMIN_HOME ]; then
        # 等待CA服务端将初始化生成的根证书拷贝为CA_CHAINFILE文件
        dowait "$CA_NAME to start" 60 $CA_LOGFILE $CA_CHAINFILE
        log "Enrolling admin '$ADMIN_NAME' with $CA_HOST ..."
        # 向CA服务端使用组织管理员身份登记时生成的证书的保存路径/${DATA}/orgs/$ORG/admin/msp
        export FABRIC_CA_CLIENT_HOME=$ORG_ADMIN_HOME
        # fabric-ca-client enroll 向CA服务端使用组织管理员身份登记时使用
        export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE # CA的根证书
        fabric-ca-client enroll -d -u https://$ADMIN_NAME:$ADMIN_PASS@$CA_HOST:7054

        # 将 /${DATA}/orgs/$ORG/admin/msp/signcerts/ 下的证书拷贝为:
        #       /${DATA}/orgs/${ORG}/msp/admincerts/cert.pem ($DATA目录)
        #       /${DATA}/orgs/$ORG/admin/msp/admincerts/cert.pem ($DATA目录)
        if [ $ADMINCERTS ]; then
            # ORG_ADMIN_CERT=/${DATA}/orgs/${ORG}/msp/admincerts/cert.pem
            mkdir -p $(dirname "${ORG_ADMIN_CERT}")
            cp $ORG_ADMIN_HOME/msp/signcerts/* $ORG_ADMIN_CERT
            mkdir $ORG_ADMIN_HOME/msp/admincerts
            cp $ORG_ADMIN_HOME/msp/signcerts/* $ORG_ADMIN_HOME/msp/admincerts
        fi
    fi
    export CORE_PEER_MSPCONFIGPATH=$ORG_ADMIN_HOME/msp # /${DATA}/orgs/$ORG/admin/msp
}

# 切换到当前组织的普通用户身份。如果之前没有登记，则登记。
function switchToUserIdentity {

    export FABRIC_CA_CLIENT_HOME=/etc/hyperledger/fabric/orgs/$ORG/user
    export CORE_PEER_MSPCONFIGPATH=$FABRIC_CA_CLIENT_HOME/msp

    if [ ! -d $FABRIC_CA_CLIENT_HOME ]; then
        # 等待CA服务端将初始化生成的根证书拷贝为CA_CHAINFILE文件
        dowait "$CA_NAME to start" 60 $CA_LOGFILE $CA_CHAINFILE
        log "Enrolling user for organization $ORG with home directory $FABRIC_CA_CLIENT_HOME ..."
        # fabric-ca-client enroll 向CA服务端使用组织普通用户身份登记时使用
        export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE # CA的根证书
        fabric-ca-client enroll -d -u https://$USER_NAME:$USER_PASS@$CA_HOST:7054

        # 将 /${DATA}/orgs/$ORG/admin/msp/signcerts/ 下的证书拷贝为:
        #       /etc/hyperledger/fabric/orgs/$ORG/user/msp/admincerts ('run'容器里的目录)
        if [ $ADMINCERTS ]; then
            ACDIR=$CORE_PEER_MSPCONFIGPATH/admincerts
            mkdir -p $ACDIR
            cp $ORG_ADMIN_HOME/msp/signcerts/* $ACDIR
        fi
    fi
}

function awaitSetup {
   dowait "the 'setup' container to finish registering identities, creating the genesis block and other artifacts" $SETUP_TIMEOUT $SETUP_LOGFILE /$SETUP_SUCCESS_FILE
}

# 将组织的管理员证书拷贝到目标MSP目录
# 只有在启用了ADMINCERTS的情况下才需要
function copyAdminCert {

    if [ $# -ne 1 ]; then
        fatal "Usage: copyAdminCert <targetMSPDIR>"
    fi

    if $ADMINCERTS; then
        dstDir=$1/admincerts
        mkdir -p $dstDir
        dowait "$ORG administator to enroll" 60 $SETUP_LOGFILE $ORG_ADMIN_CERT
        cp $ORG_ADMIN_CERT $dstDir
    fi
}

function genClientTLSCert {

    if [ $# -ne 3 ]; then
        echo "Usage: genClientTLSCert <host name> <cert file> <key file>: $*"
        exit 1
    fi

    HOST_NAME=$1
    CERT_FILE=$2
    KEY_FILE=$3

    # Get a client cert
    fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $HOST_NAME

    mkdir /$DATA/tls || true
    cp /tmp/tls/signcerts/* $CERT_FILE
    cp /tmp/tls/keystore/* $KEY_FILE
    rm -rf /tmp/tls
}

# 使用管理员身份吊销用户证书，并生成CRL
function revokeFabricUserAndGenerateCRL {

    switchToAdminIdentity # 切换组织管理员身份
    export FABRIC_CA_CLIENT_HOME=$ORG_ADMIN_HOME # /${DATA}/orgs/$ORG/admin
    logr "Revoking the user '$USER_NAME' of the organization '$ORG' with Fabric CA Client home directory set to $FABRIC_CA_CLIENT_HOME and generating CRL ..."
    export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
    fabric-ca-client revoke -d --revoke.name $USER_NAME --gencrl
}

# 生成一个包含所有已撤销注册证书序列号的CRL。
# 生成的CRL存放在管理员的MSP的crls文件夹中。
function generateCRL {

    switchToAdminIdentity
    export FABRIC_CA_CLIENT_HOME=$ORG_ADMIN_HOME
    logr "Generating CRL for the organization '$ORG' with Fabric CA Client home directory set to $FABRIC_CA_CLIENT_HOME ..."
    export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
    fabric-ca-client gencrl -d
}

# log a message
function log {
   if [ "$1" = "-n" ]; then
      shift
      echo -n "##### `date '+%Y-%m-%d %H:%M:%S'` $*"
   else
      echo "##### `date '+%Y-%m-%d %H:%M:%S'` $*"
   fi
}

# fatal a message
function fatal {
   log "FATAL: $*"
   exit 1 # 错误退出
}

