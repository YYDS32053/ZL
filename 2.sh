#!/bin/bash

# 第一步：运行远程脚本
echo "=== Running remote setup script ==="
curl -fsSL https://raw.githubusercontent.com/YYDS32053/ZL/main/1.sh | bash

# 第二步：克隆项目代码
echo "=== Cloning ChatGPT-Mirror repository ==="
cd /home/ && git clone https://github.com/dairoot/ChatGPT-Mirror.git

# 第三步：进入项目目录
cd /home/ChatGPT-Mirror/

# 第四步：复制环境变量文件
echo "=== Creating environment configuration file ==="
cp .env.example .env

# 第五步：执行部署脚本
echo "=== Running deployment script ==="
chmod +x ./deploy.sh
./deploy.sh

echo "=== Deployment completed ==="
