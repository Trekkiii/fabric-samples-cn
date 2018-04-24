# fabric-shell v1.1.0

## 前言

### 安装GO

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

### 下载源码

将fabric源码Clone到hyperledger目录下。

```text
git clone https://github.com/hyperledger/fabric.git
git checkout -b v1.1.0 v1.1.0
```

然后将该代码Clone到到hyperledger目录下。

```text
git@github.com:fnpac/fabric-shell.git
```

此时的目录结构应该是这样子：

```text
root@vm***:~/gopath/src/github.com/hyperledger# ll
total 20
drwxr-xr-x  5 root   root   4096 Apr 24 11:26 ./
drwxr-xr-x  3 root   root   4096 Apr 17 18:12 ../
drwxr-xr-x 28 root   root   4096 Apr 18 14:37 fabric/
drwxrwxr-x  6 root   root   4096 Apr 24 11:25 fabric-shell/
```

### 安装docker

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

### 安装docker-compose

```text
apt-get install python-pip
pip install docker-compose
```

### 下载fabric docker镜像

```text
cd /root/gopath/src/github.com/hyperledger/

curl -sSL https://goo.gl/6wtTN5 | bash -s 1.1.0
```