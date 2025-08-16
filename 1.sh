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

# 更新系统软件包索引
echo "正在更新系统软件包..."
sudo apt update -y

# 安装 Docker 所需的最小依赖项（curl 和 ca-certificates）
echo "正在安装必需依赖项..."
sudo apt install -y ca-certificates curl

# 添加 Docker 官方 GPG 密钥
echo "正在添加 Docker 官方 GPG 密钥..."
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo tee /etc/apt/trusted.gpg.d/docker.asc > /dev/null

# 添加 Docker 仓库
echo "正在添加 Docker 仓库..."
echo "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新 APT 包索引
echo "正在更新 APT 包索引..."
sudo apt update -y

# 安装 Docker 核心组件
echo "正在安装 Docker 核心组件..."
sudo apt install -y docker-ce

# 启动并启用 Docker 服务
echo "正在启动 Docker 服务并设置为开机自启..."
sudo systemctl start docker
sudo systemctl enable docker

sudo curl -L "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version

# 验证 Docker 是否安装成功
echo "正在检查 Docker 版本..."
if sudo docker --version &>/dev/null; then
    echo "Docker 安装成功！"
else
    echo "错误: Docker 安装失败。"
    exit 1
fi

echo "Docker 安装完成!！"
