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

COUNTER=1
MAX_RETRY=5

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

        # 列引用
        # $0代表整行所有数据，$1代表第一列。
        # NF是个代表总列数的系统变量，所以$NF代表最后一列，还支持$(NF-1)来表示倒数第二列。
        # 还支持列之间的运算，如$NF-$(NF-1)是最后两列的值相减。
        # 只写一个print 是 print $0的简写，打印整行所有数据。
        # eg, 2018-04-23 14:38:45.910 UTC [channelCmd] readBlock -> DEBU 00a Received block: 0
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

    # 设置peer节点连接属性
    setGlobals 0

    # TODO
}


## 检查orderering服务是否可用
echo "Check orderering service availability..."
checkOSNAvailability

## 创建应用通道
echo "Creating channel..."
createChannel