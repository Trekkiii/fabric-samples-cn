#!/bin/bash

# Hyperledger Fabric网络由两个组织组成，每个组织维护两个peer，以及一个"solo"类型的orderer服务。
#
# 使用两个基本工具，这对于创建具有数字签名验证和访问控制功能的事务性网络是必需的：
#
# * cryptogen - 生成用于识别和验证网络中各种组件的x509证书。
# * configtxgen - 为orderer引导和通道创建生成必要的配置工件。

export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}




# 已知不能与此版本的first-network一起使用的fabric版本
BLACKLISTED_VERSIONS="^1\.0\. ^1\.1\.0-preview ^1\.1\.0-alpha"

