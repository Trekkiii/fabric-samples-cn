#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

# 这个脚本被设计成在cli容器中运行，它作为EYFN教程的第三步。
# 将chaincode作为2.0版本安装在peer0.org1和peer0.org2上，并将通道上的chaincode升级到2.0版本
# 从而完成了将org3添加到以前在BYFN教程中设置的网络的步骤。

echo
echo "========= Finish adding Org3 to your first network ========= "
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

echo "===================== Installing chaincode 2.0 on peer0.org1 ===================== "
installChaincode 0 1 2.0
echo "===================== Installing chaincode 2.0 on peer0.org2 ===================== "
installChaincode 0 2 2.0

echo "===================== Upgrading chaincode on peer0.org1 ===================== "
upgradeChaincode 0 1

echo
echo "========= Finished adding Org3 to your first network! ========= "
echo

exit 0