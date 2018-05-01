#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

# 这个脚本被设计成在org3cli容器中运行，它作为EYFN教程的最后一步。
# 它只是通过org3 peers发出几个chaincode请求来检查org3是否已正确添加到以前在BYFN教程中设置的网络中。

cat << EOF
 ____    _____      _      ____    _____
/ ___|  |_   _|    / \    |  _ \  |_   _|
\___ \    | |     / _ \   | |_) |   | |
 ___) |   | |    / ___ \  |  _ <    | |
|____/    |_|   /_/   \_\ |_| \_\   |_|

Extend your first network (EYFN) test

EOF

CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
TIMEOUT="$4"
: ${CHANNEL_NAME:="mychannel"}
: ${TIMEOUT:="10"}
: ${LANGUAGE:="golang"}
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
COUNTER=1
MAX_RETRY=5
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

CC_SRC_PATH="github.com/chaincode/go/chaincode_example02/"
if [ "$LANGUAGE" = "node" ]; then
	CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/node/chaincode_example02/"
fi

echo "Channel name : "$CHANNEL_NAME

# import functions
. scripts/utils.sh

chaincodeQuery 0 3 90
chaincodeInvoke 0 3
chaincodeQuery 0 3 80

echo
echo "========= All GOOD, EYFN test execution completed =========== "
echo

cat << EOF

 _____   _   _   ____
| ____| | \ | | |  _ \
|  _|   |  \| | | | | |
| |___  | |\  | | |_| |
|_____| |_| \_| |____/

EOF

exit 0