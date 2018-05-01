#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

# Hyperledger Fabric网络由两个组织组成，每个组织维护两个peer，以及一个"solo"类型的orderer服务。
#
# 使用两个基本工具，这对于创建具有数字签名验证和访问控制功能的事务性网络是必需的：
#
# * cryptogen - 生成用于识别和验证网络中各种组件的x509证书。
# * configtxgen - 为orderer引导和通道创建生成必要的配置工件。

export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}

# 已知不能与此版本的first-network一起使用的fabric版本
BLACKLISTED_VERSIONS="^1\.0\. ^1\.1\.0-preview ^1\.1\.0-alpha"

# 获取将用于为您的平台（platform）选择正确的本地二进制文件的OS和体系结构（architecture）标识串
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
# 超时时间 - CLI在放弃之前应该等待来自另一个容器的响应的等待时间，单位s
CLI_TIMEOUT=10
# 命令之间延迟的默认值
CLI_DELAY=3
# 应用通道名称，默认为"mychannel"
CHANNEL_NAME="mychannel"
# 默认的docker-compose yaml文件
COMPOSE_FILE=docker-compose-cli.yaml
#
COMPOSE_FILE_COUCH=docker-compose-couch.yaml
# 使用golang作为链码的开发语言
LANGUAGE=golang
# 默认的镜像标签
IMAGETAG="latest"

export FABRIC_ROOT=$PWD/../../fabric # fabric源码根路径

if [ ! -d $FABRIC_ROOT ]; then
    echo "fabric source not exits -> $FABRIC_ROOT"
    exit 1
fi

# Print the usage message
function printHelp () {

cat << EOF
    使用方法:
      byfn.sh up|down|restart|generate|upgrade [-c <channel name>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>] [-s <dbtype>] [-i <imagetag>]
      byfn.sh -h|--help (获取此帮助)
        <mode> - 'up', 'down', 'restart' 或者 'generate'
          - 'up' - 使用'docker-compose up'创建网络
          - 'down' - 使用'docker-compose down'关闭网络，并删除相关fabric文件、docker组件
          - 'restart' - 重启网络
          - 'generate' - 生成必要的身份证书、创世区块、应用通道配置交易文件和锚点更新配置文件
          - 'upgrade'  - 将网络从 v1.0.x 升级到 v1.1
        -c <channel name> - 使用的应用通道名称 (默认为\"mychannel\")
        -t <timeout> - CLI在放弃之前应该等待来自另一个容器的响应的超时时间，单位s (默认10s)
        -d <delay> - 命令之间延迟，单位s(默认3s)
        -f <docker-compose-file> - 指定要使用的docker-compose 文件(默认为docker-compose-cli.yaml)
        -s <dbtype> - 使用的数据库: goleveldb (默认) 或者 couchdb(支持更高级的查询)
        -l <language> - 编写链码使用的开发语言: golang (默认) 或者 node
        -i <imagetag> - 创建网络所使用镜像的tag (默认为\"latest\")，i.e -i 1.1.0

    例如：

    	byfn.sh generate -c mychannel
    	byfn.sh up -c mychannel -s couchdb
            byfn.sh up -c mychannel -s couchdb -i 1.1.0-alpha
    	byfn.sh up -l node
    	byfn.sh down -c mychannel
            byfn.sh upgrade -c mychannel

    或者使用默认值：

        byfn.sh generate
        byfn.sh up
        byfn.sh down
EOF
}

# 询问用户是否继续
function askProceed () {

    read -p "Continue? [Y/n] " ans

    case "$ans" in
        y|Y|"" )
          echo "proceeding ..."
        ;;
        n|N )
          echo "exiting..."
          exit 1
        ;;
        * )
          echo "invalid response"
          askProceed
        ;;
    esac
}

# 做一些基本的检查，以确保fabric二进制文件和镜像版本可用。未来，可以增加其他检查。
function checkPrereqs() {

    # Note, we check configtxlator externally because it does not require a config file, and peer in the
    # docker image because of FAB-8551 that makes configtxlator return 'development version' in docker

    LOCAL_VERSION=$(configtxlator version | sed -ne 's/ Version: //p')
    # --rm: Automatically remove the container when it exits
    DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:$IMAGETAG peer version | sed -ne 's/ Version: //p'|head -1)

    echo "LOCAL_VERSION=$LOCAL_VERSION"
    echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

    # 校验本地二进制文件和docker镜像的版本号是否一致，不一致发出警告
    if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ] ; then
        echo "=================== WARNING ==================="
        echo "  Local fabric binaries and docker images are  "
        echo "  out of  sync. This may cause problems.       "
        echo "==============================================="
    fi

    # 校验本地二进制文件和docker镜像文件的版本是否是当前脚本不支持的版本，如果是，则退出。
    for UNSUPPORTED_VERSION in $BLACKLISTED_VERSIONS; do
        echo "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION
        if [ $? -eq 0 ] ; then
            echo "ERROR! Local Fabric binary version of $LOCAL_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-shell."
            exit 1
        fi

        echo "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION
        if [ $? -eq 0 ] ; then
            echo "ERROR! Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-shell."
            exit 1
        fi
    done
}

# We will use the cryptogen tool to generate the cryptographic material (x509 certs)
# for our various network entities.  The certificates are based on a standard PKI
# implementation where validation is achieved by reaching a common trust anchor.
#
# Cryptogen consumes a file - ``crypto-config.yaml`` - that contains the network
# topology and allows us to generate a library of certificates for both the
# Organizations and the components that belong to those Organizations.  Each
# Organization is provisioned a unique root certificate (``ca-cert``), that binds
# specific components (peers and orderers) to that Org.  Transactions and communications
# within Fabric are signed by an entity's private key (``keystore``), and then verified
# by means of a public key (``signcerts``).  You will notice a "count" variable within
# this file.  We use this to specify the number of peers per Organization; in our
# case it's two peers per Org.  The rest of this template is extremely
# self-explanatory.
#
# After we run the tool, the certs will be parked in a folder titled ``crypto-config``.

# Generates Org certs using cryptogen tool
function generateCerts () {

    which cryptogen

#    CRYPTOGEN=$FABRIC_ROOT/release/$OS_ARCH/bin/cryptogen
#    if [ -f "$CRYPTOGEN" ]; then
#        echo "Using cryptogen -> $CRYPTOGEN"
#    else
#        echo "Building cryptogen"
#        make -C $FABRIC_ROOT release
#    fi

    if [ "$?" -ne 0 ]; then
        echo "cryptogen tool not found. exiting"
        exit 1
    fi

    echo
    echo "##########################################################"
    echo "#     Generate certificates using cryptogen tool         #"
    echo "##########################################################"

    # 删除已生成的组织关系和身份证书
    if [ -d "crypto-config" ]; then
        rm -rf crypto-config
    fi

    set -x
    cryptogen generate --config=./crypto-config.yaml
    res=$?
    set +x

    if [ $res -ne 0 ]; then
        echo "Failed to generate certificates..."
        exit 1
    fi
    echo
}

# 将docker-compose-e2e-template.yaml复制为docker-compose-e2e.yaml，并用由cryptogen工具生成的私钥文件名替换docker-compose-e2e.yaml文件其中的私钥名称占位符
function replacePrivateKey () {

    # sed on MacOSX does not support -i flag with a null extension. We will use
    # 't' for our back-up's extension and delete it at the end of the function
    ARCH=`uname -s | grep Darwin`
    if [ "$ARCH" == "Darwin" ]; then
        OPTS="-it"
    else
        OPTS="-i"
    fi

    # Copy the template to the file that will be modified to add the private key
    cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml

    # The next steps will replace the template's contents with the
    # actual values of the private key file names for the two CAs.
    CURRENT_DIR=$PWD
    cd crypto-config/peerOrganizations/org1.example.com/ca/
    PRIV_KEY=$(ls *_sk)
    cd "$CURRENT_DIR"
    sed $OPTS "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
    cd crypto-config/peerOrganizations/org2.example.com/ca/
    PRIV_KEY=$(ls *_sk)
    cd "$CURRENT_DIR"
    sed $OPTS "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
    # If MacOSX, remove the temporary backup of the docker-compose file
    if [ "$ARCH" == "Darwin" ]; then
        rm docker-compose-e2e.yamlt
    fi
}

# The `configtxgen tool is used to create four artifacts: orderer **bootstrap
# block**, fabric **channel configuration transaction**, and two **anchor
# peer transactions** - one for each Peer Org.
#
# The orderer block is the genesis block for the ordering service, and the
# channel transaction file is broadcast to the orderer at channel creation
# time.  The anchor peer transactions, as the name might suggest, specify each
# Org's anchor peer on this channel.
#
# Configtxgen consumes a file - ``configtx.yaml`` - that contains the definitions
# for the sample network. There are three members - one Orderer Org (``OrdererOrg``)
# and two Peer Orgs (``Org1`` & ``Org2``) each managing and maintaining two peer nodes.
# This file also specifies a consortium - ``SampleConsortium`` - consisting of our
# two Peer Orgs.  Pay specific attention to the "Profiles" section at the top of
# this file.  You will notice that we have two unique headers. One for the orderer genesis
# block - ``TwoOrgsOrdererGenesis`` - and one for our channel - ``TwoOrgsChannel``.
# These headers are important, as we will pass them in as arguments when we create
# our artifacts.  This file also contains two additional specifications that are worth
# noting.  Firstly, we specify the anchor peers for each Peer Org
# (``peer0.org1.example.com`` & ``peer0.org2.example.com``).  Secondly, we point to
# the location of the MSP directory for each member, in turn allowing us to store the
# root certificates for each Org in the orderer genesis block.  This is a critical
# concept. Now any network entity communicating with the ordering service can have
# its digital signature verified.
#
# This function will generate the crypto material and our four configuration
# artifacts, and subsequently output these files into the ``channel-artifacts``
# folder.
#
# If you receive the following warning, it can be safely ignored:
#
# [bccsp] GetDefault -> WARN 001 Before using BCCSP, please call InitFactories(). Falling back to bootBCCSP.
#
# You can ignore the logs regarding intermediate certs, we are not using them in
# this crypto implementation.

# Generate orderer genesis block, channel configuration transaction and
# anchor peer update transactions
function generateChannelArtifacts() {

    which configtxgen

#    CONFIGTXGEN=$FABRIC_ROOT/release/$OS_ARCH/bin/configtxgen
#    if [ -f "$CONFIGTXGEN" ]; then
#        echo "Using configtxgen -> $CONFIGTXGEN"
#    else
#        echo "Building configtxgen"
#        make -C $FABRIC_ROOT release
#    fi

    if [ "$?" -ne 0 ]; then
        echo "configtxgen tool not found. exiting"
        exit 1
    fi

    echo "##########################################################"
    echo "#          Generating Orderer Genesis block              #"
    echo "##########################################################"
    # Note: For some unknown reason (at least for now) the block file can't be
    # named orderer.genesis.block or the orderer will fail to launch!
    set -x
    configtxgen -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block
    res=$?
    set +x
    if [ $res -ne 0 ]; then
        echo "Failed to generate orderer genesis block..."
        exit 1
    fi

    echo
    echo "#################################################################"
    echo "#   Generating channel configuration transaction 'channel.tx'   #"
    echo "#################################################################"
    set -x
    configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
    res=$?
    set +x
    if [ $res -ne 0 ]; then
        echo "Failed to generate channel configuration transaction..."
        exit 1
    fi

    echo
    echo "#################################################################"
    echo "#          Generating anchor peer update for Org1MSP            #"
    echo "#################################################################"
    set -x
    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
    res=$?
    set +x
    if [ $res -ne 0 ]; then
        echo "Failed to generate anchor peer update for Org1MSP..."
        exit 1
    fi

    echo
    echo "#################################################################"
    echo "#          Generating anchor peer update for Org2MSP            #"
    echo "#################################################################"
    set -x
    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
    res=$?
    set +x
    if [ $res -ne 0 ]; then
        echo "Failed to generate anchor peer update for Org2MSP..."
        exit 1
    fi
    echo
}

# 生成组织关系和身份证书、orderer创世区块、应用通道配置交易文件、锚节点更新交易文件，以及创建并启动网络
function networkUp () {

    checkPrereqs
    # generate artifacts if they don't exist
    if [ ! -d "crypto-config" ]; then
        # 生成组织关系和身份证书
        generateCerts
        # 将docker-compose-e2e-template.yaml复制为docker-compose.yaml，并用由cryptogen工具生成的私钥文件名替换docker-compose.yaml文件其中的私钥名称占位符
        replacePrivateKey
        # 生成orderer创世区块，应用通道配置交易文件和锚点更新配置文件
        generateChannelArtifacts
    fi

    # 通过docker-compose启动peer、orderer、ca等节点
    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH up -d 2>&1
    else
        IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE up -d 2>&1
    fi

    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Unable to start network"
        exit 1
    fi

    # now run the end to end script
    # 通过CLI客户端节点，创建应用通道，将peer加入应用通道，更新组织的锚节点配置
    docker exec cli scripts/script.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Test failed"
        exit 1
    fi
}

# 删除docker中所有容器
# 获取容器的CONTAINER_IDS并删除这些容器
# TODO Might want to make this optional - could clear other containers
function clearContainers () {

    CONTAINER_IDS=$(docker ps -aq)
    if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == "" ]; then
        echo "---- No containers available for deletion ----"
    else
        docker rm -f $CONTAINER_IDS
    fi
}

# 删除生成的所有镜像
# 特别是下面代码中指定的这些镜像经常会被疏漏
# TODO list generated image naming patterns
function removeUnwantedImages() {

    DOCKER_IMAGE_IDS=$(docker images | grep "dev\|none\|test-vp\|peer[0-9]-" | awk '{print $3}')
    if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == "" ]; then
        echo "---- No images available for deletion ----"
    else
        docker rmi -f $DOCKER_IMAGE_IDS
    fi
}

# Tear down running network
function networkDown () {

    # -v, --volumes：删除Compose文件的`volumes`部分中声明的命名卷和附加到容器的匿名卷。
    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH down --volumes
    else
        docker-compose -f $COMPOSE_FILE down --volumes
    fi

    # 如果是重启，不删除生成的artifacts。
    # 但是账本总是会被删除，因为上述命令'docker-compose -f ... down --volumes'指定了`--volumes`选项
    if [ "$MODE" != "restart" ]; then
        # 删除账本备份文件（升级fabric网络时生成的账本备份）
        docker run -v $PWD:/tmp/first-network --rm hyperledger/fabric-tools:$IMAGETAG rm -rf /tmp/first-network/ledgers-backup
        # 删除docker中的所有容器
        clearContainers
        # 删除链码镜像
        removeUnwantedImages
        # 删除orderer创世区块、配置交易文件、身份证书
        rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config ./org3-artifacts/crypto-config/ channel-artifacts/org3.json
        rm -f docker-compose-e2e.yaml
    fi
}

# 将fabric网络从v1.0.x升级到v1.1
# 停止Orderer和Peer，从Orderer和Peer中备份账本，删除Peer中的链码容器和镜像，使用`latest` tag的镜像启动Orderer和Peer节点
function upgradeNetwork () {

    docker inspect  -f '{{.Config.Volumes}}' orderer.example.com |grep -q '/var/hyperledger/production/orderer'
    if [ $? -ne 0 ]; then
        echo "ERROR !!!! This network does not appear to be using volumes for its ledgers, did you start from fabric-shell >= v1.0.6?"
        exit 1
    fi

    LEDGERS_BACKUP=./ledgers-backup

    # create ledger-backup directory
    mkdir -p $LEDGERS_BACKUP

    # 指定镜像的tag
    export IMAGE_TAG=$IMAGETAG
    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        COMPOSE_FILES="-f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH"
    else
        COMPOSE_FILES="-f $COMPOSE_FILE"
    fi

    # 停止cli容器
    docker-compose $COMPOSE_FILES stop cli
    # docker-compose up：构建，（重新）创建，启动，链接一个服务相关的容器。链接的服务都将会启动，除非他们已经运行。
    # 默认情况下，所有关联的服务将会自动被启动，除非这些服务已经在运行中。
    # 如果不希望自动启动关联的容器，可以使用 --no-deps 选项
    # 单独启动cli容器
    docker-compose $COMPOSE_FILES up -d --no-deps cli

    echo "Upgrading orderer"
    # 停止orderer容器
    docker-compose $COMPOSE_FILES stop orderer.example.com
    # 备份其账本
    docker cp -a orderer.example.com:/var/hyperledger/production/orderer $LEDGERS_BACKUP/orderer.example.com
    # 单独启动orderer容器
    docker-compose $COMPOSE_FILES up -d --no-deps orderer.example.com

    for PEER in peer0.org1.example.com peer1.org1.example.com peer0.org2.example.com peer1.org2.example.com; do

        echo "Upgrading peer $PEER"

        # 停止peer节点
        docker-compose $COMPOSE_FILES stop $PEER
        # 备份其账本
        docker cp -a $PEER:/var/hyperledger/production $LEDGERS_BACKUP/$PEER/
        # 删除当前peer所有的老版本链码容器和镜像
        CC_CONTAINERS=$(docker ps | grep dev-$PEER | awk '{print $1}') # 当前peer节点的所有链码容器ids
        if [ -n "$CC_CONTAINERS" ] ; then
            docker rm -f $CC_CONTAINERS
        fi
        CC_IMAGES=$(docker images | grep dev-$PEER | awk '{print $1}')
        if [ -n "$CC_IMAGES" ] ; then
            docker rmi -f $CC_IMAGES
        fi
        # 单独启动peer节点
        docker-compose $COMPOSE_FILES up -d --no-deps $PEER
    done

    docker exec cli scripts/upgrade_to_v11.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Test failed"
        exit 1
    fi
}

# 解析命令参数
if [ "$1" = "-m" ];then	# 支持旧的用法
    shift
fi
MODE=$1;shift

# Determine whether starting, stopping, restarting or generating for announce
if [ "$MODE" == "up" ]; then
  EXPMODE="Starting"
elif [ "$MODE" == "down" ]; then
  EXPMODE="Stopping"
elif [ "$MODE" == "restart" ]; then
  EXPMODE="Restarting"
elif [ "$MODE" == "generate" ]; then
  EXPMODE="Generating certs and genesis block for"
elif [ "$MODE" == "upgrade" ]; then
  EXPMODE="Upgrading the network"
else
  printHelp
  exit 1
fi

# ./byfn.sh up|down|restart|generate|upgrade|-h|-?
while getopts "h?c:t:d:f:s:l:i:" opt; do
    case "$opt" in
        h|\?)
          printHelp
          exit 0
        ;;
        c)  CHANNEL_NAME=$OPTARG
        ;;
        t)  CLI_TIMEOUT=$OPTARG
        ;;
        d)  CLI_DELAY=$OPTARG
        ;;
        f)  COMPOSE_FILE=$OPTARG
        ;;
        s)  IF_COUCHDB=$OPTARG
        ;;
        l)  LANGUAGE=$OPTARG
        ;;
        i)  IMAGETAG=`uname -m`"-"$OPTARG
        ;;
    esac
done

# Announce what was requested
if [ "${IF_COUCHDB}" == "couchdb" ]; then
    echo
    echo "${EXPMODE} with channel '${CHANNEL_NAME}' and CLI timeout of '${CLI_TIMEOUT}' seconds and CLI delay of '${CLI_DELAY}' seconds and using database '${IF_COUCHDB}'"
else
    echo "${EXPMODE} with channel '${CHANNEL_NAME}' and CLI timeout of '${CLI_TIMEOUT}' seconds and CLI delay of '${CLI_DELAY}' seconds"
fi

# 询问用户是否继续
askProceed

# 使用docker compose创建网络
if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "down" ]; then ## Clear the network
  networkDown
elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
  generateCerts
  replacePrivateKey
  generateChannelArtifacts
elif [ "${MODE}" == "restart" ]; then ## Restart the network
  networkDown
  networkUp
elif [ "${MODE}" == "upgrade" ]; then ## Upgrade the network from v1.0.x to v1.1
  upgradeNetwork
else
  printHelp
  exit 1
fi