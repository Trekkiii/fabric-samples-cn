## e2e_cli

该脚本基于docker-compose在一台机器上创建fabric网络。

包括：2个组织（分别有2个节点）、1个CLI节点、Orderer节点（3个Zookeeper以及4个Kafka）

直接运行该脚本即可创建fabric网络。

```text
./network_setup.sh up
```

关闭网络执行如下

```text
./network_setup.sh down
```