#!/bin/bash
# =====================================================
# JoyLaw 数据库初始化脚本
# =====================================================

set -e  # 遇到错误立即退出

echo "========================================"
echo "JoyLaw 数据库初始化脚本"
echo "========================================"

# 读取环境变量
if [ -f .env ]; then
    # 过滤注释和空行，并去除行尾注释
    export $(cat .env | grep -v '^#' | grep -v '^$' | sed 's/#.*$//' | xargs)
    echo "✅ 已加载 .env 配置文件"
else
    echo "⚠️  未找到 .env 文件，使用默认配置"
    DB_USER=${DB_USER:-joylaw_user}
    DB_PASS=${DB_PASS:-your_secure_password}
    DB_HOST=${DB_HOST:-localhost}
    DB_PORT=${DB_PORT:-5432}
    DB_NAME=${DB_NAME:-joylaw}
fi

echo ""
echo "数据库配置:"
echo "  主机: $DB_HOST:$DB_PORT"
echo "  数据库: $DB_NAME"
echo "  用户: $DB_USER"
echo ""

# 检查PostgreSQL是否安装
if ! command -v psql &> /dev/null; then
    echo "❌ 未检测到 PostgreSQL，请先安装："
    echo "   Ubuntu/Debian: sudo apt install postgresql-15 postgresql-contrib-15"
    echo "   CentOS/RHEL:   sudo yum install postgresql15-server postgresql15-contrib"
    exit 1
fi

echo "✅ PostgreSQL 已安装"

# 检查pgvector扩展是否安装
echo ""
echo "检查 pgvector 扩展..."
if ! sudo -u postgres psql -c "SELECT * FROM pg_available_extensions WHERE name='vector';" | grep -q vector; then
    echo "⚠️  pgvector 扩展未安装，正在安装..."
    
    # 下载并安装pgvector
    cd /tmp
    if [ ! -d "pgvector" ]; then
        git clone https://github.com/pgvector/pgvector.git
    fi
    cd pgvector
    make clean
    make
    sudo make install
    
    echo "✅ pgvector 扩展安装完成"
else
    echo "✅ pgvector 扩展已安装"
fi

# 创建数据库和用户
echo ""
echo "创建数据库和用户..."

sudo -u postgres psql <<EOF
-- 创建用户（如果不存在）
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DB_USER') THEN
        CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
        RAISE NOTICE '✅ 用户 $DB_USER 创建成功';
    ELSE
        RAISE NOTICE '⚠️  用户 $DB_USER 已存在';
    END IF;
END
\$\$;

-- 创建数据库（如果不存在）
SELECT 'CREATE DATABASE $DB_NAME OWNER $DB_USER'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec

-- 授予权限
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

\c $DB_NAME

-- 授予schema权限
GRANT ALL ON SCHEMA public TO $DB_USER;
EOF

echo "✅ 数据库和用户创建完成"

# 执行建表SQL
echo ""
echo "执行建表脚本..."

PGPASSWORD=$DB_PASS psql -U $DB_USER -h $DB_HOST -p $DB_PORT -d $DB_NAME -f init_database.sql

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "✅ 数据库初始化完成！"
    echo "========================================"
    echo ""
    echo "默认管理员账户:"
    echo "  用户名: admin"
    echo "  密码: admin123"
    echo "  邮箱: admin@joylaw.com"
    echo ""
    echo "⚠️  请及时修改默认密码！"
    echo ""
else
    echo ""
    echo "❌ 数据库初始化失败，请检查错误信息"
    exit 1
fi

# 验证表是否创建成功
echo "验证表结构..."
TABLE_COUNT=$(PGPASSWORD=$DB_PASS psql -U $DB_USER -h $DB_HOST -p $DB_PORT -d $DB_NAME -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")

echo "✅ 已创建 $TABLE_COUNT 张表"

# 验证扩展
echo ""
echo "验证扩展安装..."
PGPASSWORD=$DB_PASS psql -U $DB_USER -h $DB_HOST -p $DB_PORT -d $DB_NAME -c "\dx" | grep -E "vector|pg_trgm"

echo ""
echo "========================================"
echo "🎉 一切就绪，可以启动服务了！"
echo "========================================"

