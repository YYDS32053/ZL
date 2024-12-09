#!/bin/bash

# 终止脚本，如果有任何命令失败
set -e

# 禁用交互界面
export DEBIAN_FRONTEND=noninteractive

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
  echo "错误: 请以root权限运行此脚本"
  exit 1
fi

# 检查是否已经安装 curl 和 lsb-release，避免重复安装
if ! command -v curl &>/dev/null; then
  echo "错误: curl 未安装。请手动安装 curl 或确保系统中已有它。"
  exit 1
fi

if ! command -v lsb_release &>/dev/null; then
  echo "错误: lsb_release 未安装。请手动安装 lsb-release 或确保系统中已有它。"
  exit 1
fi

echo "正在更新系统软件包..."
apt update -y && apt upgrade -y

# 添加Docker官方GPG密钥
echo "正在添加Docker官方GPG密钥..."
curl -fsSL https://download.docker.com/linux/debian/gpg | tee /etc/apt/trusted.gpg.d/docker.asc > /dev/null

# 添加Docker仓库
echo "正在添加Docker仓库..."
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" -y

# 更新APT包索引
echo "正在更新APT包索引..."
apt update -y

# 安装Docker
echo "正在安装Docker..."
apt install -y docker-ce docker-ce-cli containerd.io

# 启动并启用Docker
echo "正在启动Docker并设置开机自启..."
systemctl start docker
systemctl enable docker

# 检查Docker是否安装成功
echo "正在检查Docker版本..."
if docker --version &>/dev/null; then
    echo "Docker安装成功！版本: $(docker --version)"
else
    echo "错误: Docker安装失败。"
    exit 1
fi

echo "Docker安装完成！"
