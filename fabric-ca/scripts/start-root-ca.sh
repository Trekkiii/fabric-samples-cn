#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0
#

set -e

# 初始化根CA
fabric-ca-server init -b $BOOTSTRAP_USER_PASS

# 将根CA的签名证书复制到data目录以供其他人使用
cp $FABRIC_CA_SERVER_HOME/ca-cert.pem $TARGET_CERTFILE

# 添加组织结构配置
for o in $FABRIC_ORGS; do
   aff=$aff"\n   $o: []"
done
aff="${aff#\\n   }" # 注意对\n转义

# sed   -i：直接修改读取的文件内容，而不是输出到终端
#       a：新增，a 的后面可以接字串，而这些字串会在新的一行出现
#       \\ 输出其后的空格，否则会被忽略
sed -i "/affiliations:/a \\   $aff" \
   $FABRIC_CA_SERVER_HOME/fabric-ca-server-config.yaml

# Start the root CA
fabric-ca-server start