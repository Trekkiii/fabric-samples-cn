# first-network

> 💡 确保你已经读完了[README.md](https://github.com/fnpac/fabric-shell/blob/master/README.md)

## 特性

* 该脚本基于docker-compose在**一台机器**上创建fabric网络；
* fabric网络结构包括：2个Org（分别有2个Peer，且每一个Peer支持启用couchdb，默认不启用）、1个Cli、1个Orderer；
* 提供灵活的选项，对fabric网络进行简单的配置；
* 支持指定fabric版本；
* 适合快速构建并测试fabric区块链；

> 💡 该脚本构建fabric区块链网络所使用的二进制文件，使用的是[bootstrap.sh](https://raw.githubusercontent.com/fnpac/fabric-shell/master/bootstrap.sh)脚本自动下载的二进制文件。
> 这有区别于`e2e_cli`模块，这里不用下载fabric源码。

## 使用

```bash
byfn.sh up|down|restart|generate|upgrade [-c <channel name>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>] [-s <dbtype>] [-i <imagetag>]
  byfn.sh -h|--help (获取此帮助)
    <mode> - 'up', 'down', 'restart' 或者 'generate'
      - 'up' - 使用'docker-compose up'创建网络
      - 'down' - 使用'docker-compose down'关闭网络，并删除相关fabric文件、docker组件
      - 'restart' - 重启网络
      - 'generate' - 生成必要的身份证书、创世区块、应用通道配置交易文件和锚点更新配置文件
      - 'upgrade'  - 将网络从 v1.0.x 升级到 v1.1
    -c <channel name> - 使用的应用通道名称 (默认为\"mychannel\")
    -t <timeout> - CLI在放弃之前应该等待来自另一个容器的响应的超时时间，单位s (默认10s)
    -d <delay> - 命令之间延迟，单位s(默认3s)
    -f <docker-compose-file> - 指定要使用的docker-compose 文件(默认为docker-compose-cli.yaml)
    -s <dbtype> - 使用的数据库: goleveldb (默认) 或者 couchdb(支持更高级的查询)
    -l <language> - 编写链码使用的开发语言: golang (默认) 或者 node
    -i <imagetag> - 创建网络所使用镜像的tag (默认为\"latest\")，i.e -i 1.1.0
```

### 启动网络

直接运行该脚本即可使用默认配置创建fabric网络。

```text
./byfn.sh -m up
```

> 💡 第一次启动可能会失败，尝试先关闭`./byfn.sh -m down`，再重新启动

> 💡 务必保证fabric的docker镜像和用来生成必要的身份证书、创世区块、应用通道配置交易文件和锚点更新配置文件等文件的二进制文件(i.e cryptogen、configtxgen)版本一致！！！

##### fabric docker images（docker镜像）

脚本默认使用docker中tag为`latest`的镜像创建fabric网络。

**一、下载镜像**

可以通过以下命令下载镜像：

```bash
curl -sSL https://raw.githubusercontent.com/fnpac/fabric-shell/master/bootstrap.sh | bash -s 1.1.0 1.1.0 -s -b
```

**二、指定镜像**

1. 你可以通过如下命令指定使用的镜像的版本创建启动fabric网络：

```bash
./byfn.sh -m up -i 1.1.0
```

2. 也可以使用脚本的默认配置，但是通过如下命令将指定版本的镜像标记`latest`tag。

**v1.0.6**
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

**v1.1.0**
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

##### bin（二进制文件）

脚本使用`$PATH`中的二进制文件(i.e cryptogen、configtxgen)来生成必要的身份证书、创世区块、应用通道配置交易文件和锚点更新配置文件等文件

可以通过如下命令下载指定版本的二进制文件：

```bash
cd /root/gopath/src/github.com/hyperledger/

curl -sSL https://raw.githubusercontent.com/fnpac/fabric-shell/master/bootstrap.sh | bash -s 1.1.0 1.1.0 -d -s
```

此外，脚本会将`fabric-shell/bin`目录加入`PATH`，所以只需要将下载的`bin/`目录移到`fabric-shell/`目录下。

```bash
mv bin/ fabric-shell/
```

### 生成相关文件

主要执行如下内容：

* 生成组织关系和身份证书
* 将`docker-compose-e2e-template.yaml`复制为`docker-compose.yaml`，并用由`cryptogen`工具生成的私钥文件名替换`docker-compose.yaml`文件其中的私钥名称占位符
* 生成orderer创世区块，应用通道配置交易文件和锚点更新配置文件

```bash
./byfn.sh -m generate
```

### 关闭网络

主要执行如下内容：

1. 删除Compose文件中定义的容器
2. 删除Compose文件中`networks`部分定义的网络
3. 删除Compose文件的`volumes`部分中声明的命名卷和附加到容器的匿名卷，删除fabric的整个区块链账本数据
4. 删除docker中的所有容器
5. 删除链码镜像
6. 删除通过`cryptogen`生成的MSP身份证书
7. 删除通过`configtxgen`工具生成的创世区块、应用通道配置交易文件、锚节点配置更新文件

```bash
./byfn.sh -m down
```

### 重启网络

```bash
./byfn.sh -m restart
```

> 💡 重启操作不会删除生成的Artifacts。不会执行**关闭网络**操作中的4-7步。但是账本总是会被删除。

### 升级网络

将fabric网络从v1.0.x升级到v1.1.0

由于在`docker-compose-base.yaml`文件中，我们将`orderer`与`peer`节点的账本挂载到了docker的`volumes`，所以升级过程不会导致账本数据的丢失。

**TODO**：升级过程会删除链码容器和镜像，但升级脚本并没有再次安装、实例化，那么链码容器是怎么再次运行的呢？

### 加入新组织

```bash
./eyfn.sh -m up
```

这一步涉及到三个关键脚本：`step1org3.sh`,`step2org3.sh`,`step3org3.sh`。

* `step1org3.sh`：
    通过`cli`容器运行
    - 创建配置更新交易文件；
    - 通过`peer channel update`将Org3加入fabric网络；
* `step2org3.sh`：
    通过`Org3cli`容器运行
    - 通过`peer channel fetch`获取要加入应用通道的初始区块；
    - 通过`peer channel join`将Org3 peers节点加入应用通道；
    - 在`peer0.org3`上安装链码；
* `step3org3.sh`：
    通过`cli`容器运行
    - 在peer0.org1和peer0.org2上安装链码；
    - 将通道上的chaincode升级到2.0版本；

> 💡 `step1org3.sh`,`step2org3.sh`,`step3org3.sh`都是通过tls连接，确保开启tls。

这里之所以使用cli容器，是因为用于将加入Org3的配置更新交易文件需要大多数peer节点（Org1 peers 与 Org2 peers）的签名，
而Org1 peers 与 Org2 peers节点的身份证书只挂载在cli容器中，Org3 peers 和 Orderer节点的身份证书挂载在Org3cli容器中。

### 获取更多的帮助

```text
./byfn.sh -h
./byfn.sh -?
```