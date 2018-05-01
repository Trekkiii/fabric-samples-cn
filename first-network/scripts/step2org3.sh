#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

# 这个脚本被设计成在Org3cli容器中运行，它作为EYFN教程的第二步。
# 它将org3 peers加入先前在BYFN教程中创建的应用通道，并在peer0.org3上将chaincode安装为2.0版本。

echo
echo "========= Getting Org3 on to your first network ========= "
echo

CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
TIMEOUT="$4"
: ${CHANNEL_NAME:="mychannel"}
: ${DELAY:="3"}
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

# import utils
. scripts/utils.sh

echo "Fetching channel config block from orderer..."
set -x
peer channel fetch 0 $CHANNEL_NAME.block -o orderer.example.com:7050 -c $CHANNEL_NAME --tls --cafile $ORDERER_CA >&log.txt
res=$?
set +x
cat log.txt
verifyResult $res "Fetching config block from orderer has Failed"

echo "===================== Having peer0.org3 join the channel ===================== "
joinChannelWithRetry 0 3
echo "===================== peer0.org3 joined the channel \"$CHANNEL_NAME\" ===================== "
echo "===================== Having peer1.org3 join the channel ===================== "
joinChannelWithRetry 1 3
echo "===================== peer1.org3 joined the channel \"$CHANNEL_NAME\" ===================== "

echo "Installing chaincode 2.0 on peer0.org3..."
installChaincode 0 3 2.0

echo
echo "========= Got Org3 halfway onto your first network ========= "
echo

exit 0