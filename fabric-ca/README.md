# Hyperledger Fabric CA sample

Hyperledger Fabric CA演示了以下内容：

* 如何使用Hyperledger Fabric CA client&server来生成所有身份文件，而不是使用cryptogen。
    
    cryptogen工具不适用于生产环境，因为它在一个位置生成所有私钥，并将其复制到相应的主机或容器中。
        
    本示例演示如何为orderers，peers，管理员和终端用户生成身份文件，因此私钥永远不会离开生成它们的主机或容器。
    
* 如何使用Attribute-Based Access Control (ABAC)。 

    请参阅fabric-samples-cn/chaincode/go/abac/abac.go。
    
    请注意使用*github.com/hyperledger/fabric/core/chaincode/lib/cid*软件包来提取来自调用者身份的属性。
    仅具有值为*true*的*abac.init*属性的调用者身份才可以成功调用*Init*函数来实例化链码。
    
## Running this sample
    
1. 运行此示例需要以下镜像：*hyperledger/fabric-ca-orderer*, *hyperledger/fabric-ca-peer*, and *hyperledger/fabric-ca-tools*

    ##### 1.1.0
    运行此示例提供的*bootstrap.sh*脚本以下载fabric-ca sample所需的镜像
    
2. 要运行此示例，只需运行*start.sh*脚本。根据需要，您可以连续多次执行此操作，因为每次启动前*start.sh*脚本都会自动清理。

3. 要停止由*start.sh*脚本启动的容器，可以运行*stop.sh*脚本。

## Understanding this sample

在*fabric-samples-cn/fabric-ca/scripts/env.sh*脚本的顶部有一些变量，它们定义了此示例的名称和拓扑。您可以按照脚本注释中所述修改这些内容来自定义这个示例。

默认情况下，有三个组织。orderer组织是*org0*，两个peer组织分别是是 org1*和*org2*。

*start.sh*脚本首先构建*docker-compose.yml*文件（通过调用*makeDocker.sh*脚本），然后启动docker容器。

所有容器挂载*data*目录。在实际场景中不需要挂载此volume，但此示例由于如下原因选择使用它：

1. 所有容器都可以将其日志写入一个公共目录（即*data/logs*目录），以便于调试；
2. 同步容器启动的顺序（例如，*ica*容器中的中间层CA必须等待在*rca*容器中的相应根CA将其证书写入*data*目录）；
3. 以使用*客户端通过TLS进行连接*所需的引导证书；

在*docker-compose.yml*文件中定义的容器以以下顺序启动：

1. *rca*（Root CA）容器首先启动，每个组织启动一个。
一个*rca*容器运行一个fabric-ca-server（组织的根CA）。根CA证书写入*data*目录，以便中间层CA通过TLS连接到它时使用。

2. *ica*（Intermediate CA）容器接下来启动。
一个*ica*容器运行一个fabric-ca-server（组织的中间层CA）。每一个中间层CA都会登记一个对应的根CA。中间层CA证书也写入*data*目录。

3. *setup*容器向中间层CA注册身份，生成创世区块，以及创建区块链网络所需的其他artifacts。这由*fabric-samples-cn/fabric-ca/scripts/setup-fabric.sh*脚本执行。
    请注意管理员身份使用`abac.init=true:ecert`注册（请参阅此脚本的*registerPeerIdentities*函数）。从而管理员的注册证书（ECert）具有一个名为`abac.init`的属性，其值为`true`。
    需要进一步注意的是，此示例使用的链式代码要求将此属性包含在调用其`Init`函数的身份的证书中（参阅*fabric-samples-cn/chaincode/go/abac/abac.go*上的链码）。

有关Attribute-Based Access Control (ABAC)的更多信息，请参阅https://github.com/hyperledger/fabric/tree/release/core/chaincode/lib/cid/README.md。

4. orderer和peer容器启动。这些容器的命名就像它们在*data/logs*目录中的日志文件一样。

5. *run*容器启动后运行实际的测试用例。它创建一个应用通道，将peers加入应用通道，安装和实例化链码，并且查询和调用链码。见*fabric-samples-cn/fabric-ca/scripts/run-fabric.sh*脚本的*main*函数获取更多细节。

<a rel="license" href="http://creativecommons.org/licenses/by/4.0/"> <img alt =“Creative Commons License”style =“border-width：0”src =“https：/ /i.creativecommons.org/l/by/4.0/88x31.png“/> </a> <br />本作品根据<a rel =”license“href =”http://creativecommons.org /licenses/by/4.0/">创作共用署名4.0国际许可</a>