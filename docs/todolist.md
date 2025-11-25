## JoyLaw 项目开发任务清单

### ✅ 已完成
1. ~~设计数据库 - 登录注册、数据存储、项目存储、文件存储等~~ ✅
   - PostgreSQL + pgvector 数据库设计完成
   - 13张核心表（用户、项目、文件、双知识库、日志）
   - 自动触发器（用户注册创建公共资源、项目创建创建项目资源）
   - 软删除机制
   - 向量检索索引优化

### 🚀 进行中
2. **设计前端** - 登录页、项目页、知识库页
   - 需要根据数据库结构设计API接口
   - 需要设计前端路由和页面布局

3. **设计context** - 现在不认识上下文
   - 需要理解当前context处理机制
   - 需要设计项目间数据共享机制（公共知识库）

### 📋 待开发功能

#### Phase 1: 用户认证模块（预计1周）
- [ ] 用户注册API（POST /api/auth/register）
  - 自动创建公共文件夹和公共知识库
  - 密码bcrypt加密
- [ ] 用户登录API（POST /api/auth/login）
  - JWT token生成
  - Session记录
- [ ] Token刷新API（POST /api/auth/refresh）
- [ ] 用户信息查询API（GET /api/users/me）
- [ ] 登出API（POST /api/auth/logout）

#### Phase 2: 项目管理模块（预计1周）
- [ ] 创建项目API（POST /api/projects）
  - 自动创建项目文件夹
  - 自动创建项目知识库（双库：RAGFlow + GraphRAG）
- [ ] 项目列表API（GET /api/projects）
- [ ] 项目详情API（GET /api/projects/{id}）
- [ ] 更新项目API（PUT /api/projects/{id}）
- [ ] 删除项目API（DELETE /api/projects/{id}，软删除）

#### Phase 3: 文件管理模块（预计1周）
- [ ] 文件上传API（POST /api/files）
  - 支持上传到项目文件夹或公共文件夹
  - MinIO存储集成
  - 文件hash去重
- [ ] 文件列表API（GET /api/files）
  - 区分项目文件夹和公共文件夹
- [ ] 文件下载API（GET /api/files/{id}/download）
  - 生成MinIO预签名URL
- [ ] 文件删除API（DELETE /api/files/{id}，软删除）
- [ ] 文件移动API（POST /api/files/{id}/move）
  - 支持公共文件夹与项目文件夹间移动

#### Phase 4: 知识库管理模块（预计2周）
- [ ] 上传文档到知识库（POST /api/kb/{kb_id}/documents）
  - 文档解析（PDF/Word/Markdown等）
  - 文本分块（chunk）
- [ ] 文档向量化（Background Task）
  - OpenAI Embedding生成
  - 存储到kb_chunks表
- [ ] RAGFlow向量检索API（POST /api/kb/{kb_id}/search）
  - pgvector余弦相似度搜索
  - Top-K结果返回
- [ ] GraphRAG实体提取（POST /api/kb/{kb_id}/extract-entities）
  - NER实体识别
  - 实体存储到graph_entities表
- [ ] GraphRAG关系构建（POST /api/kb/{kb_id}/build-graph）
  - 关系抽取
  - 关系存储到graph_relations表
- [ ] 知识库切换API（PUT /api/kb/{kb_id}/config）
  - 切换RAGFlow/GraphRAG/双模式
- [ ] 文档列表API（GET /api/kb/{kb_id}/documents）
- [ ] 删除文档API（DELETE /api/kb/documents/{id}，软删除）

#### Phase 5: 日志管理模块（预计3天）
- [ ] 操作日志中间件（自动记录所有API请求）
- [ ] 查询操作日志API（GET /api/logs/operations）
- [ ] 查询系统日志API（GET /api/logs/system）
- [ ] 日志统计API（GET /api/logs/stats）

### 🛠️ 技术债务
- [ ] 数据迁移：SQLite → PostgreSQL（migrate_sqlite_to_postgres.py）
- [ ] 性能优化：向量索引调优（IVFFlat vs HNSW）
- [ ] 安全加固：修改默认密码、JWT密钥
- [ ] 备份策略：自动数据库备份脚本
- [ ] 监控告警：数据库连接池监控、MinIO存储监控

### 📚 文档
- [x] 数据库设计文档（database_design.md）
- [x] 快速开始指南（QUICK_START.md）
- [x] 安装清单（INSTALLATION_SUMMARY.md）
- [ ] API接口文档（待开发）
- [ ] 前端开发文档（待开发）

### 🎯 下一步行动
**立即执行：**
```bash
# 1. 初始化数据库
./setup_database.sh

# 2. 初始化MinIO
./setup_minio.sh

# 3. 验证安装
psql -U joylaw_user -h localhost -d joylaw -c "\dt"
mc ls joylaw

# 4. 开始开发用户认证API
```

### 💡 架构设计亮点
- ✅ PostgreSQL + pgvector 原生向量检索
- ✅ 双知识库架构（RAGFlow + GraphRAG）
- ✅ 自动资源创建（用户注册/项目创建触发器）
- ✅ 公共资源共享（跨项目文件和知识库）
- ✅ 软删除机制（数据安全）
- ✅ MinIO对象存储（S3兼容）

## JoyLaw 项目开发任务清单

### ✅ 已完成
1. ~~设计数据库 - 登录注册、数据存储、项目存储、文件存储等~~ ✅
   - PostgreSQL + pgvector 数据库设计完成
   - 13张核心表（用户、项目、文件、双知识库、日志）
   - 自动触发器（用户注册创建公共资源、项目创建创建项目资源）
   - 软删除机制
   - 向量检索索引优化

### 🚀 进行中
2. **设计前端** - 登录页、项目页、知识库页
   - 需要根据数据库结构设计API接口
   - 需要设计前端路由和页面布局

3. **设计context** - 现在不认识上下文
   - 需要理解当前context处理机制
   - 需要设计项目间数据共享机制（公共知识库）

### 📋 待开发功能

#### Phase 1: 用户认证模块（预计1周）
- [ ] 用户注册API（POST /api/auth/register）
  - 自动创建公共文件夹和公共知识库
  - 密码bcrypt加密
- [ ] 用户登录API（POST /api/auth/login）
  - JWT token生成
  - Session记录
- [ ] Token刷新API（POST /api/auth/refresh）
- [ ] 用户信息查询API（GET /api/users/me）
- [ ] 登出API（POST /api/auth/logout）

#### Phase 2: 项目管理模块（预计1周）
- [ ] 创建项目API（POST /api/projects）
  - 自动创建项目文件夹
  - 自动创建项目知识库（双库：RAGFlow + GraphRAG）
- [ ] 项目列表API（GET /api/projects）
- [ ] 项目详情API（GET /api/projects/{id}）
- [ ] 更新项目API（PUT /api/projects/{id}）
- [ ] 删除项目API（DELETE /api/projects/{id}，软删除）

#### Phase 3: 文件管理模块（预计1周）
- [ ] 文件上传API（POST /api/files）
  - 支持上传到项目文件夹或公共文件夹
  - MinIO存储集成
  - 文件hash去重
- [ ] 文件列表API（GET /api/files）
  - 区分项目文件夹和公共文件夹
- [ ] 文件下载API（GET /api/files/{id}/download）
  - 生成MinIO预签名URL
- [ ] 文件删除API（DELETE /api/files/{id}，软删除）
- [ ] 文件移动API（POST /api/files/{id}/move）
  - 支持公共文件夹与项目文件夹间移动

#### Phase 4: 知识库管理模块（预计2周）
- [ ] 上传文档到知识库（POST /api/kb/{kb_id}/documents）
  - 文档解析（PDF/Word/Markdown等）
  - 文本分块（chunk）
- [ ] 文档向量化（Background Task）
  - OpenAI Embedding生成
  - 存储到kb_chunks表
- [ ] RAGFlow向量检索API（POST /api/kb/{kb_id}/search）
  - pgvector余弦相似度搜索
  - Top-K结果返回
- [ ] GraphRAG实体提取（POST /api/kb/{kb_id}/extract-entities）
  - NER实体识别
  - 实体存储到graph_entities表
- [ ] GraphRAG关系构建（POST /api/kb/{kb_id}/build-graph）
  - 关系抽取
  - 关系存储到graph_relations表
- [ ] 知识库切换API（PUT /api/kb/{kb_id}/config）
  - 切换RAGFlow/GraphRAG/双模式
- [ ] 文档列表API（GET /api/kb/{kb_id}/documents）
- [ ] 删除文档API（DELETE /api/kb/documents/{id}，软删除）

#### Phase 5: 日志管理模块（预计3天）
- [ ] 操作日志中间件（自动记录所有API请求）
- [ ] 查询操作日志API（GET /api/logs/operations）
- [ ] 查询系统日志API（GET /api/logs/system）
- [ ] 日志统计API（GET /api/logs/stats）

### 🛠️ 技术债务
- [ ] 数据迁移：SQLite → PostgreSQL（migrate_sqlite_to_postgres.py）
- [ ] 性能优化：向量索引调优（IVFFlat vs HNSW）
- [ ] 安全加固：修改默认密码、JWT密钥
- [ ] 备份策略：自动数据库备份脚本
- [ ] 监控告警：数据库连接池监控、MinIO存储监控

### 📚 文档
- [x] 数据库设计文档（database_design.md）
- [x] 快速开始指南（QUICK_START.md）
- [x] 安装清单（INSTALLATION_SUMMARY.md）
- [ ] API接口文档（待开发）
- [ ] 前端开发文档（待开发）

### 🎯 下一步行动
**立即执行：**
```bash
# 1. 初始化数据库
./setup_database.sh

# 2. 初始化MinIO
./setup_minio.sh

# 3. 验证安装
psql -U joylaw_user -h localhost -d joylaw -c "\dt"
mc ls joylaw

# 4. 开始开发用户认证API
```

### 💡 架构设计亮点
- ✅ PostgreSQL + pgvector 原生向量检索
- ✅ 双知识库架构（RAGFlow + GraphRAG）
- ✅ 自动资源创建（用户注册/项目创建触发器）
- ✅ 公共资源共享（跨项目文件和知识库）
- ✅ 软删除机制（数据安全）
- ✅ MinIO对象存储（S3兼容）

