#!/bin/bash

cat << EOF
 ____    _____      _      ____    _____
/ ___|  |_   _|    / \    |  _ \  |_   _|
\___ \    | |     / _ \   | |_) |   | |
 ___) |   | |    / ___ \  |  _ <    | |
|____/    |_|   /_/   \_\ |_| \_\   |_|

Upgrade your first network (BYFN) from v1.0.x to v1.1 end-to-end test

EOF

CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
TIMEOUT="$4"
: ${CHANNEL_NAME:="mychannel"}
: ${DELAY:="5"}
: ${LANGUAGE:="golang"}
: ${TIMEOUT:="10"}
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
COUNTER=1
MAX_RETRY=5
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

CC_SRC_PATH="github.com/chaincode/go/chaincode_example02/"
if [ "$LANGUAGE" = "node" ]; then
	CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/node/chaincode_example02/"
fi

echo "Channel name : "$CHANNEL_NAME

# import utils
. scripts/utils.sh

# addCapabilityToChannel <channel_id> <capabilities_group>
# 获取当前的通道配置，用指定group的capabilities修改它，计算配置更新，签名并提交。
addCapabilityToChannel() {

    CH_NAME=$1 # channel（系统通道、应用通道）
    GROUP=$2 # capabilities group

    setOrdererGlobals

    # 获取给定channel的配置区块，解码为json，并使用jq工具提取其中的完整的通道配置信息部分（.data.data[0].payload.data.config）保存到config.json文件中
    fetchChannelConfig $CH_NAME config.json

    # 根据capabilities group修改配置的相应部分
    # TODO usage of jq
    if [ $GROUP == "orderer" ]; then
        jq -s '.[0] * {"channel_group":{"groups":{"Orderer": {"values": {"Capabilities": .[1]}}}}}' config.json ./scripts/capabilities.json > modified_config.json
    elif [ $GROUP == "channel" ]; then
        jq -s '.[0] * {"channel_group":{"values": {"Capabilities": .[1]}}}' config.json ./scripts/capabilities.json > modified_config.json
    elif [ $GROUP == "application" ]; then
        jq -s '.[0] * {"channel_group":{"groups":{"Application": {"values": {"Capabilities": .[1]}}}}}' config.json ./scripts/capabilities.json > modified_config.json
    fi

    # 基于config.json和modified_config.json文件的不同，为此channel创建配置更新文件config_update.pb（类型为common.ConfigUpdate）
    # 将config_update.pb写入到config_update_in_envelope.pb（类型为common.Envelope）
    createConfigUpdate "$CH_NAME" config.json modified_config.json config_update_in_envelope.pb

    # 签名并设置提交的身份
    if [ $CH_NAME != "testchainid" ] ; then
        if [ $GROUP == "orderer" ]; then
            # 修改orderer group，仅需要Orderer管理员签名

            # Prepare to sign the update as the OrdererOrg.Admin
            setOrdererGlobals
        elif [ $GROUP == "channel" ]; then
            # 修改channel group，需要大部分的application管理员和orderer管理员签名

            # 使用PeerOrg1.Admin对配置更新交易文件签名
            signConfigtxAsPeerOrg 1 config_update_in_envelope.pb
            # 使用PeerOrg2.Admin对配置更新交易文件签名
            signConfigtxAsPeerOrg 2 config_update_in_envelope.pb

            # Prepare to sign the update as the OrdererOrg.Admin
            setOrdererGlobals
        elif [ $GROUP == "application" ]; then
            # 修改application group，需要大部分的application管理员来签名

            # 使用PeerOrg1.Admin对配置更新交易文件签名
            signConfigtxAsPeerOrg 1 config_update_in_envelope.pb

            # Prepare to sign the update as the PeerOrg2.Admin
            setGlobals 0 2
        fi
    else
        # 对于orderer系统通道，仅需要orderer管理员签名
        # 其将在执行更新（update）操作时附加
        setOrdererGlobals
    fi

    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        set -x
        peer channel update -f config_update_in_envelope.pb -c $CH_NAME -o orderer.example.com:7050
        res=$?
        set +x
    else
        set -x
        peer channel update -f config_update_in_envelope.pb -c $CH_NAME -o orderer.example.com:7050 --tls true --cafile $ORDERER_CA
        res=$?
        set +x
    fi
    verifyResult $res "Config update for \"$GROUP\" on \"$CH_NAME\" failed"
    echo "===================== Config update for \"$GROUP\" on \"$CH_NAME\" is completed ===================== "
}

echo "Installing jq"
apt-get update
# 使用-y选项会在安装过程中使用默认设置，如果默认设置为N，那么就会选择N，而不会选择y。并没有让apt-get一直选择y的选项。
apt-get install -y jq

sleep $DELAY

# Config update for /Channel/Orderer on testchainid
echo "Config update for /Channel/Orderer on testchainid"
addCapabilityToChannel testchainid orderer

sleep $DELAY

# Config update for /Channel on testchainid
echo "Config update for /Channel on testchainid"
addCapabilityToChannel testchainid channel

sleep $DELAY

# Config update for /Channel/Orderer
echo "Config update for /Channel/Orderer on \"$CHANNEL_NAME\""
addCapabilityToChannel $CHANNEL_NAME orderer

sleep $DELAY

# Config update for /Channel/Application
echo "Config update for /Channel/Application on \"$CHANNEL_NAME\""
addCapabilityToChannel $CHANNEL_NAME application

sleep $DELAY

# Config update for /Channel
echo "Config update for /Channel on \"$CHANNEL_NAME\""
addCapabilityToChannel $CHANNEL_NAME channel

# 查询 a 账户余额，预期为 90
# Query on chaincode on Peer0/Org1
echo "Querying chaincode on org1/peer0..."
chaincodeQuery 0 1 90

# a 给 b 转账 10
# Invoke on chaincode on Peer0/Org1
echo "Sending invoke transaction on org1/peer0..."
chaincodeInvoke 0 1

sleep $DELAY

# 查询 a 账户余额，预期为 80
# Query on chaincode on Peer0/Org1
echo "Querying chaincode on org1/peer0..."
chaincodeQuery 0 1 80

# a 给 b 转账 10
# Invoke on chaincode on Peer0/Org2
echo "Sending invoke transaction on org2/peer0..."
chaincodeInvoke 0 2

sleep $DELAY

# 查询 a 账户余额，预期为 70
# Query on chaincode on Peer0/Org2
echo "Querying chaincode on org2/peer0..."
chaincodeQuery 0 2 70

cat << EOF

===================== All GOOD, End-2-End UPGRADE Scenario execution completed =====================

 _____   _   _   ____            _____   ____    _____
| ____| | \ | | |  _ \          | ____| |___ \  | ____|
|  _|   |  \| | | | | |  _____  |  _|     __) | |  _|
| |___  | |\  | | |_| | |_____| | |___   / __/  | |___
|_____| |_| \_| |____/          |_____| |_____| |_____|

EOF

exit 0
