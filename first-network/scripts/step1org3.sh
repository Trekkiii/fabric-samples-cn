#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

# 这个脚本被设计成在cli容器中运行，它作为EYFN教程的第一步。
# 它创建并提交配置交易文件，以将org3添加到以前在BYFN教程中设置的网络中。

CHANNEL_NAME="$1" # 应用通道名称，默认为"mychannel"
DELAY="$2" # 命令之间延迟的默认值
LANGUAGE="$3" # 使用golang作为链码的开发语言
TIMEOUT="$4" # 超时时间 - CLI在放弃之前应该等待来自另一个容器的响应的等待时间，单位s
: ${CHANNEL_NAME:="mychannel"}
: ${DELAY:="3"}
: ${LANGUAGE:="golang"}
: ${TIMEOUT:="10"}
# tr [OPTION]... SET1 [SET2]，将SET1中字符用SET2对应位置的字符进行替换，一般缺省为-t
# tr -t [:upper:] [:lower:]，将大写转为小写
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
COUNTER=1
MAX_RETRY=5
# orderer tls根证书
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

# 链码路径
CC_SRC_PATH="github.com/chaincode/go/chaincode_example02/"
if [ "$LANGUAGE" = "node" ]; then
	CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/node/chaincode_example02/"
fi

# import utils
. scripts/utils.sh

echo
echo "========= Creating config transaction to add org3 to network =========== "
echo

echo "Installing jq"
# 使用-y选项会在安装过程中使用默认设置，如果默认设置为N，那么就会选择N，而不会选择y。并没有让apt-get一直选择y的选项。
apt-get -y update && apt-get -y install jq

# 获取给定channel的配置区块，解码为json，并使用jq工具提取其中的完整的通道配置信息部分（.data.data[0].payload.data.config）保存到config.json文件中
fetchChannelConfig ${CHANNEL_NAME} config.json

# 修改配置添加新的组织
# config.json：原Org1和Org2组织配置；channel-artifacts/org3.json：Org3组织配置
set -x
# 在generateChannelArtifacts一步中，org3.json保存在./channel-artifacts目录下
# cli容器通过volumes将./channel-artifacts目录挂载到了/opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts目录
# 并通过working_dir设置工作目录为/opt/gopath/src/github.com/hyperledger/fabric/peer目录
jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"Org3MSP":.[1]}}}}}' config.json ./channel-artifacts/org3.json > modified_config.json
set +x

# 根据config.json和modified_config.json之间的差异计算配置更新，将其作为交易写入org3_update_in_envelope.pb
createConfigUpdate ${CHANNEL_NAME} config.json modified_config.json org3_update_in_envelope.pb

echo
echo "========= Config transaction to add org3 to network created ===== "
echo

echo "Signing config transaction"
echo
# 使用Org1组织管理员签名
signConfigtxAsPeerOrg 1 org3_update_in_envelope.pb

echo
echo "========= Submitting transaction from a different peer (peer0.org2) which also signs it ========= "
echo
setGlobals 0 2 # 使用Org2组织管理员签名
set -x
peer channel update -f org3_update_in_envelope.pb -c ${CHANNEL_NAME} -o orderer.example.com:7050 --tls --cafile ${ORDERER_CA}
set +x

echo
echo "========= Config transaction to add org3 to network submitted! =========== "
echo

exit 0