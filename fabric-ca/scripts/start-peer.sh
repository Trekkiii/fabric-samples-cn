#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0
#

set -e

source $(dirname "$0")/env.sh

awaitSetup

# Although a peer may use the same TLS key and certificate file for both inbound and outbound TLS,
# we generate a different key and certificate for inbound and outbound TLS simply to show that it is permissible

# Generate server TLS cert and key pair for the peer
# 登记peer节点的tls证书
# 使用peer节点身份登记，以获取peer的TLS证书，并保存在/tmp/tls目录下(使用 "tls" profile)
fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $PEER_HOST
# 将TLS私钥和证书拷贝到/opt/gopath/src/github.com/hyperledger/fabric/peer/tls目录下
TLSDIR=$PEER_HOME/tls
mkdir -p $TLSDIR
cp /tmp/tls/signcerts/* $CORE_PEER_TLS_CERT_FILE
cp /tmp/tls/keystore/* $CORE_PEER_TLS_KEY_FILE
rm -rf /tmp/tls

# Generate client TLS cert and key pair for the peer
# CORE_PEER_TLS_CLIENTCERT_FILE=/$DATA/tls/$PEER_NAME-client.crt
# CORE_PEER_TLS_CLIENTKEY_FILE=/$DATA/tls/$PEER_NAME-client.key
genClientTLSCert $PEER_NAME $CORE_PEER_TLS_CLIENTCERT_FILE $CORE_PEER_TLS_CLIENTKEY_FILE

# Generate client TLS cert and key pair for the peer CLI
# /$DATA/tls/$PEER_NAME-cli-client.crt
# /$DATA/tls/$PEER_NAME-cli-client.key
genClientTLSCert $PEER_NAME /$DATA/tls/$PEER_NAME-cli-client.crt /$DATA/tls/$PEER_NAME-cli-client.key

# Enroll the peer to get an enrollment certificate and set up the core's local MSP directory
fabric-ca-client enroll -d -u $ENROLLMENT_URL -M $CORE_PEER_MSPCONFIGPATH
finishMSPSetup $CORE_PEER_MSPCONFIGPATH
copyAdminCert $CORE_PEER_MSPCONFIGPATH

# Start the peer
log "Starting peer '$CORE_PEER_ID' with MSP at '$CORE_PEER_MSPCONFIGPATH'"
env | grep CORE
peer node start