#!/bin/bash

# Copyright 凡派 All Rights Reserved.
#
# Apache-2.0
#
# 如果使用该脚本，请执行：curl -sSL https://raw.githubusercontent.com/fnpac/fabric-samples-cn/master/bootstrap.sh | bash -s 1.1.0 1.1.0
# 具体使用请参考[bootstrap.sh脚本](https://github.com/fnpac/fabric-samples-cn/blob/master/README.md#bootstrap.sh脚本)

# 如果version未指定，则默认使用latest released version
export VERSION=1.1.0

# 如果ca version未指定，则默认使用latest released version
export CA_VERSION=$VERSION

# current version of thirdparty images (couchdb, kafka and zookeeper) released
export THIRDPARTY_IMAGE_VERSION=0.4.6
# e.g linux-amd64
export ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')

# Set MARCH variable i.e ppc64le,s390x,x86_64,i386
MARCH=`uname -m`

DOCKER=true
SAMPLES=true
BINARIES=true

# 解析命令行参数，获取version、ca version
if echo $1 | grep -P -q '\d'; then
    VERSION=$1;shift
    if echo $1 | grep -P -q '\d'; then
        CA_VERSION=$1;shift
    fi
fi

BINARY_FILE=hyperledger-fabric-${ARCH}-${VERSION}.tar.gz
CA_BINARY_FILE=hyperledger-fabric-ca-${ARCH}-${CA_VERSION}.tar.gz

: ${CA_TAG:="$MARCH-$CA_VERSION"}
: ${FABRIC_TAG:="$MARCH-$VERSION"}
: ${THIRDPARTY_TAG:="$MARCH-$THIRDPARTY_IMAGE_VERSION"}

printHelp() {

cat << EOF
  使用说明: bootstrap.sh [<version>] [<ca_version>] [-d -s -b]

      -d - 忽略下载docker镜像
      -s - 忽略克隆fabric-samples-cn代码库
      -b - 忽略下载fabric二进制文件

  默认版本1.1.0

  e.g. bootstrap.sh 1.1.0 -s
  将会下载1.1.0版本的docker镜像和fabric二进制文件
EOF
}

samplesInstall() {

    # 仅支持v1.1.0
    if [ "${VERSION}" == "1.1.0" ]; then
        # 克隆（如果需要）fabric-samples-cn库并切换到要下载的二进制文件和docker映像相应版本
        if [ -d first-network ]; then
            # 如果当前处于fabric-samples-cn目录下，切换到相应的版本
            echo "===> Checking out v${VERSION} branch of hyperledger/fabric-samples-cn"
            git checkout v${VERSION}
        elif [ -d fabric-samples-cn ]; then
            # 如果fabric-samples-cn库已经克隆了，并且在当前目录下，进入到fabric-samples-cn目录并切换到相应的版本
            echo "===> Checking out v${VERSION} branch of hyperledger/fabric-samples-cn"
            cd fabric-samples-cn && git checkout v${VERSION}
        else
            echo "===> Cloning hyperledger/fabric-samples-cn repo and checkout v${VERSION}"
            git clone -b master https://github.com/fnpac/fabric-samples-cn.git && cd fabric-samples-cn && git checkout v${VERSION}
        fi
    fi
}

# 首先在本地增量下载.tar.gz文件，下载完成后才解压。这比binaryDownload()慢，但允许恢复下载。
binaryIncrementalDownload() {

    local BINARY_FILE=$1
    local URL=$2

    # Usage: curl [options...] <url>
    #   Options: (H) means HTTP/HTTPS only, (F) means FTP only
    #
    #   -f, --fail      Fail silently (no output at all) on HTTP errors (H) 连接失败时不显示http错误
    #   -s, --silent    Silent mode (don't output anything) 静默模式。不输出任何东西
    #   -C, --continue-at OFFSET  Resumed transfer OFFSET 继续对该文件进行下载，已经下载过的文件不会被重新下载。偏移量是以字节为单位的整数，如果让curl自动推断出正确的续传位置使用 '-C -'。
    curl -f -s -C - ${URL} -o ${BINARY_FILE} || rc=$?

    # 由于目前的Nexus库限制：
    # 当有一个没有更多字节下载的恢复尝试时，curl会返回33
    # 完成恢复下载后，curl返回2
    # 使用-f选项，404时curl返回22
    if [ "$rc" = 22 ]; then
        # looks like the requested file doesn't actually exist so stop here
        return 22
    fi
    # 在本地增量下载.tar.gz文件成功：-z "$rc"
    # 恢复下载完成：$rc -eq 33，$rc -eq 2
    if [ -z "$rc" ] || [ $rc -eq 33 ] || [ $rc -eq 2 ]; then
        # The checksum validates that RC 33 or 2 are not real failures
        echo "==> File downloaded. Verifying the md5sum..."
        localMd5sum=$(md5sum ${BINARY_FILE} | awk '{print $1}')
        remoteMd5sum=$(curl -s ${URL}.md5)
        if [ "$localMd5sum" == "$remoteMd5sum" ]; then
            echo "==> Extracting ${BINARY_FILE}..."
            tar xzf ./${BINARY_FILE} --overwrite
            echo "==> Done."
            rm -f ${BINARY_FILE} ${BINARY_FILE}.md5
        else
            echo "Download failed: the local md5sum is different from the remote md5sum. Please try again."
            rm -f ${BINARY_FILE} ${BINARY_FILE}.md5
            exit 1
        fi
    else
        echo "Failure downloading binaries (curl RC=$rc). Please try again and the download will resume from where it stopped."
        exit 1
    fi
}

# 这会尝试一次下载.tar.gz，但会在失败时调用binaryIncrementalDownload()函数，允许在网络出现故障时恢复。
binaryDownload() {

    local BINARY_FILE=$1 # 保存的文件名
    # e.g
    #   https://nexus.hyperledger.org/content/repositories/releases/org/hyperledger/fabric/hyperledger-fabric/linux-amd64-1.1.0/hyperledger-fabric-linux-amd64-1.1.0.tar.gz
    #   https://nexus.hyperledger.org/content/repositories/releases/org/hyperledger/fabric-ca/hyperledger-fabric-ca/linux-amd64-1.1.0/hyperledger-fabric-ca-linux-amd64-1.1.0.tar.gz
    local URL=$2 # 下载url

    # 检查以前是否发生故障并且文件下载了一部分
    if [ -e ${BINARY_FILE} ]; then
        echo "==> Partial binary file found. Resuming download..."
        binaryIncrementalDownload ${BINARY_FILE} ${URL}
    else
        curl ${URL} | tar xz || rc=$?
        if [ ! -z "$rc" ]; then
            echo "==> There was an error downloading the binary file. Switching to incremental download."
            echo "==> Downloading file..."
            binaryIncrementalDownload ${BINARY_FILE} ${URL}
        else
            echo "==> Done."
        fi
    fi
}

binariesInstall() {

    echo "===> Downloading version ${FABRIC_TAG} platform specific fabric binaries"
    binaryDownload ${BINARY_FILE} https://nexus.hyperledger.org/content/repositories/releases/org/hyperledger/fabric/hyperledger-fabric/${ARCH}-${VERSION}/${BINARY_FILE}

    # 22 对应于 404
    if [ $? -eq 22 ]; then
        echo
        echo "------> ${FABRIC_TAG} platform specific fabric binary is not available to download <----"
        echo
    fi

    echo "===> Downloading version ${CA_TAG} platform specific fabric-ca-client binary"
    binaryDownload ${CA_BINARY_FILE} https://nexus.hyperledger.org/content/repositories/releases/org/hyperledger/fabric-ca/hyperledger-fabric-ca/${ARCH}-${CA_VERSION}/${CA_BINARY_FILE}
    if [ $? -eq 22 ]; then
         echo
         echo "------> ${CA_TAG} fabric-ca-client binary is not available to download  (Available from 1.1.0-rc1) <----"
         echo
    fi
}

dockerFabricPull() {
  local FABRIC_TAG=$1
  for IMAGES in peer orderer ccenv javaenv tools; do
      echo "==> FABRIC IMAGE: $IMAGES"
      echo
      docker pull hyperledger/fabric-$IMAGES:$FABRIC_TAG
      docker tag hyperledger/fabric-$IMAGES:$FABRIC_TAG hyperledger/fabric-$IMAGES
  done
}

dockerThirdPartyImagesPull() {
  local THIRDPARTY_TAG=$1
  for IMAGES in couchdb kafka zookeeper; do
      echo "==> THIRDPARTY DOCKER IMAGE: $IMAGES"
      echo
      docker pull hyperledger/fabric-$IMAGES:$THIRDPARTY_TAG
      docker tag hyperledger/fabric-$IMAGES:$THIRDPARTY_TAG hyperledger/fabric-$IMAGES
  done
}

dockerCaPull() {
      local CA_TAG=$1
      echo "==> FABRIC CA IMAGE"
      echo
      docker pull hyperledger/fabric-ca:$CA_TAG
      docker tag hyperledger/fabric-ca:$CA_TAG hyperledger/fabric-ca
}

dockerInstall() {

    which docker >& /dev/null
    NODOCKER=$?
    if [ "${NODOCKER}" == 0 ]; then # docker已经安装
        echo "===> Pulling fabric Images"
        dockerFabricPull ${FABRIC_TAG}
        echo "===> Pulling fabric ca Image"
	    dockerCaPull ${CA_TAG}
	    echo "===> Pulling thirdparty docker images"
	    dockerThirdPartyImagesPull ${THIRDPARTY_TAG}
	    echo
        echo "===> List out hyperledger docker images"
        docker images | grep hyperledger*
    else
        echo "========================================================="
        echo "Docker not installed, bypassing download of Fabric images"
        echo "========================================================="
    fi
}

# then parse opts
while getopts "h?dsb" opt; do
  case "$opt" in
    h|\?)
      printHelp
      exit 0
    ;;
    d)  DOCKER=false
    ;;
    s)  SAMPLES=false
    ;;
    b)  BINARIES=false
    ;;
  esac
done

if [ "$SAMPLES" == "true" ]; then
  echo
  echo "Installing hyperledger/fabric-samples-cn repo"
  echo
  # 下载fabric-samples-cn
  samplesInstall
fi
# 此时处于fabric-sample目录下
if [ "$BINARIES" == "true" ]; then
  echo
  echo "Installing Hyperledger Fabric binaries"
  echo
  # 下载configtxgen、configtxlator、cryptogen、orderer、peer等二进制文件，以及get-docker-images.sh
  binariesInstall
fi

if [ "$DOCKER" == "true" ]; then
  echo
  echo "Installing Hyperledger Fabric docker images"
  echo
  dockerInstall
fi
