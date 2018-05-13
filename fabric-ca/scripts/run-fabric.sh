#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

set -e

source $(dirname "$0")/env.sh

function main {

    done=false # 标记是否执行完成所有以下操作

    # 等待setup容器成功完成所有操作，再等待10s以便orderer和peers节点启动
    awaitSetup
    sleep 10

    # 捕获信号
    # 在终端一个shell程序的执行过程中，当你按下 Ctrl + C 键或 Break 键，正常程序将立即终止，并返回命令提示符。这可能并不总是可取的。例如，你可能最终留下了一堆临时文件，将不会清理。
    # 捕获这些信号是很容易的，trap命令的语法如下：trap commands signals
    trap finish EXIT

    mkdir -p $LOGPATH
    logr "The docker 'run' container has started"

    # IFS:
    # 在bash中IFS是内部的域分隔符。IFS的默认值为：空白（包括：空格，tab, 和新行)，将其ASSII码用十六进制打印出来就是：20 09 0a （见下面的shell脚本）。
    #
    # read：
    #   -a:将内容读入到数组中
    #   -r:在参数输入中，我们可以使用’\’表示没有输入完，换行继续输入，如果我们需要行最后的’\’作为有效的字符，可以通过-r来进行。此外在输入字符中，我们希望\n这类特殊字符生效，也应采用-r选项。
    #   -n:用于限定最多可以有多少字符可以作为有效读入。例如read –n 4 value1 value2，如果我们试图输入12 34，则只有前面有效的12 3，作为输入，实际上在你输入第4个字符'3'后，就自动结束输入。这里结果是value为12，value2为3。
    IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"

    # 将 ORDERER_PORT_ARGS 设置为与第一个orderer组织的第一个orderer节点进行通信所需的参数
    initOrdererVars ${OORGS[0]} 1
    # 连接Orderer端点的连接属性
    #       -o, --orderer string    Orderer服务地址
    #       --tls    在与Orderer端点通信时使用TLS
    #       --cafile string     Orderer节点的TLS证书，PEM格式编码，启用TLS时有效
    #       --clientauth    与Orderer端点相互通信时使用TLS
    #       --certfile string    Peer节点的PEM编码的X509公钥文件(代表peer节点身份)，用于与Orderer端点进行相互TLS通信
    #       --keyfile string    Peer节点的PEM编码的私钥文件(代表peer节点身份)，用于与Orderer端点进行相互TLS通信
    export ORDERER_PORT_ARGS="-o $ORDERER_HOST:7050 --tls --cafile $CA_CHAINFILE --clientauth"

    # Convert PEER_ORGS to an array named PORGS
    IFS=', ' read -r -a PORGS <<< "$PEER_ORGS"

    # 创建应用通道
    createChannel

    # 所有节点加入通道
    for ORG in $PEER_ORGS; do
        local COUNT=1
        while [[ "$COUNT" -le $NUM_PEERS ]]; do
            initPeerVars $ORG $COUNT
            joinChannel
            COUNT=$((COUNT+1))
        done
    done

    # 为每个peer组织更新锚节点
    for ORG in $PEER_ORGS; do
        initPeerVars $ORG 1
        switchToAdminIdentity
        logr "Updating anchor peers for $PEER_HOST ..."
        peer channel update -c $CHANNEL_NAME -f $ANCHOR_TX_FILE $ORDERER_CONN_ARGS
    done

    # 在每个Peer组织的第一个peer节点上安装链码
    for ORG in $PEER_ORGS; do
        initPeerVars $ORG 1
        installChaincode
    done

    # 在第二个Peer组织的第一个peer节点上实例化链码
    makePolicy
    initPeerVars ${PORGS[1]} 1
    switchToAdminIdentity
    logr "Instantiating chaincode on $PEER_HOST ..."
    peer chaincode instantiate -C $CHANNEL_NAME -n mycc -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "$POLICY" $ORDERER_CONN_ARGS

    # 在第一个Peer组织的第一个peer节点上查询链码
    initPeerVars ${PORGS[0]} 1
    switchToUserIdentity
    chaincodeQuery 100

    # 在第一个Peer组织的第一个peer节点上调用链码
    initPeerVars ${PORGS[0]} 1
    switchToUserIdentity
    logr "Sending invoke transaction to $PEER_HOST ..."
    peer chaincode invoke -C $CHANNEL_NAME -n mycc -c '{"Args":["invoke","a","b","10"]}' $ORDERER_CONN_ARGS

    # 在第二个Peer组织的第二个peer节点上安装链码
    initPeerVars ${PORGS[1]} 2
    installChaincode

    # 在第二个Peer组织的第二个peer节点上查询链码
    sleep 10
    initPeerVars ${PORGS[1]} 2
    switchToUserIdentity
    chaincodeQuery 90

    # 切换到第一个Peer组织的普通用户身份
    initPeerVars ${PORGS[0]} 1
    switchToUserIdentity

    # 使用管理员身份吊销用户证书，并生成CRL
    revokeFabricUserAndGenerateCRL

    # 获取指定应用通道的配置区块
    fetchConfigBlock

    # 使用CRL和应用通道配置区块创建配置更新交易文件
    createConfigUpdatePayloadWithCRL
    updateConfigBlock

    # 用户被注销，查询链码应该失败
    switchToUserIdentity
    queryAsRevokedUser
    if [ "$?" -ne 0 ]; then
        logr "The revoked user $USER_NAME should have failed to query the chaincode in the channel '$CHANNEL_NAME'"
        exit 1
    fi
    logr "Congratulations! The tests ran successfully."

    done=true
}

# 切换到第一个peer组织的管理员身份。然后创建应用通道。
function createChannel {

    initPeerVars ${PORGS[0]} 1
    # 切换到第一个peer组织的管理员身份。如果之前没有登记，则登记。
    switchToAdminIdentity
    logr "Creating channel '$CHANNEL_NAME' on $ORDERER_HOST ..."
    peer channel create --logging-level=DEBUG -c $CHANNEL_NAME -f $CHANNEL_TX_FILE $ORDERER_CONN_ARGS
}

# 切换到peer组织的管理员身份。然后加入应用通道
function joinChannel {

    switchToAdminIdentity

    set +e

    local COUNT=1
    MAX_RETRY=10

    while true; do
        logr "Peer $PEER_HOST is attempting to join channel '$CHANNEL_NAME' (attempt #${COUNT}) ..."
        peer channel join -b $CHANNEL_NAME.block
        if [ $? -eq 0 ]; then
            set -e
            logr "Peer $PEER_HOST successfully joined channel '$CHANNEL_NAME'"
            return
        fi
        if [ $COUNT -gt $MAX_RETRY ]; then
            fatalr "Peer $PEER_HOST failed to join channel '$CHANNEL_NAME' in $MAX_RETRY retries"
        fi
        COUNT=$((COUNT+1))
        sleep 1
    done
}

function installChaincode {

    switchToAdminIdentity
    logr "Installing chaincode on $PEER_HOST ..."
    peer chaincode install -n mycc -v 1.0 -p github.com/hyperledger/fabric-samples-cn/chaincode/go/abac
}

function finish {

    if [ "$done" = true ]; then
        logr "See $RUN_LOGFILE for more details"
        touch /$RUN_SUCCESS_FILE
    else
        logr "Tests did not complete successfully; see $RUN_LOGFILE for more details"
        touch /$RUN_FAIL_FILE
    fi
}

# 实例化策略
function makePolicy {

    POLICY="OR("
    local COUNT=0

    # name=liucl
    # echo "My Name is '${name}'" -> My Name is 'liucl'
    # echo My Name is '${name}' -> My Name is ${name}
    for ORG in $PEER_ORGS; do
        if [ $COUNT -ne 0 ]; then
            POLICY="${POLICY}," # 拼接逗号
        fi
        initOrgVars $ORG
        POLICY="${POLICY}'${ORG_MSP_ID}.member'"
        COUNT=$((COUNT+1))
    done
    POLICY="${POLICY})"
    log "policy: $POLICY"
}

function chaincodeQuery {

    if [ $# -ne 1 ]; then
        fatalr "Usage: chaincodeQuery <expected-value>"
    fi

    set +e
    logr "Querying chaincode in the channel '$CHANNEL_NAME' on the peer '$PEER_HOST' ..."

    local rc=1
    local starttime=$(date +%s)

    # Continue to poll until we get a successful response or reach QUERY_TIMEOUT
    while test "$(($(date +%s)-starttime))" -lt "$QUERY_TIMEOUT"; do
        sleep 1
        peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}' >& log.txt
        VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')
        if [ $? -eq 0 -a "$VALUE" = "$1" ]; then
            logr "Query of channel '$CHANNEL_NAME' on peer '$PEER_HOST' was successful"
            set -e
            return 0
        fi
        echo -n "."
    done

    cat log.txt
    cat log.txt >> $RUN_SUMFILE
    fatalr "Failed to query channel '$CHANNEL_NAME' on peer '$PEER_HOST'; expected value was $1 and found $VALUE"
}

function fetchConfigBlock {
    logr "Fetching the configuration block of the channel '$CHANNEL_NAME'"
    peer channel fetch config $CONFIG_BLOCK_FILE -c $CHANNEL_NAME $ORDERER_CONN_ARGS
}

function createConfigUpdatePayloadWithCRL {

    logr "Creating config update payload with the generated CRL for the organization '$ORG'"
    # Start the configtxlator
    configtxlator start & # 使用restful接口形式使用configtxlator工具
    configtxlator_pid=$!

    log "configtxlator_pid:$configtxlator_pid"
    logr "Sleeping 5 seconds for configtxlator to start..."
    sleep 5

    pushd /tmp

    CTLURL=http://127.0.0.1:7059

    # 将配置区块protobuf转换为JSON
    curl -X POST --data-binary @$CONFIG_BLOCK_FILE $CTLURL/protolator/decode/common.Block > config_block.json

    # 从配置区块中提取配置，并输出到config.json
    jq .data.data[0].payload.data.config config_block.json > config.json

    # tr命令可以对来自标准输入的字符进行替换、压缩和删除。它可以将一组字符变成另一组字符，经常用来编写优美的单行命令，作用很强大。
    #   -d：delete，删除SET1中指定的所有字符，不转换
    #   echo "a12HJ13fdaADff" | tr -d "[a-z][A-Z]" -> 1213
    crl=$(cat $CORE_PEER_MSPCONFIGPATH/crls/crl*.pem | base64 | tr -d '\n')

    # 更新config.json中的crl，并输出到updated_config.json
    cat config.json | jq '.channel_group.groups.Application.groups.'"${ORG}"'.values.MSP.value.config.revocation_list = ["'"${crl}"'"]' > updated_config.json

    # Create the config diff protobuf
    curl -X POST --data-binary @config.json $CTLURL/protolator/encode/common.Config > config.pb
    curl -X POST --data-binary @updated_config.json $CTLURL/protolator/encode/common.Config > updated_config.pb
    curl -X POST -F original=@config.pb -F updated=@updated_config.pb $CTLURL/configtxlator/compute/update-from-configs -F channel=$CHANNEL_NAME > config_update.pb

    # Convert the config diff protobuf to JSON
    curl -X POST --data-binary @config_update.pb $CTLURL/protolator/decode/common.ConfigUpdate > config_update.json

    # Create envelope protobuf container config diff to be used in the "peer channel update" command to update the channel configuration block
    echo '{"payload":{"header":{"channel_header":{"channel_id":"'"${CHANNEL_NAME}"'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' > config_update_as_envelope.json
    curl -X POST --data-binary @config_update_as_envelope.json $CTLURL/protolator/encode/common.Envelope > $CONFIG_UPDATE_ENVELOPE_FILE

    # Stop configtxlator
    kill $configtxlator_pid

    popd
}

function updateConfigBlock {
   logr "Updating the configuration block of the channel '$CHANNEL_NAME'"
   peer channel update -f $CONFIG_UPDATE_ENVELOPE_FILE -c $CHANNEL_NAME $ORDERER_CONN_ARGS
}

# 查询链码失败时返回0，否则返回1
function queryAsRevokedUser {

    set +e

    logr "Querying the chaincode in the channel '$CHANNEL_NAME' on the peer '$PEER_HOST' as revoked user '$USER_NAME' ..."

    local starttime=$(date +%s)

    # Continue to poll until we get an expected response or reach QUERY_TIMEOUT
    while test "$(($(date +%s)-starttime))" -lt "$QUERY_TIMEOUT"; do
        sleep 1
        peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}' >& log.txt
        if [ $? -ne 0 ]; then
            err=$(cat log.txt | grep "access denied")
            if [ "$err" != "" ]; then
                logr "Expected error occurred when the revoked user '$USER_NAME' queried the chaincode in the channel '$CHANNEL_NAME'"
                set -e
                return 0
            fi
        fi
        echo -n "."
    done
    set -e
    cat log.txt
    cat log.txt >> $RUN_SUMFILE
    return 1
}

function logr {
   log $*
   log $* >> $RUN_SUMPATH
}

function fatalr {
   logr "FATAL: $*"
   exit 1
}

main
