#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

# 此脚本通过将第三个组织添加到先前在BYFN教程中设置的网络来扩展First Network的Hyperledger Fabric

# 将$PWD/../bin追加到PATH的开头，以确保我们能够使用相应的二进制文件
# 如果需要的话，这可能会被注释掉
export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}

# Obtain the OS and Architecture string that will be used to select the correct native binaries for your platform
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
# 默认的docker-compose yaml文件
COMPOSE_FILE_ORG3=docker-compose-org3.yaml
#
COMPOSE_FILE_COUCH_ORG3=docker-compose-couch-org3.yaml
# 使用golang作为链码的开发语言
LANGUAGE=golang
# 默认的镜像标签
IMAGETAG="latest"

function printHelp () {
cat << EOF
    使用方法:
        eyfn.sh up|down|restart|generate [-c <channel name>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>] [-s <dbtype>]
        eyfn.sh -h|--help (获取此帮助)
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
        -i <imagetag> - 创建网络所使用的镜像标签 (默认为\"latest\")

    例如：

    	byfn.sh generate -c mychannel
    	byfn.sh up -c mychannel -s couchdb
            byfn.sh up -c mychannel -s couchdb -i 1.1.0-alpha
    	byfn.sh up -l node
    	byfn.sh down -c mychannel
            byfn.sh upgrade -c mychannel

    或者全部使用默认值：

        byfn.sh generate
        byfn.sh up
        byfn.sh down
EOF
}

# 询问用户是否继续
function askProceed () {
    # -p 显示给用户的信息
    # ans 用户输入
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

# 我们使用cryptogen工具为新组织生成证书（x509证书）。在我们运行该工具后，证书将被保存在名为`crypto-config`的文件夹中。

# 使用cryptogen工具生成Org3证书
function generateCerts () {

    which cryptogen
    if [ "$?" -ne 0 ]; then
        echo "cryptogen tool not found. exiting"
        exit 1
    fi

    echo
    echo "###############################################################"
    echo "#     Generate Org3 certificates using cryptogen tool         #"
    echo "###############################################################"

    # 单小括号 ():
    #   命令组。括号中的命令将会新开一个子shell顺序执行，所以括号中的变量不能够被脚本余下的部分使用。括号中多个命令之间用分号隔开，最后一个命令可以没有分号，各命令和括号之间不必有空格。
    # 这会导致执行完‘(cd org3-artifacts ...)’内所有命令，跳出‘()'后，仍处于当前目录
    (
        cd org3-artifacts
        set -x
        cryptogen generate --config=./org3-crypto.yaml
        res=$?
        set +x

        if [ $res -ne 0 ]; then
            echo "Failed to generate certificates..."
            exit 1
        fi
    )
    echo
}

# Generate channel configuration transaction
function generateChannelArtifacts() {

    which configtxgen
    if [ "$?" -ne 0 ]; then
        echo "configtxgen tool not found. exiting"
        exit 1
    fi

    echo "##########################################################"
    echo "#########  Generating Org3 config material ###############"
    echo "##########################################################"

    (
        # 处于org3-artifacts目录
        cd org3-artifacts

        # 设置FABRIC_CFG_PATH环境变量告诉configtxgen去哪个目录寻找configtx.yaml文件
        export FABRIC_CFG_PATH=$PWD

        set -x
        # -printOrg string：将组织的定义显示为JSON（可用于手动添加组织到通道）
    	# 将Org3组织的配置保存到org3.json
        configtxgen -printOrg Org3MSP > ../channel-artifacts/org3.json
        res=$?
        set +x
        if [ $res -ne 0 ]; then
         echo "Failed to generate Org3 config material..."
         exit 1
        fi
    )

    # 当前处于first-network目录下
    # 将crypto-config/ordererOrganizations目录copy到org3-artifacts/crypto-config/目录下
    # 与此同时generateCerts方法生成的org3身份证书也存在于org3-artifacts/crypto-config/目录下
    cp -r crypto-config/ordererOrganizations org3-artifacts/crypto-config/
    echo
}

# 使用CLI容器创建配置交易文件，以用来添加Org3到fabric网络中
function createConfigTx () {

    echo
    echo "###############################################################"
    echo "####### Generate and submit config tx to add Org3 #############"
    echo "###############################################################"

    # 这里之所以使用cli容器，是因为用于将加入Org3的配置更新交易文件需要大多数peer节点的签名，
    # 而Org1 peers 与 Org2 peers节点的身份证书只挂载在cli容器中
    # Org3 peers 和 Orderer节点的身份证书挂载在Org3cli容器中
    docker exec cli scripts/step1org3.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Unable to create config tx"
        exit 1
    fi
}

# 生成组织关系和身份证书、orderer创世区块、应用通道配置交易文件、锚节点更新交易文件，以及创建并启动网络
function networkUp () {

    # generate artifacts if they don't exist
    if [ ! -d "org3-artifacts/crypto-config" ]; then
        generateCerts
        generateChannelArtifacts
        createConfigTx
    fi

    # 启动org3组织的peer节点
    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        IMAGE_TAG=${IMAGETAG} docker-compose -f $COMPOSE_FILE_ORG3 -f $COMPOSE_FILE_COUCH_ORG3 up -d 2>&1
    else
        IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE_ORG3 up -d 2>&1
    fi

    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Unable to start Org3 network"
        exit 1
    fi

    echo
    echo "###############################################################"
    echo "#               Have Org3 peers join network                  #"
    echo "###############################################################"
    docker exec Org3cli ./scripts/step2org3.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Unable to have Org3 peers join network"
        exit 1
    fi

    echo
    echo "###############################################################"
    echo "#     Upgrade chaincode to have Org3 peers on the network     #"
    echo "###############################################################"
    docker exec cli ./scripts/step3org3.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Unable to add Org3 peers on network"
        exit 1
    fi

    # finish by running the test
    docker exec Org3cli ./scripts/testorg3.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Unable to run test"
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

    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_ORG3 -f $COMPOSE_FILE_COUCH down --volumes
    else
        docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_ORG3 down --volumes
    fi

    # 如果是重启，不删除容器、镜像，不删除生成的artifacts。
    # 但是账本总是会被删除，因为上述命令'docker-compose -f ... down --volumes'指定了`--volumes`选项
    if [ "$MODE" != "restart" ]; then
        # 删除docker中的所有容器
        clearContainers
        # 删除链码镜像
        removeUnwantedImages
        # 删除orderer创世区块、配置交易文件、身份证书
        rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config ./org3-artifacts/crypto-config/ channel-artifacts/org3.json
        # remove the docker-compose yaml file that was customized to the example
        rm -f docker-compose-e2e.yaml
    fi

    # For some black-magic reason the first docker-compose down does not actually cleanup the volumes
    docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_ORG3 down --volumes
    docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_ORG3 -f $COMPOSE_FILE_COUCH down --volumes
}

# If BYFN wasn't run abort
# 加入Org3时，需要该文件夹下的orderer组织证书
if [ ! -d crypto-config ]; then
  echo
  echo "ERROR: Please, run byfn.sh first."
  echo
  exit 1
fi

# 解析命令行参数
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
        i)  IMAGETAG=$OPTARG
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

# 使用docker compose 创建fabric网络
if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "down" ]; then ## Clear the network
  networkDown
elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
  generateCerts
  generateChannelArtifacts
  createConfigTx
elif [ "${MODE}" == "restart" ]; then ## Restart the network
  networkDown
  networkUp
else
  printHelp
  exit 1
fi