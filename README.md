# fabric-samples-cn v1.1.0

### 脚本模块

* [>> e2e_cli](https://github.com/fnpac/fabric-samples-cn/tree/master/e2e_cli)
* [>> first-network](https://github.com/fnpac/fabric-samples-cn/tree/master/first-network)
* [>> fabric-ca](https://github.com/fnpac/fabric-samples-cn/tree/master/fabric-ca)

### 环境安装

下载地址:

https://studygolang.com/dl

拷贝到`/usr/local`目录下解压

```text
tar -zxvf go1.10.1.linux-amd64.tar.gz
```

在`$HOME`（我这里为`ubuntu`用户目录）下新建`gopath`目录，并且新增`src`子目录。

```text
cd src/

mkdir github.com

cd github.com

mkdir hyperledger
```

编辑`.bashrc`文件:

```text
export GOPATH=$HOME/gopath
export GOROOT=/usr/local/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
```

```bash
source .bashrc
```

##### 下载fabric源码

将fabric源码Clone到hyperledger目录下。

```text
git clone https://github.com/hyperledger/fabric.git
git checkout -b v1.1.0 v1.1.0
```

##### 安装docker

```text
sudo curl -fsSL https://get.docker.com | sh
```

安装结束后，会提示：

```text
If you would like to use Docker as a non-root user, you should now consider
adding your user to the "docker" group with something like:

  sudo usermod -aG docker ubuntu

Remember that you will have to log out and back in for this to take effect!

WARNING: Adding a user to the "docker" group will grant the ability to run
         containers which can be used to obtain root privileges on the
         docker host.
         Refer to https://docs.docker.com/engine/security/security/#docker-daemon-attack-surface
         for more information.
```

将`ubuntu`加入`docker`用户组：

```bash
sudo usermod -aG docker ubuntu
```

然后执行如下命令启动docker：

```bash
# 使用下面的命令启动 Docker：
systemctl start docker
```

**重新启动**

systemctl restart docker

**设置开机自启动**

systemctl enable docker

**查看状态**

systemctl status docker

**查看所有已启动的服务**

systemctl list-units --type=service


执行`docker ps`查看docker容器，如果提示：

```text
ubuntu@vm10-249-0-3:~$ docker ps
Got permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: Get http://%2Fvar%2Frun%2Fdocker.sock/v1.37/containers/json: dial unix /var/run/docker.sock: connect: permission denied
```

执行如下命令即可解决：

```bash
ubuntu@vm10-249-0-3:~$ newgrp - docker
ubuntu@vm10-249-0-3:~$ 
ubuntu@vm10-249-0-3:~$ 
ubuntu@vm10-249-0-3:~$ docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
ubuntu@vm10-249-0-3:~$
```

##### 安装docker-compose

```text
sudo apt-get update
sudo apt-get install python-pip
sudo pip install docker-compose
```

### bootstrap.sh脚本

使用方法：

```bash
使用说明: bootstrap.sh [<version>] [<ca_version>] [-d -s -b]

  -d - 忽略下载docker镜像
  -s - 忽略克隆fabric-samples-cn代码库
  -b - 忽略下载fabric二进制文件

默认版本1.1.0
```

`bootstrap.sh`脚本主要执行如下操作：

* 克隆`fabric-samples-cn`代码库；
    
    fabric-samples-cn代码库只提供了v1.1.0版本的支持；
    
* 下载fabric二进制文件，并保存到fabric-samples-cn目录下的`bin`文件夹下；

    v1.1.0版本还会下载configtx.yaml、configtx.yaml、configtx.yaml配置文件；
    
* 下载fabric docker镜像

> 💡 指定的版本不要加前缀`v`

```text
cd /root/gopath/src/github.com/hyperledger/

# 克隆fabric-samples-cn库、下载fabric二进制文件、下载configtx.yaml、core.yaml、orderer.yaml配置文件、下载fabric docker镜像
curl -sSL https://raw.githubusercontent.com/fnpac/fabric-samples-cn/master/bootstrap.sh | bash -s 1.1.0 1.1.0

# 下载fabric二进制文件、下载configtx.yaml、core.yaml、orderer.yaml配置文件、下载fabric docker镜像
# 但不会克隆`fabric-samples-cn`库（仅支持1.1.0）
curl -sSL https://raw.githubusercontent.com/fnpac/fabric-samples-cn/master/bootstrap.sh | bash -s 1.0.6 1.0.6
```

> 💡 务必在fabric源码同级目录下执行上述命令操作

##### 官方版本

当前你可以使用官方提供的脚本，其`fabric-samples`代码库提供了除v1.1.0外的其他版本。

```bash
cd /root/gopath/src/github.com/hyperledger/

curl -sSL https://goo.gl/6wtTN5 | bash -s 1.0.6 1.0.6
```

> 💡 指定的版本为[fabric-samples tags](https://github.com/hyperledger/fabric-samples/tags)中列出的tags，
如果指定其它版本，这会造成`fabric-samples`代码无法切换到指定版本的分支。