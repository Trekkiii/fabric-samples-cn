#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

cat << EOF
      __                              __       _          _               _          _ _
     / _|_ __  _ __   __ _  ___      / _| __ _| |__  _ __(_) ___      ___| |__   ___| | |
    | |_| '_ \| '_ \ / _  |/ __|____| |_ / _  | '_ \| '__| |/ __|____/ __| '_ \ / _ \ | |
    |  _| | | | |_) | (_| | (_|_____|  _| (_| | |_) | |  | | (_|_____\__ \ | | |  __/ | |
    |_| |_| |_| .__/ \__,_|\___|    |_|  \__,_|_.__/|_|  |_|\___|    |___/_| |_|\___|_|_|
              |_|
EOF

CHANNEL_NAME="$1" # 应用通道名称
: ${CHANNEL_NAME:="mychannel"}

: ${TIMEOUT:="60"} # 超时

COUNTER=1 # 节点加入应用通道的尝试次数
MAX_RETRY=5 # 节点加入应用通道的最大尝试次数

# Orderer TLS CA根证书，同 ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

echo "Channel name : "$CHANNEL_NAME

verifyResult () {

    if [ $1 -ne 0 ] ; then
        echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
        echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
        echo
        exit 1
    fi
}

checkOSNAvailability() {

    # 使用orderer的MSP来获取系统通道配置块
    CORE_PEER_LOCALMSPID="OrdererMSP"
    CORE_PEER_TLS_ROOTCERT_FILE=$ORDERER_CA
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp # TODO 是否可使用orderer Admin's msp？

    local rc=1 # 标记获取创世区块是否成功，如果为0，则成功
    local starttime=$(date +%s) # 下面循环逻辑的开始时间，单位s

    # continue to poll
    # 我们要么得到一个成功的回复，要么超时
    while test "$(($(date +%s)-starttime))" -lt "$TIMEOUT" -a $rc -ne 0
    do
        sleep 3
        echo "Attempting to fetch system channel 'testchainid' ...$(($(date +%s)-starttime)) secs"

        if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
            peer channel fetch 0 -o orderer.example.com:7050 -c "testchainid" >&log.txt
        else
            # 保存为 0_block.pb 文件
            peer channel fetch 0 0_block.pb -o orderer.example.com:7050 -c "testchainid" --tls --cafile $ORDERER_CA >&log.txt
        fi

        # awk '{pattern + action}' {filenames}
        # $NF 列引用，$0代表整行所有数据，$1代表第一列。
        # NF是个代表总列数的系统变量，所以$NF代表最后一列，还支持$(NF-1)来表示倒数第二列。
        # 还支持列之间的运算，如$NF-$(NF-1)是最后两列的值相减。
        # 只写一个print 是 print $0的简写，打印整行所有数据。
        # i.e 2018-04-23 14:38:45.910 UTC [channelCmd] readBlock -> DEBU 00a Received block: 0
        test $? -eq 0 && VALUE=$(cat log.txt | awk '/Received block/ {print $NF}')
        test "$VALUE" = "0" && let rc=0

    done

    cat log.txt
    verifyResult $rc "Ordering Service is not available, Please try again ..."
    echo "===================== Ordering Service is up and running ===================== "
    echo
}

setGlobals () {

    # 传参为 0 或 1
    if [ $1 -eq 0 -o $1 -eq 1 ] ; then
        CORE_PEER_LOCALMSPID="Org1MSP"
        CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
        CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
        if [ $1 -eq 0 ]; then
            CORE_PEER_ADDRESS=peer0.org1.example.com:7051
        else
            CORE_PEER_ADDRESS=peer1.org1.example.com:7051
        fi
    else
        CORE_PEER_LOCALMSPID="Org2MSP"
        CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
        CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
        if [ $1 -eq 2 ]; then
            CORE_PEER_ADDRESS=peer0.org2.example.com:7051
        else
            CORE_PEER_ADDRESS=peer1.org2.example.com:7051
        fi
    fi

    env |grep CORE
}

createChannel() {

    # 设置peer0节点连接属性
    # 通过peer0节点创建应用通道
    setGlobals 0

    # cli节点通过 /bin/bash -c './scripts/script.sh ${CHANNEL_NAME}; sleep $TIMEOUT' 执行该脚本，所以当前路径为 e2e_cli/
    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx >&log.txt
    else
		peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx --tls --cafile $ORDERER_CA >&log.txt
	fi

    res=$?
	cat log.txt

	verifyResult $res "Channel creation failed"
	echo "===================== Channel \"$CHANNEL_NAME\" is created successfully ===================== "
	echo
}

# Sometimes Join takes time hence RETRY atleast for 5 times
joinWithRetry () {

    peer channel join -b $CHANNEL_NAME.block  >&log.txt

    res=$?
	cat log.txt

	if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
	    COUNTER=`expr $COUNTER + 1`
	    echo "PEER$1 failed to join the channel, Retry after 2 seconds"
		sleep 2
		joinWithRetry $1
    else
		COUNTER=1
    fi

    verifyResult $res "After $MAX_RETRY attempts, PEER$ch has failed to Join the Channel"
}

joinChannel () {

    for ch in 0 1 2 3
    do
        # 设置当前节点的连接属性
        setGlobals $ch
        joinWithRetry $ch
        echo "===================== PEER$ch joined on the channel \"$CHANNEL_NAME\" ===================== "
		sleep 2
		echo
	done
}

updateAnchorPeers() {

    PEER=$1
    setGlobals $PEER

    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx >&log.txt
	else
		peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls --cafile $ORDERER_CA >&log.txt
	fi

	res=$?
	cat log.txt

	verifyResult $res "Anchor peer update failed"

	echo "===================== Anchor peers for org \"$CORE_PEER_LOCALMSPID\" on \"$CHANNEL_NAME\" is updated successfully ===================== "
	sleep 5
	echo
}

installChaincode () {

    PEER=$1
	setGlobals $PEER

    # 这里要注意下链码的路径
    peer chaincode install -n mycc -v 1.0 -p github.com/hyperledger/fabric/examples/chaincode/go/chaincode_example02 >&log.txt

    res=$?
	cat log.txt
    verifyResult $res "Chaincode installation on remote peer PEER$PEER has Failed"
	echo "===================== Chaincode is installed on remote peer PEER$PEER ===================== "
	echo
}

instantiateChaincode () {

    PEER=$1
	setGlobals $PEER

    # while 'peer chaincode' command can get the orderer endpoint from the peer (if join was successful),
	# lets supply it directly as we know it using the "-o" option
    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer chaincode instantiate -o orderer.example.com:7050 -C $CHANNEL_NAME -n mycc -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "OR ('Org1MSP.peer','Org2MSP.peer')" >&log.txt
	else
		peer chaincode instantiate -o orderer.example.com:7050 --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "OR	('Org1MSP.peer','Org2MSP.peer')" >&log.txt
	fi

	res=$?
	cat log.txt
	verifyResult $res "Chaincode instantiation on PEER$PEER on channel '$CHANNEL_NAME' failed"
	echo "===================== Chaincode Instantiation on PEER$PEER on channel '$CHANNEL_NAME' is successful ===================== "
	echo
}

chaincodeQuery () {

    PEER=$1
    echo "===================== Querying on PEER$PEER on channel '$CHANNEL_NAME'... ===================== "
    setGlobals $PEER

    local rc=1
    local starttime=$(date +%s) # 下面循环逻辑的开始时间，单位s

    # continue to poll
    # 我们要么得到一个成功的回复，要么超时
    while test "$(($(date +%s)-starttime))" -lt "$TIMEOUT" -a $rc -ne 0
    do
        sleep 3
        echo "Attempting to Query PEER$PEER ...$(($(date +%s)-starttime)) secs"

        peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}' >&log.txt

        # i.e Query Result: 100
        test $? -eq 0 && VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')

        test "$VALUE" = "$2" && let rc=0
    done

    echo
    cat log.txt

    if test $rc -eq 0 ; then
        echo "===================== Query on PEER$PEER on channel '$CHANNEL_NAME' is successful ===================== "
    else
        echo "!!!!!!!!!!!!!!! Query result on PEER$PEER is INVALID !!!!!!!!!!!!!!!!"
        echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
        echo
        exit 1
    fi
}

chaincodeInvoke () {

    PEER=$1
	setGlobals $PEER

	# while 'peer chaincode' command can get the orderer endpoint from the peer (if join was successful),
	# lets supply it directly as we know it using the "-o" option
	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer chaincode invoke -o orderer.example.com:7050 -C $CHANNEL_NAME -n mycc -c '{"Args":["invoke","a","b","10"]}' >&log.txt
	else
		peer chaincode invoke -o orderer.example.com:7050  --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -c '{"Args":["invoke","a","b","10"]}' >&log.txt
	fi

	res=$?
	cat log.txt
	verifyResult $res "Invoke execution on PEER$PEER failed "
	echo "===================== Invoke transaction on PEER$PEER on channel '$CHANNEL_NAME' is successful ===================== "
	echo
}

## 检查orderering服务是否可用
echo "Check orderering service availability..."
checkOSNAvailability

## 创建应用通道
echo "Creating channel..."
createChannel

## 将所有节点加入创建的应用通道
echo "Having all peers join the channel..."
joinChannel

## 为应用通道中的每一个组织设置锚节点
echo "Updating anchor peers for org1..."
updateAnchorPeers 0
echo "Updating anchor peers for org2..."
updateAnchorPeers 2

## 在 Peer0/Org1、Peer1/Org1、Peer0/Org2、Peer1/Org2 节点上安装链码
echo "Installing chaincode on org1/peer0..."
installChaincode 0
echo "Installing chaincode on org1/peer1..."
installChaincode 1
echo "Install chaincode on org2/peer0..."
installChaincode 2
echo "Install chaincode on org2/peer1..."
installChaincode 3

# 在 Peer0/Org2 节点上实例化链码
echo "Instantiating chaincode on org2/peer0..."
instantiateChaincode 2

# 在Peer0/Org1节点上查询链码，并校验查询结果是否等于实例化链码时指定的值。如果不等于则结束程序
echo "Querying chaincode on org1/peer0..."
chaincodeQuery 0 100

# 在Peer0/Org1节点上调用链码
echo "Sending invoke transaction on org1/peer0..."
chaincodeInvoke 0

# 在Peer0/Org2节点上查询链码，并校验查询结果是否等于90
echo "Querying chaincode on org2/peer0..."
chaincodeQuery 3 90

echo
echo "===================== All GOOD, End-2-End execution completed ===================== "
echo

echo
echo " _____   _   _   ____            _____   ____    _____ "
echo "| ____| | \ | | |  _ \          | ____| |___ \  | ____|"
echo "|  _|   |  \| | | | | |  _____  |  _|     __) | |  _|  "
echo "| |___  | |\  | | |_| | |_____| | |___   / __/  | |___ "
echo "|_____| |_| \_| |____/          |_____| |_____| |_____|"
echo

exit 0