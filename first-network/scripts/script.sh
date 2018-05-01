#!/bin/bash

cat << EOF
     ____    _____      _      ____    _____
    / ___|  |_   _|    / \    |  _ \  |_   _|
    \___ \    | |     / _ \   | |_) |   | |
     ___) |   | |    / ___ \  |  _ <    | |
    |____/    |_|   /_/   \_\ |_| \_\   |_|

    Build your first network (BYFN) end-to-end test
EOF

CHANNEL_NAME="$1" # 应用通道名称，默认为"mychannel"
DELAY="$2" # 命令之间延迟的默认值
LANGUAGE="$3" # 使用golang作为链码的开发语言
TIMEOUT="$4" # CLI在放弃之前应该等待来自另一个容器的响应的等待时间，单位s

: ${CHANNEL_NAME:="mychannel"}
: ${DELAY:="3"}
: ${LANGUAGE:="golang"}
: ${TIMEOUT:="10"}

# tr [OPTION]... SET1 [SET2]，将SET1中字符用SET2对应位置的字符进行替换，一般缺省为-t
# tr -t [:upper:] [:lower:]，将大写转为小写
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`

# 用于peer加入应用通道的重试控制
COUNTER=1
MAX_RETRY=5

# orderer tls根证书
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

# 链码路径
CC_SRC_PATH="github.com/chaincode/go/chaincode_example02/"
if [ "$LANGUAGE" = "node" ]; then
	CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/node/chaincode_example02/"
fi

echo "Channel name : "$CHANNEL_NAME

# import utils
. scripts/utils.sh

createChannel() {

    setGlobals 0 1

    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        set -x
        peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx >&log.txt
        res=$?
        set +x
    else
        set -x
        peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
        res=$?
        set +x
    fi

    cat log.txt
	verifyResult $res "Channel creation failed"
	echo "===================== Channel \"$CHANNEL_NAME\" is created successfully ===================== "
	echo
}

joinChannel () {

    for org in 1 2; do
        for peer in 0 1; do
            joinChannelWithRetry $peer $org
            echo "===================== peer${peer}.org${org} joined on the channel \"$CHANNEL_NAME\" ===================== "
            sleep $DELAY
    		echo
	    done
	done
}

# 创建应用通道
echo "Creating channel..."
createChannel

## 将所有的peer加入应用通道
echo "Having all peers join the channel..."
joinChannel

## 设置应用通道中的每个组织的锚节点
echo "Updating anchor peers for org1..."
updateAnchorPeers 0 1
echo "Updating anchor peers for org2..."
updateAnchorPeers 0 2

## peer0.org1 、peer1.org1 、 peer0.org2、peer1.org2节点上安装链码
echo "Installing chaincode on peer0.org1..."
installChaincode 0 1
echo "Installing chaincode on peer1.org1..."
installChaincode 1 1
echo "Installing chaincode on peer0.org2..."
installChaincode 0 2
echo "Installing chaincode on peer1.org2..."
installChaincode 1 2

# peer0.org2节点上实例化链码
echo "Instantiating chaincode on peer0.org2..."
instantiateChaincode 0 2

# peer0.org1上查询链码
echo "Querying chaincode on peer0.org1..."
chaincodeQuery 0 1 100

# peer0.org1节点上调用链码
echo "Sending invoke transaction on peer0.org1..."
chaincodeInvoke 0 1

# Query on chaincode on peer1.org2, check if the result is 90
echo "Querying chaincode on peer1.org2..."
chaincodeQuery 1 2 90

cat << EOF
========= All GOOD, BYFN execution completed ===========

 _____   _   _   ____
| ____| | \ | | |  _ \
|  _|   |  \| | | | | |
| |___  | |\  | | |_| |
|_____| |_| \_| |____/

EOF

exit 0