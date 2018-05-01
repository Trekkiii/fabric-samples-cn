## v1.0.6

为了简单明了起见，我们将fabric docker镜像的下载步骤分开执行。

### docker镜像

可以通过如下命令下载fabric v1.0.6镜像

```bash
curl -sSL https://raw.githubusercontent.com/fnpac/fabric-shell/master/bootstrap.sh | bash -s 1.0.6 1.0.6 -s -b
```

可以通过如下命令下载fabric v1.1.0镜像

```bash
curl -sSL https://raw.githubusercontent.com/fnpac/fabric-shell/master/bootstrap.sh | bash -s 1.1.0 1.1.0 -s -b
```

### fabric脚本

##### v1.0.6

这里我们借助[hyperledger/fabric-samples](https://github.com/hyperledger/fabric-samples)提供的支持创建v1.0.6 fabric网络。

你可以通过如下命令启动v1.0.6 fabric网络。

下载v1.0.6 fabric-samples脚本代码 & 下载运行脚本所需的v1.0.6二进制文件：

```bash
curl -sSL https://goo.gl/6wtTN5 | bash -s 1.0.6 1.0.6 -d

root@vm***:~/gopath/src/github.com/hyperledger# ll
total 12
drwxr-xr-x  3 root root 4096 May  1 20:50 ./
drwxr-xr-x  3 root root 4096 Apr 17 18:12 ../
drwxr-xr-x 12 root root 4096 May  1 20:50 fabric-samples/
root@vm***:~/gopath/src/github.com/hyperledger# 
root@vm***:~/gopath/src/github.com/hyperledger# cd fabric-samples/
root@vm***:~/gopath/src/github.com/hyperledger/fabric-samples# 
root@vm***:~/gopath/src/github.com/hyperledger/fabric-samples# git branch
* (HEAD detached at v1.0.6)
  master
root@vm***:~/gopath/src/github.com/hyperledger/fabric-samples# 
root@vm***:~/gopath/src/github.com/hyperledger/fabric-samples# cd bin/
root@vm***:~/gopath/src/github.com/hyperledger/fabric-samples/bin# 
root@vm***:~/gopath/src/github.com/hyperledger/fabric-samples/bin# ./configtxgen -version
configtxgen:
 Version: 1.0.6
 Go version: go1.7.5
 OS/Arch: linux/amd64
root@vm***:~/gopath/src/github.com/hyperledger/fabric-samples/bin# 
```

如果你下载了v1.0.6与v1.1.0的docker镜像，这里我们需要指定所使用的镜像版本v1.0.6：

```bash
docker tag hyperledger/fabric-peer:x86_64-1.0.6 hyperledger/fabric-peer; \
docker tag hyperledger/fabric-orderer:x86_64-1.0.6 hyperledger/fabric-orderer; \
docker tag hyperledger/fabric-ccenv:x86_64-1.0.6 hyperledger/fabric-ccenv; \
docker tag hyperledger/fabric-javaenv:x86_64-1.0.6 hyperledger/fabric-javaenv; \
docker tag hyperledger/fabric-tools:x86_64-1.0.6 hyperledger/fabric-tools; \
docker tag hyperledger/fabric-couchdb:x86_64-0.4.6 hyperledger/fabric-couchdb; \
docker tag hyperledger/fabric-kafka:x86_64-0.4.6 hyperledger/fabric-kafka; \
docker tag hyperledger/fabric-zookeeper:x86_64-0.4.6 hyperledger/fabric-zookeeper; \
docker tag hyperledger/fabric-ca:x86_64-1.0.6 hyperledger/fabric-ca;
```

最后就是启动网络：

```bash
root@vm***:~/gopath/src/github.com/hyperledger/fabric-samples/first-network# ./byfn.sh -m up
```

##### v1.0.6 => v1.1.0

下载v1.1.0 fabric-shell脚本代码 & 下载运行脚本所需的v1.1.0二进制文件：

```bash
curl -sSL https://raw.githubusercontent.com/fnpac/fabric-shell/master/bootstrap.sh | bash -s 1.1.0 1.1.0 -d
```

需要指定所使用的镜像版本v1.1.0：

```bash
docker tag hyperledger/fabric-peer:x86_64-1.1.0 hyperledger/fabric-peer; \
docker tag hyperledger/fabric-orderer:x86_64-1.1.0 hyperledger/fabric-orderer; \
docker tag hyperledger/fabric-ccenv:x86_64-1.1.0 hyperledger/fabric-ccenv; \
docker tag hyperledger/fabric-javaenv:x86_64-1.1.0 hyperledger/fabric-javaenv; \
docker tag hyperledger/fabric-tools:x86_64-1.1.0 hyperledger/fabric-tools; \
docker tag hyperledger/fabric-couchdb:x86_64-0.4.6 hyperledger/fabric-couchdb; \
docker tag hyperledger/fabric-kafka:x86_64-0.4.6 hyperledger/fabric-kafka; \
docker tag hyperledger/fabric-zookeeper:x86_64-0.4.6 hyperledger/fabric-zookeeper; \
docker tag hyperledger/fabric-ca:x86_64-1.1.0 hyperledger/fabric-ca;
```

升级过程需要使用到在启动fabric v1.0.6网络时生成的`channel-artifacts`、`crypto-config`这两个文件夹，我们将其Copy到`fabric-shell/first-network`目录下。

> 💡 切记不可重新生成，一定要使用启动fabric v1.0.6网络时生成的`channel-artifacts`、`crypto-config`这两个文件夹

```bash
root@vm***:~/gopath/src/github.com/hyperledger/fabric-shell/first-network# mv ../../fabric-samples/first-network/crypto-config .
root@vm***:~/gopath/src/github.com/hyperledger/fabric-shell/first-network# rm -rf channel-artifacts/ && mv ../../fabric-samples/first-network/channel-artifacts .
```

最后更新网络操作：

```bash
root@vm***:~/gopath/src/github.com/hyperledger/fabric-shell/first-network# ./byfn.sh -m upgrade
```