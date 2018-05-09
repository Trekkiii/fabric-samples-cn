#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0

set -e

source $(dirname "$0")/env.sh

# 等待setup容器成功完成所有操作
awaitSetup

# 登记orderer节点的tls证书
# 使用orderer节点身份登记，以获取orderer的TLS证书，并保存在/tmp/tls目录下(使用 "tls" profile)
fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $ORDERER_HOST

# 将TLS私钥和证书拷贝到/etc/hyperledger/orderer/tls目录下
TLSDIR=$ORDERER_HOME/tls
mkdir -p $TLSDIR
cp /tmp/tls/keystore/* $ORDERER_GENERAL_TLS_PRIVATEKEY # /etc/hyperledger/orderer/tls/server.key
cp /tmp/tls/signcerts/* $ORDERER_GENERAL_TLS_CERTIFICATE # /etc/hyperledger/orderer/tls/server.crt
rm -rf /tmp/tls

# ORDERER_GENERAL_LOCALMSPDIR：/etc/hyperledger/orderer/msp

# 使用orderer节点身份登记，以再次获取orderer的证书，并保存在/etc/hyperledger/orderer/msp目录下(使用默认 profile)
fabric-ca-client enroll -d -u $ENROLLMENT_URL -M $ORDERER_GENERAL_LOCALMSPDIR

# Finish setting up the local MSP for the orderer
finishMSPSetup $ORDERER_GENERAL_LOCALMSPDIR
copyAdminCert $ORDERER_GENERAL_LOCALMSPDIR

# 等待创世区块生成
dowait "genesis block to be created" 60 $SETUP_LOGFILE $ORDERER_GENERAL_GENESISFILE

# 启动orderer
env | grep ORDERER
orderer