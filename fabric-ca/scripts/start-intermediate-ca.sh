#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0
#

source $(dirname "$0")/env.sh

initOrgVars $ORG

set -e

# 等待根CA启动
# Usage: waitPort <what> <timeoutInSecs> <errorLogFile> <host> <port>
waitPort "root CA to start" 60 $ROOT_CA_LOGFILE $ROOT_CA_HOST 7054

# 初始化中间层CA
# -u 父fabric-ca-server服务地址
fabric-ca-server init -b $BOOTSTRAP_USER_PASS -u $PARENT_URL

# 将中间层CA的签名证书chain复制到data目录以供其他人使用
cp $FABRIC_CA_SERVER_HOME/ca-chain.pem $TARGET_CHAINFILE

# 添加组织结构配置
for o in $FABRIC_ORGS; do
   aff=$aff"\n   $o: []"
done
aff="${aff#\\n   }"
sed -i "/affiliations:/a \\   $aff" \
   $FABRIC_CA_SERVER_HOME/fabric-ca-server-config.yaml

# Start the intermediate CA
fabric-ca-server start