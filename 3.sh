#!/bin/bash

# 脚本功能: 在 Ubuntu 24.04 (Noble Numbat) 及兼容系统上安装 Docker Engine 和 Docker Compose 插件
# 优化点:
# 1. 使用官方推荐的 Ubuntu 软件源，而非错误的 Debian 源。
# 2. 采用更安全的 GPG 密钥管理方式。
# 3. 安装现代的 Docker Compose 插件 (docker compose)，而非旧的独立二进制文件 (docker-compose)。
# 4. 增加了更完善的依赖项和完整的 Docker 组件安装。
# 5. 使用更可靠的验证方式。

# 终止脚本，如果有任何命令失败
set -e

# 禁用交互界面
export DEBIAN_FRONTEND=noninteractive

# 1. 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
  echo "错误: 请以root权限运行此脚本 (例如: sudo ./install_docker.sh)"
  exit 1
fi

# 2. 安装 Docker 所需的依赖项
echo "正在更新软件包索引并安装依赖项..."
apt-get update
apt-get install -y ca-certificates curl gnupg

# 3. 添加 Docker 官方 GPG 密钥 (采用推荐的 keyring 方式)
echo "正在添加 Docker 官方 GPG 密钥..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# 4. 添加 Docker 的 APT 软件源
# 注意：这里会自动识别你的系统架构 (如 amd64) 和版本代号 (如 noble)
echo "正在设置 Docker 软件源..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. 更新软件包索引以包含新的 Docker 源
echo "再次更新软件包索引..."
apt-get update

# 6. 安装 Docker Engine, CLI, Containerd, 以及 Docker Compose 插件
echo "正在安装 Docker Engine 和 Docker Compose 插件..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 7. 验证 Docker 是否安装并运行成功
echo "正在通过运行 hello-world 容器来验证 Docker 安装..."
if docker run hello-world &>/dev/null; then
    echo -e "\n✅ Docker Engine 安装成功并已正确运行！"
else
    echo -e "\n❌ 错误: Docker Engine 安装失败或无法运行。"
    # 尝试启动服务并重试
    echo "尝试启动 Docker 服务..."
    systemctl start docker
    systemctl enable docker
    if docker run hello-world &>/dev/null; then
         echo -e "\n✅ Docker 服务启动后，验证成功！"
    else
         echo -e "\n❌ 错误: 启动服务后依然无法运行 hello-world 容器。"
         exit 1
    fi
fi

# 8. 验证 Docker Compose 插件版本
echo -e "\n正在检查 Docker Compose 插件版本..."
docker compose version

echo -e "\n🎉 Docker 和 Docker Compose 已全部安装完成！"
echo "💡 提示: 为了让当前用户无需 sudo 即可运行 docker 命令, 请执行以下命令:"
echo "   sudo usermod -aG docker $USER"
echo "   然后请完全注销并重新登录系统以使设置生效。"
