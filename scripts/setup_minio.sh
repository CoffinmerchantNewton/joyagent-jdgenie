#!/bin/bash
# =====================================================
# JoyLaw MinIO 对象存储初始化脚本
# =====================================================

set -e

echo "========================================"
echo "JoyLaw MinIO 初始化脚本"
echo "========================================"

# 读取环境变量
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
    echo "✅ 已加载 .env 配置文件"
else
    echo "⚠️  未找到 .env 文件，使用默认配置"
    MINIO_ENDPOINT=${MINIO_ENDPOINT:-localhost:9000}
    MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-minioadmin}
    MINIO_SECRET_KEY=${MINIO_SECRET_KEY:-minioadmin}
fi

echo ""
echo "MinIO配置:"
echo "  端点: $MINIO_ENDPOINT"
echo "  访问密钥: $MINIO_ACCESS_KEY"
echo ""

# 检查Docker是否安装
if ! command -v docker &> /dev/null; then
    echo "❌ 未检测到 Docker，请先安装 Docker"
    exit 1
fi

echo "✅ Docker 已安装"

# 检查MinIO是否已在运行（通过端口检测）
if sudo netstat -tlnp 2>/dev/null | grep -q ':9000'; then
    echo "✅ 检测到 MinIO 已在运行（端口9000已被占用）"
    echo "跳过容器创建，直接配置存储桶..."
elif docker ps | grep -q minio; then
    echo "✅ 检测到 MinIO Docker容器已运行"
    echo "跳过容器创建，直接配置存储桶..."
elif docker ps -a | grep -q joylaw-minio; then
    echo "⚠️  发现已停止的 MinIO 容器，正在启动..."
    docker start joylaw-minio
    echo "✅ MinIO 容器已启动"
    sleep 3
else
    # 创建MinIO数据目录
    MINIO_DATA_DIR="${HOME}/joylaw-minio-data"
    mkdir -p $MINIO_DATA_DIR

    echo ""
    echo "启动 MinIO 容器..."

    docker run -d \
      --name joylaw-minio \
      -p 9000:9000 \
      -p 9001:9001 \
      -v $MINIO_DATA_DIR:/data \
      -e "MINIO_ROOT_USER=$MINIO_ACCESS_KEY" \
      -e "MINIO_ROOT_PASSWORD=$MINIO_SECRET_KEY" \
      --restart unless-stopped \
      minio/minio server /data --console-address ":9001"

    echo "✅ MinIO 容器启动成功"
    echo ""
    echo "等待 MinIO 服务就绪..."
    sleep 5
fi

# 安装MinIO客户端（mc）
if ! command -v mc &> /dev/null; then
    echo "安装 MinIO 客户端（mc）..."
    wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /tmp/mc
    chmod +x /tmp/mc
    sudo mv /tmp/mc /usr/local/bin/
    echo "✅ mc 安装完成"
else
    echo "✅ mc 已安装"
fi

# 配置mc连接
echo ""
echo "配置 MinIO 客户端..."
mc alias set joylaw http://$MINIO_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

# 创建必要的buckets
echo ""
echo "创建存储桶（Buckets）..."

BUCKETS=("avatars" "project-files" "kb-documents" "temp")

for bucket in "${BUCKETS[@]}"; do
    if mc ls joylaw/$bucket &> /dev/null; then
        echo "✅ 存储桶 $bucket 已存在"
    else
        if mc mb joylaw/$bucket 2>/dev/null; then
            echo "✅ 创建存储桶: $bucket"
        else
            echo "⚠️  创建存储桶 $bucket 失败，可能已存在"
        fi
    fi
done

# 设置匿名访问策略（可选）
echo ""
echo "配置访问策略..."

# avatars 桶设置为公开读
mc anonymous set download joylaw/avatars

echo "✅ 存储桶访问策略配置完成"

# 显示MinIO信息
echo ""
echo "========================================"
echo "✅ MinIO 初始化完成！"
echo "========================================"
echo ""
echo "MinIO 控制台访问地址:"
echo "  http://localhost:9001"
echo ""
echo "MinIO API地址:"
echo "  http://localhost:9000"
echo ""
echo "登录凭证:"
echo "  用户名: $MINIO_ACCESS_KEY"
echo "  密码: $MINIO_SECRET_KEY"
echo ""
echo "已创建的存储桶:"
for bucket in "${BUCKETS[@]}"; do
    echo "  - $bucket"
done
echo ""
echo "========================================"
echo "🎉 MinIO 服务已就绪！"
echo "========================================"

