# 这是bash函数库，用于不同的scripts.sh

setOrdererGlobals() {
    # 所属组织MSP的ID
    CORE_PEER_LOCALMSPID="OrdererMSP"
    # orderer组织的tls根证书
    CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
    # orderer组织管理员用户的msp
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/users/Admin@example.com/msp
}

# setGlobals <peer> <org>
# the index of peer is from 0
# the index of org is from 1
setGlobals () {

    PEER=$1
	ORG=$2

    if [ $ORG -eq 1 ] ; then # Org1
        # 所属组织MSP的ID
        CORE_PEER_LOCALMSPID="Org1MSP"
        # Org1组织的tls根证书
        CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
        # Org1管理员用户的msp
		CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
		if [ $PEER -eq 0 ]; then
			CORE_PEER_ADDRESS=peer0.org1.example.com:7051
		else
			CORE_PEER_ADDRESS=peer1.org1.example.com:7051
		fi
    elif [ $ORG -eq 2 ] ; then
		CORE_PEER_LOCALMSPID="Org2MSP"
		CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
		CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
		if [ $PEER -eq 0 ]; then
			CORE_PEER_ADDRESS=peer0.org2.example.com:7051
		else
			CORE_PEER_ADDRESS=peer1.org2.example.com:7051
		fi

	elif [ $ORG -eq 3 ] ; then
		CORE_PEER_LOCALMSPID="Org3MSP"
		CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt
		CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
		if [ $PEER -eq 0 ]; then
			CORE_PEER_ADDRESS=peer0.org3.example.com:7051
		else
			CORE_PEER_ADDRESS=peer1.org3.example.com:7051
		fi
	else
		echo "================== ERROR !!! ORG Unknown =================="
	fi

	env |grep CORE
}

verifyResult () {

    if [ $1 -ne 0 ] ; then
        echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
        echo "========= ERROR !!! FAILED to execute End-2-End Scenario ==========="
        echo
        exit 1
    fi
}

# joinChannelWithRetry <peer> <org>
# 有时加入应用通道需要时间，因此至少重试5次
joinChannelWithRetry () {

    PEER=$1
	ORG=$2
	setGlobals $PEER $ORG

	set -x
	# 1. 之前创建应用通道的指令会在cli当前工作目录下生成一个CHANNEL_NAME.block区块，用于后续加入通道；
	# 2. 或者新加入组织，通过peer channel fetch获取要加入应用通道的初始区块
	peer channel join -b $CHANNEL_NAME.block  >&log.txt
	res=$?
    set +x
	cat log.txt

    if [ $res -ne 0  -a $COUNTER -lt $MAX_RETRY ]; then
        COUNTER=`expr $COUNTER + 1`
        echo "peer${PEER}.org${ORG} failed to join the channel, Retry after $DELAY seconds"
		sleep $DELAY
		joinChannelWithRetry $PEER $ORG
    else
		COUNTER=1
	fi

	verifyResult $res "After $MAX_RETRY attempts, peer${PEER}.org${ORG} has failed to Join the Channel"
}

updateAnchorPeers() {

    PEER=$1
    ORG=$2
    setGlobals $PEER $ORG

    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        set -x
		peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx >&log.txt
		res=$?
        set +x
    else
        set -x
        # 注：之前使用configtxgen工具生成锚节点更新交易文件
        peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
        res=$?
        set +x
    fi

    cat log.txt
	verifyResult $res "Anchor peer update failed"
	echo "===================== Anchor peers for org \"$CORE_PEER_LOCALMSPID\" on \"$CHANNEL_NAME\" is updated successfully ===================== "
	sleep $DELAY
	echo
}

installChaincode () {

    PEER=$1
	ORG=$2
	setGlobals $PEER $ORG

	VERSION=${3:-1.0}

    set -x
	peer chaincode install -n mycc -v ${VERSION} -l ${LANGUAGE} -p ${CC_SRC_PATH} >&log.txt
	res=$?
    set +x

    cat log.txt
	verifyResult $res "Chaincode installation on peer${PEER}.org${ORG} has Failed"
	echo "===================== Chaincode is installed on peer${PEER}.org${ORG} ===================== "
	echo
}

instantiateChaincode () {

    PEER=$1
	ORG=$2
	setGlobals $PEER $ORG

	VERSION=${3:-1.0}

	# 虽然'peer chaincode'命令可以从peer节点获取Orderer地址（如果peer成功加入应用通道），但是我们可以通过'-o'选项直接提供它
	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
	    set -x
		peer chaincode instantiate -o orderer.example.com:7050 -C $CHANNEL_NAME -n mycc -l ${LANGUAGE} -v ${VERSION} -c '{"Args":["init","a","100","b","200"]}' -P "OR	('Org1MSP.peer','Org2MSP.peer')" >&log.txt
		res=$?
        set +x
    else
        set -x
		peer chaincode instantiate -o orderer.example.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -l ${LANGUAGE} -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "OR	('Org1MSP.peer','Org2MSP.peer')" >&log.txt
		res=$?
        set +x
	fi

	cat log.txt
	verifyResult $res "Chaincode instantiation on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' failed"
	echo "===================== Chaincode Instantiation on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' is successful ===================== "
	echo
}

# 查询 a 账户余额
chaincodeQuery () {

    PEER=$1
    ORG=$2
    setGlobals $PEER $ORG

    EXPECTED_RESULT=$3

    echo "===================== Querying on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME'... ===================== "

    local rc=1
    local starttime=$(date +%s)

    # continue to poll
    # we either get a successful response, or reach TIMEOUT
    while test "$(($(date +%s)-starttime)))" -lt "$TIMEOUT" -a $rc -ne 0
    do
        sleep $DELAY
        echo "Attempting to Query peer${PEER}.org${ORG} ...$(($(date +%s)-starttime)) secs"
        set -x
        peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}' >&log.txt
        res=$?
        set +x

        # awk '{pattern + action}' {filenames}
        # $NF 列引用，$0代表整行所有数据，$1代表第一列。
        # NF是个代表总列数的系统变量，所以$NF代表最后一列，还支持$(NF-1)来表示倒数第二列。
        # 还支持列之间的运算，如$NF-$(NF-1)是最后两列的值相减。
        # 只写一个print 是 print $0的简写，打印整行所有数据。
        # i.e 2018-04-23 14:38:45.910 UTC [channelCmd] readBlock -> DEBU 00a Received block: 0
        test $res -eq 0 && VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')
        test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
    done

    echo
    cat log.txt
    if test $rc -eq 0 ; then
	    echo "===================== Query on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' is successful ===================== "
    else
        echo "!!!!!!!!!!!!!!! Query result on peer${PEER}.org${ORG} is INVALID !!!!!!!!!!!!!!!!"
        echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
        echo
        exit 1
    fi
}

# a 给 b 转账 10
chaincodeInvoke () {

    PEER=$1
	ORG=$2
	setGlobals $PEER $ORG

	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
	    set -x
		peer chaincode invoke -o orderer.example.com:7050 -C $CHANNEL_NAME -n mycc -c '{"Args":["invoke","a","b","10"]}' >&log.txt
		res=$?
        set +x
    else
        set -x
		peer chaincode invoke -o orderer.example.com:7050  --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -c '{"Args":["invoke","a","b","10"]}' >&log.txt
		res=$?
        set +x
	fi

	cat log.txt
	verifyResult $res "Invoke execution on peer${PEER}.org${ORG} failed "
	echo "===================== Invoke transaction on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' is successful ===================== "
	echo
}

# fetchChannelConfig <channel_id> <output_json>
# 获取给定channel的配置区块，解码为json，并使用jq工具提取其中的完整的通道配置信息部分（.data.data[0].payload.data.config）保存到config.json文件中
fetchChannelConfig() {

    CHANNEL=$1
    OUTPUT=$2

    setOrdererGlobals

    # 获取指定channel的配置区块
    echo "Fetching the most recent configuration block for the channel"
    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        set -x
        peer channel fetch config config_block.pb -o orderer.example.com:7050 -c $CHANNEL
        set +x
    else
        set -x
        peer channel fetch config config_block.pb -o orderer.example.com:7050 -c $CHANNEL --tls --cafile $ORDERER_CA
        set +x
    fi

    echo "Decoding config block to JSON and isolating config to ${OUTPUT}"
    set -x
    configtxlator proto_decode --input config_block.pb --type common.Block | jq .data.data[0].payload.data.config > "${OUTPUT}"
    set +x
}

# createConfigUpdate <channel_id> <original_config.json> <modified_config.json> <output.pb>
# 使用原始的和修改的配置，来生成配置更新交易文件
createConfigUpdate() {

    CHANNEL=$1 # 通道
    ORIGINAL=$2 # 原通道配置json文件
    MODIFIED=$3 # 修改的通道配置json文件
    OUTPUT=$4 # 最终输出的配置更新交易文件

    set -x
    # 将通道配置json文件编码生成类型为common.Config的配置文件
    configtxlator proto_encode --input "${ORIGINAL}" --type common.Config > original_config.pb
    configtxlator proto_encode --input "${MODIFIED}" --type common.Config > modified_config.pb
    # 计算配置更新量，输出类型为common.ConfigUpdate的配置更新文件
    configtxlator compute_update --channel_id "${CHANNEL}" --original original_config.pb --updated modified_config.pb > config_update.pb
    # 将类型为common.ConfigUpdate的配置更新文件解码为json文件
    configtxlator proto_decode --input config_update.pb  --type common.ConfigUpdate > config_update.json
    # 将上述common.ConfigUpdate结构数据补全，编码生成类型为common.Envelope的配置更新交易文件
    echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . > config_update_in_envelope.json
    configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope > "${OUTPUT}"
    set +x
}

# signConfigtxAsPeerOrg <org> <configtx.pb>
# 使用指定peer组织的管理员身份对配置更新交易文件签名
signConfigtxAsPeerOrg() {
    PEERORG=$1 # 组织
    TX=$2 # 配置更新交易文件
    # setGlobals <peer> <org>
    setGlobals 0 $PEERORG
    set -x
    peer channel signconfigtx -f "${TX}"
    set +x
}

upgradeChaincode () {

    PEER=$1
    ORG=$2
    setGlobals $PEER $ORG

    set -x
    peer chaincode upgrade -o orderer.example.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -v 2.0 -c '{"Args":["init","a","90","b","210"]}' -P "OR ('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')"
    res=$?
	set +x

	cat log.txt
    verifyResult $res "Chaincode upgrade on org${ORG} peer${PEER} has Failed"
    echo "===================== Chaincode is upgraded on org${ORG} peer${PEER} ===================== "
    echo
}
