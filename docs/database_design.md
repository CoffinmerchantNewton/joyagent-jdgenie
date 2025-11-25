# JoyLaw 多智能体项目 - 数据库设计方案

## 一、技术选型

### 1.1 数据库：PostgreSQL 15+
- **向量检索**: pgvector扩展（RAG核心）
- **全文检索**: pg_trgm + GIN索引（中文分词）
- **JSON支持**: JSONB类型（知识图谱存储）
- **异步支持**: asyncpg（高性能）

### 1.2 对象存储：MinIO
- **文件管理**: 用户上传文件、知识库文档
- **访问方式**: S3兼容API
- **部署**: 单机模式（初期）→ 分布式（扩展期）

### 1.3 迁移策略
```python
# 从SQLite迁移到PostgreSQL只需改一行
# 原代码
engine = create_engine(f"sqlite:///{SQLITE_DB_PATH}")

# 新代码
engine = create_engine(f"postgresql+asyncpg://{USER}:{PASS}@{HOST}:{PORT}/{DB}")
```

---

## 二、核心表设计

### 2.1 用户认证模块

#### users - 用户表
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,  -- bcrypt加密
    full_name VARCHAR(100),
    avatar_url VARCHAR(255),  -- MinIO存储路径
    role VARCHAR(20) DEFAULT 'user',  -- admin/user/guest
    is_active BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_role CHECK (role IN ('admin', 'user', 'guest'))
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username);
```

#### user_sessions - 会话表
```sql
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(255) UNIQUE NOT NULL,  -- JWT token
    refresh_token VARCHAR(255),
    expires_at TIMESTAMP NOT NULL,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_token ON user_sessions(token);
CREATE INDEX idx_sessions_user ON user_sessions(user_id);
```

---

### 2.2 项目管理模块

#### projects - 项目表
```sql
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    owner_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'active',  -- active/archived/deleted
    config JSONB DEFAULT '{}',  -- 项目配置（智能体参数等）
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_status CHECK (status IN ('active', 'archived', 'deleted'))
);

CREATE INDEX idx_projects_owner ON projects(owner_id);
CREATE INDEX idx_projects_status ON projects(status);
```

#### project_members - 项目成员表
```sql
CREATE TABLE project_members (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member',  -- owner/admin/member/viewer
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(project_id, user_id),
    CONSTRAINT chk_member_role CHECK (role IN ('owner', 'admin', 'member', 'viewer'))
);

CREATE INDEX idx_project_members_project ON project_members(project_id);
CREATE INDEX idx_project_members_user ON project_members(user_id);
```

---

### 2.3 文件管理模块

#### files - 文件元数据表
```sql
CREATE TABLE files (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,  -- 原始文件名
    file_path VARCHAR(500) NOT NULL,  -- MinIO路径: bucket/path/file
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100),
    file_hash VARCHAR(64),  -- SHA256防重复上传
    
    -- 业务关联
    owner_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    
    -- 文件分类
    file_type VARCHAR(20),  -- document/image/video/other
    tags TEXT[],  -- 标签数组
    
    -- 状态管理
    status VARCHAR(20) DEFAULT 'active',  -- active/processing/deleted
    is_public BOOLEAN DEFAULT FALSE,
    
    -- 访问控制
    download_count INTEGER DEFAULT 0,
    last_accessed_at TIMESTAMP,
    
    -- 时间戳
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,  -- 软删除
    
    CONSTRAINT chk_file_status CHECK (status IN ('active', 'processing', 'deleted'))
);

CREATE INDEX idx_files_owner ON files(owner_id);
CREATE INDEX idx_files_project ON files(project_id);
CREATE INDEX idx_files_hash ON files(file_hash);
CREATE INDEX idx_files_type ON files(file_type);
CREATE INDEX idx_files_status ON files(status) WHERE status != 'deleted';
```

#### file_versions - 文件版本表（可选）
```sql
CREATE TABLE file_versions (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT NOT NULL,
    change_description TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(file_id, version_number)
);
```

---

### 2.4 知识库管理模块（核心！）

#### knowledge_bases - 知识库表
```sql
CREATE TABLE knowledge_bases (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    owner_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    
    -- 知识库类型
    kb_type VARCHAR(20) NOT NULL,  -- ragflow/graphrag/hybrid
    
    -- RAGFlow配置
    ragflow_dataset_id VARCHAR(100),  -- RAGFlow数据集ID
    ragflow_config JSONB,
    
    -- GraphRAG配置
    graphrag_config JSONB,
    
    -- 向量配置
    embedding_model VARCHAR(50) DEFAULT 'text-embedding-3-small',
    embedding_dim INTEGER DEFAULT 1536,
    chunk_size INTEGER DEFAULT 500,
    chunk_overlap INTEGER DEFAULT 50,
    
    -- 统计信息
    document_count INTEGER DEFAULT 0,
    total_chunks INTEGER DEFAULT 0,
    last_updated_at TIMESTAMP,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_kb_type CHECK (kb_type IN ('ragflow', 'graphrag', 'hybrid'))
);

CREATE INDEX idx_kb_owner ON knowledge_bases(owner_id);
CREATE INDEX idx_kb_project ON knowledge_bases(project_id);
CREATE INDEX idx_kb_type ON knowledge_bases(kb_type);
```

#### kb_documents - 知识库文档表
```sql
CREATE TABLE kb_documents (
    id SERIAL PRIMARY KEY,
    kb_id INTEGER REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    
    title VARCHAR(255) NOT NULL,
    content TEXT,  -- 提取的文本内容
    metadata JSONB,  -- 文档元数据
    
    -- 处理状态
    status VARCHAR(20) DEFAULT 'pending',  -- pending/processing/completed/failed
    error_message TEXT,
    
    -- 统计
    chunk_count INTEGER DEFAULT 0,
    processed_at TIMESTAMP,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_doc_status CHECK (status IN ('pending', 'processing', 'completed', 'failed'))
);

CREATE INDEX idx_kb_docs_kb ON kb_documents(kb_id);
CREATE INDEX idx_kb_docs_file ON kb_documents(file_id);
CREATE INDEX idx_kb_docs_status ON kb_documents(status);
```

#### kb_chunks - 文档块表（向量检索核心）
```sql
-- 启用pgvector扩展
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE kb_chunks (
    id SERIAL PRIMARY KEY,
    document_id INTEGER REFERENCES kb_documents(id) ON DELETE CASCADE,
    kb_id INTEGER REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    
    -- 文本内容
    chunk_text TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,  -- 在文档中的位置
    
    -- 向量嵌入（核心！）
    embedding vector(1536),  -- 根据模型调整维度
    
    -- 元数据
    metadata JSONB,  -- 页码、章节等
    token_count INTEGER,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(document_id, chunk_index)
);

-- 向量相似度检索索引（IVFFlat适合大规模数据）
CREATE INDEX idx_chunks_embedding ON kb_chunks 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- 传统索引
CREATE INDEX idx_chunks_document ON kb_chunks(document_id);
CREATE INDEX idx_chunks_kb ON kb_chunks(kb_id);

-- 全文检索索引（中文支持）
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_chunks_text_trgm ON kb_chunks USING gin(chunk_text gin_trgm_ops);
```

#### graph_entities - 知识图谱实体表（GraphRAG）
```sql
CREATE TABLE graph_entities (
    id SERIAL PRIMARY KEY,
    kb_id INTEGER REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    
    entity_id VARCHAR(100) UNIQUE NOT NULL,  -- 实体唯一标识
    entity_type VARCHAR(50) NOT NULL,  -- person/organization/concept等
    entity_name VARCHAR(255) NOT NULL,
    
    description TEXT,
    properties JSONB,  -- 实体属性
    
    -- 向量嵌入（用于实体检索）
    embedding vector(1536),
    
    source_document_ids INTEGER[],  -- 来源文档
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_entities_kb ON graph_entities(kb_id);
CREATE INDEX idx_entities_type ON graph_entities(entity_type);
CREATE INDEX idx_entities_embedding ON graph_entities 
USING ivfflat (embedding vector_cosine_ops);
```

#### graph_relations - 知识图谱关系表
```sql
CREATE TABLE graph_relations (
    id SERIAL PRIMARY KEY,
    kb_id INTEGER REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    
    source_entity_id VARCHAR(100) REFERENCES graph_entities(entity_id) ON DELETE CASCADE,
    target_entity_id VARCHAR(100) REFERENCES graph_entities(entity_id) ON DELETE CASCADE,
    relation_type VARCHAR(50) NOT NULL,
    
    weight FLOAT DEFAULT 1.0,  -- 关系强度
    properties JSONB,
    
    source_document_ids INTEGER[],
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(source_entity_id, target_entity_id, relation_type)
);

CREATE INDEX idx_relations_source ON graph_relations(source_entity_id);
CREATE INDEX idx_relations_target ON graph_relations(target_entity_id);
CREATE INDEX idx_relations_type ON graph_relations(relation_type);
```

---

### 2.5 日志管理模块

#### operation_logs - 操作日志表
```sql
CREATE TABLE operation_logs (
    id BIGSERIAL PRIMARY KEY,  -- 日志量大用BIGSERIAL
    
    -- 用户信息
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    username VARCHAR(50),
    
    -- 操作信息
    operation_type VARCHAR(50) NOT NULL,  -- login/upload/query/create等
    resource_type VARCHAR(50),  -- project/file/kb等
    resource_id INTEGER,
    
    -- 请求信息
    method VARCHAR(10),  -- GET/POST/PUT/DELETE
    path VARCHAR(500),
    request_params JSONB,
    
    -- 响应信息
    status_code INTEGER,
    response_time_ms INTEGER,  -- 响应时间（毫秒）
    
    -- 环境信息
    ip_address INET,
    user_agent TEXT,
    
    -- 错误信息
    error_message TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 分区表优化（按月分区）
CREATE INDEX idx_logs_user ON operation_logs(user_id);
CREATE INDEX idx_logs_created ON operation_logs(created_at DESC);
CREATE INDEX idx_logs_operation ON operation_logs(operation_type);
CREATE INDEX idx_logs_resource ON operation_logs(resource_type, resource_id);
```

#### system_logs - 系统日志表
```sql
CREATE TABLE system_logs (
    id BIGSERIAL PRIMARY KEY,
    
    service_name VARCHAR(50) NOT NULL,  -- genie-backend/genie-tool等
    log_level VARCHAR(10) NOT NULL,  -- DEBUG/INFO/WARN/ERROR
    
    message TEXT NOT NULL,
    context JSONB,  -- 日志上下文
    
    trace_id VARCHAR(100),  -- 分布式追踪ID
    span_id VARCHAR(100),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_system_logs_service ON system_logs(service_name);
CREATE INDEX idx_system_logs_level ON system_logs(log_level);
CREATE INDEX idx_system_logs_created ON system_logs(created_at DESC);
CREATE INDEX idx_system_logs_trace ON system_logs(trace_id);
```

---

## 三、MinIO存储结构设计

### 3.1 Bucket规划
```
joylaw/
├── avatars/              # 用户头像
│   └── {user_id}/
│       └── avatar.jpg
├── project-files/        # 项目文件
│   └── {project_id}/
│       └── {file_id}/
│           ├── original.pdf
│           └── versions/
├── kb-documents/         # 知识库文档
│   └── {kb_id}/
│       └── {document_id}.pdf
└── temp/                 # 临时文件（定期清理）
    └── uploads/
```

### 3.2 MinIO配置示例
```python
from minio import Minio

minio_client = Minio(
    "localhost:9000",
    access_key="minioadmin",
    secret_key="minioadmin",
    secure=False
)

# 创建bucket
buckets = ["avatars", "project-files", "kb-documents", "temp"]
for bucket in buckets:
    if not minio_client.bucket_exists(bucket):
        minio_client.make_bucket(bucket)
```

---

## 四、数据库优化建议

### 4.1 连接池配置
```python
# genie-tool/genie_tool/db/db_engine.py
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

DATABASE_URL = "postgresql+asyncpg://user:pass@localhost:5432/joylaw"

async_engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,          # 连接池大小
    max_overflow=10,       # 最大溢出连接
    pool_recycle=3600,     # 连接回收时间
    pool_pre_ping=True,    # 连接健康检查
    echo=False,            # 生产环境关闭SQL日志
)

AsyncSessionLocal = sessionmaker(
    async_engine,
    class_=AsyncSession,
    expire_on_commit=False
)
```

### 4.2 性能优化
```sql
-- 1. 定期VACUUM（自动清理）
ALTER TABLE kb_chunks SET (autovacuum_vacuum_scale_factor = 0.05);

-- 2. 向量索引调优
-- 对于>100万条数据，使用HNSW索引（需PostgreSQL 13+）
CREATE INDEX idx_chunks_embedding_hnsw ON kb_chunks 
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- 3. 分区表（日志表）
-- 按月分区
CREATE TABLE operation_logs_2025_01 PARTITION OF operation_logs
FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- 4. 物化视图（统计查询）
CREATE MATERIALIZED VIEW project_statistics AS
SELECT 
    p.id,
    p.name,
    COUNT(DISTINCT f.id) as file_count,
    COUNT(DISTINCT kb.id) as kb_count,
    SUM(f.file_size) as total_size
FROM projects p
LEFT JOIN files f ON f.project_id = p.id
LEFT JOIN knowledge_bases kb ON kb.project_id = p.id
GROUP BY p.id, p.name;

CREATE UNIQUE INDEX ON project_statistics(id);
```

### 4.3 备份策略
```bash
#!/bin/bash
# backup.sh

# 数据库备份
pg_dump -U user -h localhost joylaw | gzip > backup_$(date +%Y%m%d).sql.gz

# MinIO备份（使用mc工具）
mc mirror local/joylaw backup-server/joylaw-backup
```

---

## 五、迁移实施步骤

### Step 1: 安装PostgreSQL和MinIO
```bash
# PostgreSQL 15
sudo apt install postgresql-15 postgresql-contrib-15

# pgvector扩展
cd /tmp
git clone https://github.com/pgvector/pgvector.git
cd pgvector
make
sudo make install

# MinIO（Docker方式）
docker run -d \
  -p 9000:9000 \
  -p 9001:9001 \
  --name minio \
  -v ~/minio/data:/data \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin" \
  minio/minio server /data --console-address ":9001"
```

### Step 2: 创建数据库和用户
```sql
-- 以postgres用户登录
sudo -u postgres psql

CREATE DATABASE joylaw;
CREATE USER joylaw_user WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE joylaw TO joylaw_user;

-- 切换到joylaw数据库
\c joylaw

-- 安装扩展
CREATE EXTENSION vector;
CREATE EXTENSION pg_trgm;
```

### Step 3: 执行表结构创建
```bash
# 将上述所有CREATE TABLE语句保存为schema.sql
psql -U joylaw_user -d joylaw -f schema.sql
```

### Step 4: 修改genie-tool配置
```python
# genie-tool/genie_tool/db/db_engine.py

import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# 环境变量配置
DB_USER = os.getenv("DB_USER", "joylaw_user")
DB_PASS = os.getenv("DB_PASS", "your_secure_password")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "joylaw")

DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

async_engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,
    max_overflow=10,
    pool_recycle=3600,
    pool_pre_ping=True,
    echo=False,
)

AsyncSessionLocal = sessionmaker(
    async_engine,
    class_=AsyncSession,
    expire_on_commit=False
)

async def get_async_session():
    async with AsyncSessionLocal() as session:
        yield session
```

### Step 5: 数据迁移脚本（SQLite → PostgreSQL）
```python
# migrate_data.py

import asyncio
from sqlalchemy import create_engine, select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from genie_tool.model.file_info import FileInfo

# 原SQLite数据库
sqlite_engine = create_engine("sqlite:///autobots.db")

# 新PostgreSQL数据库
pg_engine = create_async_engine("postgresql+asyncpg://...")

async def migrate():
    # 从SQLite读取
    with sqlite_engine.connect() as conn:
        result = conn.execute(select(FileInfo))
        old_files = result.fetchall()
    
    # 写入PostgreSQL
    async with AsyncSession(pg_engine) as session:
        for old_file in old_files:
            # 映射字段到新的files表
            new_file = {
                "filename": old_file.filename,
                "original_filename": old_file.filename,
                "file_path": old_file.file_path,
                "file_size": old_file.file_size,
                "status": "active" if old_file.status == 1 else "deleted",
                # ... 其他字段
            }
            session.add(Files(**new_file))
        
        await session.commit()
    
    print(f"迁移完成：{len(old_files)} 条记录")

if __name__ == "__main__":
    asyncio.run(migrate())
```

---

## 六、开发建议

### 6.1 使用SQLModel简化开发
```python
# genie-tool/genie_tool/models/user.py

from sqlmodel import SQLModel, Field
from datetime import datetime
from typing import Optional

class User(SQLModel, table=True):
    __tablename__ = "users"
    
    id: Optional[int] = Field(default=None, primary_key=True)
    username: str = Field(max_length=50, unique=True, index=True)
    email: str = Field(max_length=100, unique=True, index=True)
    password_hash: str
    full_name: Optional[str] = None
    role: str = Field(default="user")
    is_active: bool = Field(default=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)
```

### 6.2 向量检索示例
```python
# 向量相似度搜索
async def search_similar_chunks(
    session: AsyncSession,
    query_embedding: list[float],
    kb_id: int,
    top_k: int = 10
):
    from sqlalchemy import text
    
    query = text("""
        SELECT 
            id, 
            chunk_text, 
            metadata,
            1 - (embedding <=> :query_embedding) as similarity
        FROM kb_chunks
        WHERE kb_id = :kb_id
        ORDER BY embedding <=> :query_embedding
        LIMIT :top_k
    """)
    
    result = await session.execute(
        query,
        {
            "query_embedding": str(query_embedding),
            "kb_id": kb_id,
            "top_k": top_k
        }
    )
    
    return result.fetchall()
```

### 6.3 MinIO文件操作封装
```python
# genie-tool/genie_tool/storage/minio_client.py

from minio import Minio
from typing import BinaryIO
import os

class MinIOClient:
    def __init__(self):
        self.client = Minio(
            os.getenv("MINIO_ENDPOINT", "localhost:9000"),
            access_key=os.getenv("MINIO_ACCESS_KEY"),
            secret_key=os.getenv("MINIO_SECRET_KEY"),
            secure=False
        )
    
    async def upload_file(
        self, 
        bucket: str, 
        object_name: str, 
        file_data: BinaryIO,
        content_type: str
    ):
        """上传文件到MinIO"""
        self.client.put_object(
            bucket,
            object_name,
            file_data,
            length=-1,  # 未知大小
            part_size=10*1024*1024,  # 10MB分片
            content_type=content_type
        )
        
        return f"{bucket}/{object_name}"
    
    def get_presigned_url(self, bucket: str, object_name: str, expires=3600):
        """生成预签名URL（用于文件下载/预览）"""
        return self.client.presigned_get_object(bucket, object_name, expires)
```

---

## 七、成本与性能对比

| 指标 | SQLite | MySQL | PostgreSQL + pgvector | 推荐指数 |
|------|--------|-------|-----------------------|---------|
| 向量检索 | ❌ 不支持 | ⚠️ 需外部服务 | ✅ 原生支持 | ⭐⭐⭐⭐⭐ |
| 并发性能 | ⚠️ 写入锁 | ✅ 良好 | ✅ 优秀 | ⭐⭐⭐⭐⭐ |
| JSON支持 | ⚠️ 有限 | ✅ 支持 | ✅ JSONB索引 | ⭐⭐⭐⭐⭐ |
| 学习成本 | ✅ 最低 | ✅ 低 | ⚠️ 中等 | ⭐⭐⭐⭐ |
| 运维成本 | ✅ 零 | ⚠️ 中 | ⚠️ 中 | ⭐⭐⭐⭐ |
| 扩展性 | ❌ 单机 | ✅ 主从 | ✅ 主从+分片 | ⭐⭐⭐⭐⭐ |
| 生态支持 | ⚠️ 有限 | ✅ 丰富 | ✅ AI领域主流 | ⭐⭐⭐⭐⭐ |

---

## 八、总结

### ✅ 推荐方案
**PostgreSQL 15 + pgvector + MinIO**

### 📌 核心理由
1. **RAG刚需**：pgvector是生产级向量检索方案，避免额外引入Milvus/Qdrant
2. **一步到位**：初期简单部署，后期无痛扩展
3. **学习成本低**：SQL语法95%兼容MySQL，Python生态完善
4. **生态优势**：LangChain/LlamaIndex等RAG框架首选PostgreSQL

### 🚀 实施路径
```
第1周：PostgreSQL + MinIO环境搭建，基础表创建
第2周：用户认证、项目管理模块开发
第3周：文件管理 + MinIO集成
第4周：RAGFlow知识库集成（pgvector检索）
第5周：GraphRAG集成（实体关系图谱）
第6周：日志系统、权限控制完善
```

### 💡 风险提示
- PostgreSQL初次使用需1-2天熟悉（但SQL差异极小）
- 向量索引调优需根据数据量调整（IVFFlat vs HNSW）
- MinIO需配置nginx反向代理（生产环境）

---

**需要我协助你开始实施吗？我可以帮你：**
1. 生成完整的表创建SQL脚本
2. 编写数据迁移脚本
3. 封装PostgreSQL + MinIO的工具类
4. 设计用户认证API接口

