# fabric-shell v1.1.0

### 脚本模块

* [>> e2e_cli](https://github.com/fnpac/fabric-shell/tree/master/e2e_cli)
* [>> first-network](https://github.com/fnpac/fabric-shell/tree/master/first-network)

### 环境安装

下载地址:

https://studygolang.com/dl

拷贝到`/usr/local`目录下解压

```text
tar -zxvf go1.10.1.linux-amd64.tar.gz
```

在`$HOME`下新建`gopath`目录，并且新增`src`子目录。

```text
cd src/

mkdir github.com

cd github.com

mkdir hyperledger
```

编辑/etc/profile文件:

```text
export GOPATH=$HOME/gopath
export GOROOT=/usr/local/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
```

##### 下载fabric源码

将fabric源码Clone到hyperledger目录下。

```text
git clone https://github.com/hyperledger/fabric.git
git checkout -b v1.1.0 v1.1.0
```

##### 安装docker

```text
curl -fsSL https://get.docker.com | sh

等待安装完毕，现在我们使用下面的命令启动 Docker：
systemctl start docker

重新启动
systemctl restart docker

设置开机自启动
systemctl enable docker

查看状态
systemctl status docker

查看所有已启动的服务
systemctl list-units --type=service
```

##### 安装docker-compose

```text
apt-get install python-pip
pip install docker-compose
```

### bootstrap.sh脚本

使用方法：

```bash
使用说明: bootstrap.sh [<version>] [<ca_version>] [-d -s -b]

  -d - 忽略下载docker镜像
  -s - 忽略克隆fabric-shell代码库
  -b - 忽略下载fabric二进制文件

默认版本1.1.0
```

`bootstrap.sh`脚本主要执行如下操作：

* 克隆`fabric-shell`代码库；
    
    fabric-shell代码库只提供了v1.1.0版本的支持；
    
* 下载fabric二进制文件，并保存到fabric-shell目录下的`bin`文件夹下；

    v1.1.0版本还会下载configtx.yaml、configtx.yaml、configtx.yaml配置文件；
    
* 下载fabric docker镜像

> 💡 指定的版本不要加前缀`v`

```text
cd /root/gopath/src/github.com/hyperledger/

# 克隆fabric-shell库、下载fabric二进制文件、下载configtx.yaml、core.yaml、orderer.yaml配置文件、下载fabric docker镜像
curl -sSL https://raw.githubusercontent.com/fnpac/fabric-shell/master/bootstrap.sh | bash -s 1.1.0 1.1.0

# 下载fabric二进制文件、下载configtx.yaml、core.yaml、orderer.yaml配置文件、下载fabric docker镜像
# 但不会克隆`fabric-shell`库（仅支持1.1.0）
curl -sSL https://raw.githubusercontent.com/fnpac/fabric-shell/master/bootstrap.sh | bash -s 1.0.6 1.0.6
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