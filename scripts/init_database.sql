-- =====================================================
-- JoyLaw 多智能体项目 - PostgreSQL 数据库初始化脚本
-- =====================================================

-- 启用必要的扩展
CREATE EXTENSION IF NOT EXISTS vector;      -- 向量检索
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- 全文检索
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; -- UUID生成

-- =====================================================
-- 1. 用户认证模块
-- =====================================================

-- 用户表
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    avatar_url VARCHAR(255),
    role VARCHAR(20) DEFAULT 'user',
    is_active BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    
    CONSTRAINT chk_role CHECK (role IN ('admin', 'user', 'guest'))
);

CREATE INDEX idx_users_email ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_username ON users(username) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_deleted ON users(deleted_at);

COMMENT ON TABLE users IS '用户表';
COMMENT ON COLUMN users.role IS '用户角色: admin/user/guest';
COMMENT ON COLUMN users.deleted_at IS '软删除时间戳';

-- 用户会话表
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(500) UNIQUE NOT NULL,
    refresh_token VARCHAR(500),
    expires_at TIMESTAMP NOT NULL,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_token ON user_sessions(token);
CREATE INDEX idx_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at);

COMMENT ON TABLE user_sessions IS '用户会话表（JWT token管理）';

-- =====================================================
-- 2. 项目管理模块
-- =====================================================

-- 项目表（一个项目仅属于一个用户，不支持协作）
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'active',
    config JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    
    CONSTRAINT chk_project_status CHECK (status IN ('active', 'archived', 'deleted'))
);

CREATE INDEX idx_projects_owner ON projects(owner_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_projects_status ON projects(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_projects_deleted ON projects(deleted_at);

COMMENT ON TABLE projects IS '项目表（不支持多人协作）';
COMMENT ON COLUMN projects.status IS '项目状态: active/archived/deleted';
COMMENT ON COLUMN projects.config IS '项目配置（智能体参数等）';

-- =====================================================
-- 3. 文件夹和文件管理模块
-- =====================================================

-- 文件夹表（区分：项目文件夹 vs 公共文件夹）
CREATE TABLE folders (
    id SERIAL PRIMARY KEY,
    folder_name VARCHAR(100) NOT NULL,
    folder_type VARCHAR(20) NOT NULL,
    owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    minio_path VARCHAR(500) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    
    CONSTRAINT chk_folder_type CHECK (folder_type IN ('project', 'public')),
    CONSTRAINT chk_project_folder CHECK (
        (folder_type = 'project' AND project_id IS NOT NULL) OR
        (folder_type = 'public' AND project_id IS NULL)
    )
);

CREATE INDEX idx_folders_owner ON folders(owner_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_folders_project ON folders(project_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_folders_type ON folders(folder_type) WHERE deleted_at IS NULL;
CREATE INDEX idx_folders_deleted ON folders(deleted_at);

COMMENT ON TABLE folders IS '文件夹表（project=项目文件夹, public=公共文件夹）';
COMMENT ON COLUMN folders.folder_type IS '文件夹类型: project=项目文件夹, public=用户公共文件夹';
COMMENT ON COLUMN folders.project_id IS '项目ID（仅project类型有值）';
COMMENT ON COLUMN folders.minio_path IS 'MinIO存储路径';

-- 文件表
CREATE TABLE files (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100),
    file_hash VARCHAR(64),
    file_type VARCHAR(20),
    tags TEXT[],
    metadata JSONB DEFAULT '{}',
    owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'active',
    download_count INTEGER DEFAULT 0,
    last_accessed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    
    CONSTRAINT chk_file_status CHECK (status IN ('active', 'processing', 'deleted'))
);

CREATE INDEX idx_files_folder ON files(folder_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_files_owner ON files(owner_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_files_hash ON files(file_hash);
CREATE INDEX idx_files_type ON files(file_type) WHERE deleted_at IS NULL;
CREATE INDEX idx_files_status ON files(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_files_deleted ON files(deleted_at);

COMMENT ON TABLE files IS '文件表';
COMMENT ON COLUMN files.file_path IS 'MinIO完整路径: bucket/path/file';
COMMENT ON COLUMN files.file_hash IS 'SHA256哈希值（用于去重）';
COMMENT ON COLUMN files.file_type IS '文件类型: document/image/video/other';
COMMENT ON COLUMN files.status IS '文件状态: active/processing/deleted';

-- =====================================================
-- 4. 知识库管理模块（双知识库：RAGFlow + GraphRAG）
-- =====================================================

-- 知识库表（区分：项目知识库 vs 公共知识库，都是双库）
CREATE TABLE knowledge_bases (
    id SERIAL PRIMARY KEY,
    kb_name VARCHAR(100) NOT NULL,
    description TEXT,
    kb_type VARCHAR(20) NOT NULL,
    owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    
    -- RAGFlow配置
    ragflow_dataset_id VARCHAR(100),
    ragflow_config JSONB DEFAULT '{}',
    ragflow_enabled BOOLEAN DEFAULT TRUE,
    
    -- GraphRAG配置
    graphrag_config JSONB DEFAULT '{}',
    graphrag_enabled BOOLEAN DEFAULT TRUE,
    
    -- 向量配置
    embedding_model VARCHAR(50) DEFAULT 'text-embedding-3-small',
    embedding_dim INTEGER DEFAULT 1536,
    chunk_size INTEGER DEFAULT 500,
    chunk_overlap INTEGER DEFAULT 50,
    
    -- 统计信息
    document_count INTEGER DEFAULT 0,
    total_chunks INTEGER DEFAULT 0,
    entity_count INTEGER DEFAULT 0,
    relation_count INTEGER DEFAULT 0,
    
    last_updated_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    
    CONSTRAINT chk_kb_type CHECK (kb_type IN ('project', 'public')),
    CONSTRAINT chk_project_kb CHECK (
        (kb_type = 'project' AND project_id IS NOT NULL) OR
        (kb_type = 'public' AND project_id IS NULL)
    )
);

CREATE INDEX idx_kb_owner ON knowledge_bases(owner_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_kb_project ON knowledge_bases(project_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_kb_type ON knowledge_bases(kb_type) WHERE deleted_at IS NULL;
CREATE INDEX idx_kb_deleted ON knowledge_bases(deleted_at);

COMMENT ON TABLE knowledge_bases IS '知识库表（双库：RAGFlow+GraphRAG）';
COMMENT ON COLUMN knowledge_bases.kb_type IS '知识库类型: project=项目知识库, public=用户公共知识库';
COMMENT ON COLUMN knowledge_bases.ragflow_enabled IS '是否启用RAGFlow检索';
COMMENT ON COLUMN knowledge_bases.graphrag_enabled IS '是否启用GraphRAG检索';
COMMENT ON COLUMN knowledge_bases.project_id IS '项目ID（仅project类型有值）';

-- 知识库文档表
CREATE TABLE kb_documents (
    id SERIAL PRIMARY KEY,
    kb_id INTEGER NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    file_id INTEGER REFERENCES files(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    content TEXT,
    metadata JSONB DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'pending',
    error_message TEXT,
    chunk_count INTEGER DEFAULT 0,
    processed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    
    CONSTRAINT chk_doc_status CHECK (status IN ('pending', 'processing', 'completed', 'failed'))
);

CREATE INDEX idx_kb_docs_kb ON kb_documents(kb_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_kb_docs_file ON kb_documents(file_id);
CREATE INDEX idx_kb_docs_status ON kb_documents(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_kb_docs_deleted ON kb_documents(deleted_at);

COMMENT ON TABLE kb_documents IS '知识库文档表';
COMMENT ON COLUMN kb_documents.status IS '处理状态: pending/processing/completed/failed';

-- 文档块表（向量检索核心 - RAGFlow）
CREATE TABLE kb_chunks (
    id SERIAL PRIMARY KEY,
    document_id INTEGER NOT NULL REFERENCES kb_documents(id) ON DELETE CASCADE,
    kb_id INTEGER NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    chunk_text TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    embedding vector(1536),
    metadata JSONB DEFAULT '{}',
    token_count INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(document_id, chunk_index)
);

-- 向量相似度检索索引（IVFFlat适合百万级数据）
CREATE INDEX idx_chunks_embedding_ivfflat ON kb_chunks 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- 传统索引
CREATE INDEX idx_chunks_document ON kb_chunks(document_id);
CREATE INDEX idx_chunks_kb ON kb_chunks(kb_id);

-- 全文检索索引
CREATE INDEX idx_chunks_text_trgm ON kb_chunks 
USING gin(chunk_text gin_trgm_ops);

COMMENT ON TABLE kb_chunks IS '文档块表（RAGFlow向量检索）';
COMMENT ON COLUMN kb_chunks.embedding IS '向量嵌入（维度根据模型调整）';
COMMENT ON COLUMN kb_chunks.chunk_index IS '在文档中的位置序号';

-- 知识图谱实体表（GraphRAG）
CREATE TABLE graph_entities (
    id SERIAL PRIMARY KEY,
    kb_id INTEGER NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    entity_id VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_name VARCHAR(255) NOT NULL,
    description TEXT,
    properties JSONB DEFAULT '{}',
    embedding vector(1536),
    source_document_ids INTEGER[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(kb_id, entity_id)
);

CREATE INDEX idx_entities_kb ON graph_entities(kb_id);
CREATE INDEX idx_entities_type ON graph_entities(entity_type);
CREATE INDEX idx_entities_name ON graph_entities(entity_name);
CREATE INDEX idx_entities_embedding_ivfflat ON graph_entities 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

COMMENT ON TABLE graph_entities IS '知识图谱实体表（GraphRAG）';
COMMENT ON COLUMN graph_entities.entity_type IS '实体类型: person/organization/concept等';
COMMENT ON COLUMN graph_entities.source_document_ids IS '来源文档ID数组';

-- 知识图谱关系表（GraphRAG）
CREATE TABLE graph_relations (
    id SERIAL PRIMARY KEY,
    kb_id INTEGER NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
    source_entity_id VARCHAR(100) NOT NULL,
    target_entity_id VARCHAR(100) NOT NULL,
    relation_type VARCHAR(50) NOT NULL,
    weight FLOAT DEFAULT 1.0,
    properties JSONB DEFAULT '{}',
    source_document_ids INTEGER[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_source_entity FOREIGN KEY (kb_id, source_entity_id) 
        REFERENCES graph_entities(kb_id, entity_id) ON DELETE CASCADE,
    CONSTRAINT fk_target_entity FOREIGN KEY (kb_id, target_entity_id) 
        REFERENCES graph_entities(kb_id, entity_id) ON DELETE CASCADE
);

CREATE INDEX idx_relations_kb ON graph_relations(kb_id);
CREATE INDEX idx_relations_source ON graph_relations(source_entity_id);
CREATE INDEX idx_relations_target ON graph_relations(target_entity_id);
CREATE INDEX idx_relations_type ON graph_relations(relation_type);

COMMENT ON TABLE graph_relations IS '知识图谱关系表（GraphRAG）';
COMMENT ON COLUMN graph_relations.weight IS '关系强度权重';
COMMENT ON COLUMN graph_relations.relation_type IS '关系类型';

-- =====================================================
-- 5. 日志管理模块
-- =====================================================

-- 操作日志表
CREATE TABLE operation_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    username VARCHAR(50),
    operation_type VARCHAR(50) NOT NULL,
    resource_type VARCHAR(50),
    resource_id INTEGER,
    method VARCHAR(10),
    path VARCHAR(500),
    request_params JSONB,
    status_code INTEGER,
    response_time_ms INTEGER,
    ip_address INET,
    user_agent TEXT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_logs_user ON operation_logs(user_id);
CREATE INDEX idx_logs_created ON operation_logs(created_at DESC);
CREATE INDEX idx_logs_operation ON operation_logs(operation_type);
CREATE INDEX idx_logs_resource ON operation_logs(resource_type, resource_id);

COMMENT ON TABLE operation_logs IS '用户操作日志表';
COMMENT ON COLUMN operation_logs.operation_type IS '操作类型: login/upload/query/create等';
COMMENT ON COLUMN operation_logs.response_time_ms IS '响应时间（毫秒）';

-- 系统日志表
CREATE TABLE system_logs (
    id BIGSERIAL PRIMARY KEY,
    service_name VARCHAR(50) NOT NULL,
    log_level VARCHAR(10) NOT NULL,
    message TEXT NOT NULL,
    context JSONB DEFAULT '{}',
    trace_id VARCHAR(100),
    span_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_system_logs_service ON system_logs(service_name);
CREATE INDEX idx_system_logs_level ON system_logs(log_level);
CREATE INDEX idx_system_logs_created ON system_logs(created_at DESC);
CREATE INDEX idx_system_logs_trace ON system_logs(trace_id);

COMMENT ON TABLE system_logs IS '系统日志表（微服务日志）';
COMMENT ON COLUMN system_logs.log_level IS '日志级别: DEBUG/INFO/WARN/ERROR';
COMMENT ON COLUMN system_logs.trace_id IS '分布式追踪ID';

-- =====================================================
-- 6. 触发器：自动更新 updated_at
-- =====================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 应用到需要的表
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_projects_updated_at BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_folders_updated_at BEFORE UPDATE ON folders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_files_updated_at BEFORE UPDATE ON files
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_knowledge_bases_updated_at BEFORE UPDATE ON knowledge_bases
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_kb_documents_updated_at BEFORE UPDATE ON kb_documents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_graph_entities_updated_at BEFORE UPDATE ON graph_entities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- 7. 触发器：自动创建公共文件夹和知识库
-- =====================================================

CREATE OR REPLACE FUNCTION create_user_public_resources()
RETURNS TRIGGER AS $$
BEGIN
    -- 创建用户公共文件夹
    INSERT INTO folders (folder_name, folder_type, owner_id, minio_path)
    VALUES (
        NEW.username || '_public_folder',
        'public',
        NEW.id,
        'public-folders/' || NEW.id || '/'
    );
    
    -- 创建用户公共知识库
    INSERT INTO knowledge_bases (kb_name, description, kb_type, owner_id)
    VALUES (
        NEW.username || '的公共知识库',
        '个人公共知识库，可在所有项目中共享',
        'public',
        NEW.id
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_create_user_public_resources
AFTER INSERT ON users
FOR EACH ROW EXECUTE FUNCTION create_user_public_resources();

COMMENT ON FUNCTION create_user_public_resources() IS '用户注册时自动创建公共文件夹和知识库';

-- =====================================================
-- 8. 触发器：项目创建时自动创建文件夹和知识库
-- =====================================================

CREATE OR REPLACE FUNCTION create_project_resources()
RETURNS TRIGGER AS $$
BEGIN
    -- 创建项目文件夹
    INSERT INTO folders (folder_name, folder_type, owner_id, project_id, minio_path)
    VALUES (
        NEW.name || '_folder',
        'project',
        NEW.owner_id,
        NEW.id,
        'project-folders/' || NEW.id || '/'
    );
    
    -- 创建项目知识库
    INSERT INTO knowledge_bases (kb_name, description, kb_type, owner_id, project_id)
    VALUES (
        NEW.name || '知识库',
        '项目专属知识库',
        'project',
        NEW.owner_id,
        NEW.id
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_create_project_resources
AFTER INSERT ON projects
FOR EACH ROW EXECUTE FUNCTION create_project_resources();

COMMENT ON FUNCTION create_project_resources() IS '项目创建时自动创建文件夹和知识库';

-- =====================================================
-- 9. 触发器：更新统计信息
-- =====================================================

-- 更新知识库文档计数
CREATE OR REPLACE FUNCTION update_kb_document_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE knowledge_bases 
        SET document_count = document_count + 1,
            last_updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.kb_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE knowledge_bases 
        SET document_count = GREATEST(document_count - 1, 0),
            last_updated_at = CURRENT_TIMESTAMP
        WHERE id = OLD.kb_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_kb_document_count
AFTER INSERT OR DELETE ON kb_documents
FOR EACH ROW EXECUTE FUNCTION update_kb_document_count();

-- 更新知识库chunk计数
CREATE OR REPLACE FUNCTION update_kb_chunk_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE knowledge_bases 
        SET total_chunks = total_chunks + 1,
            last_updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.kb_id;
        
        UPDATE kb_documents
        SET chunk_count = chunk_count + 1
        WHERE id = NEW.document_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE knowledge_bases 
        SET total_chunks = GREATEST(total_chunks - 1, 0),
            last_updated_at = CURRENT_TIMESTAMP
        WHERE id = OLD.kb_id;
        
        UPDATE kb_documents
        SET chunk_count = GREATEST(chunk_count - 1, 0)
        WHERE id = OLD.document_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_kb_chunk_count
AFTER INSERT OR DELETE ON kb_chunks
FOR EACH ROW EXECUTE FUNCTION update_kb_chunk_count();

-- 更新知识库实体计数
CREATE OR REPLACE FUNCTION update_kb_entity_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE knowledge_bases 
        SET entity_count = entity_count + 1,
            last_updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.kb_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE knowledge_bases 
        SET entity_count = GREATEST(entity_count - 1, 0),
            last_updated_at = CURRENT_TIMESTAMP
        WHERE id = OLD.kb_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_kb_entity_count
AFTER INSERT OR DELETE ON graph_entities
FOR EACH ROW EXECUTE FUNCTION update_kb_entity_count();

-- 更新知识库关系计数
CREATE OR REPLACE FUNCTION update_kb_relation_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE knowledge_bases 
        SET relation_count = relation_count + 1,
            last_updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.kb_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE knowledge_bases 
        SET relation_count = GREATEST(relation_count - 1, 0),
            last_updated_at = CURRENT_TIMESTAMP
        WHERE id = OLD.kb_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_kb_relation_count
AFTER INSERT OR DELETE ON graph_relations
FOR EACH ROW EXECUTE FUNCTION update_kb_relation_count();

-- =====================================================
-- 10. 初始数据：创建默认管理员账户
-- =====================================================

-- 默认密码: admin123 (bcrypt加密后的hash)
INSERT INTO users (username, email, password_hash, full_name, role)
VALUES (
    'admin',
    'admin@joylaw.com',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5PmJy9qTy8K.i',
    '系统管理员',
    'admin'
);

-- =====================================================
-- 完成提示
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'JoyLaw 数据库初始化完成！';
    RAISE NOTICE '===========================================';
    RAISE NOTICE '✅ 已创建 13 张核心表';
    RAISE NOTICE '✅ 已启用 pgvector 向量检索扩展';
    RAISE NOTICE '✅ 已启用 pg_trgm 全文检索扩展';
    RAISE NOTICE '✅ 已创建自动触发器（公共资源/项目资源/统计更新）';
    RAISE NOTICE '✅ 已创建默认管理员账户';
    RAISE NOTICE '';
    RAISE NOTICE '默认管理员账户:';
    RAISE NOTICE '  用户名: admin';
    RAISE NOTICE '  密码: admin123';
    RAISE NOTICE '  邮箱: admin@joylaw.com';
    RAISE NOTICE '';
    RAISE NOTICE '业务逻辑:';
    RAISE NOTICE '  - 用户注册时自动创建公共文件夹和知识库';
    RAISE NOTICE '  - 项目创建时自动创建项目文件夹和知识库';
    RAISE NOTICE '  - 所有删除操作均为软删除（deleted_at）';
    RAISE NOTICE '  - 知识库支持RAGFlow和GraphRAG双模式';
    RAISE NOTICE '===========================================';
END $$;

