# -*- coding: utf-8 -*-
# =====================
# PostgreSQL 数据库引擎配置
# Author: JoyLaw Team
# Date:   2025/11/24
# =====================
import os
from typing import Callable, AsyncGenerator

from loguru import logger
from sqlalchemy import create_engine
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool, AsyncAdaptedQueuePool
from sqlmodel import SQLModel


# 数据库配置（从环境变量读取）
DB_USER = os.environ.get("DB_USER", "joylaw_user")
DB_PASS = os.environ.get("DB_PASS", "your_secure_password")
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "joylaw")

# PostgreSQL连接URL
DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
ASYNC_DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# 同步引擎（用于初始化表结构）
engine = create_engine(
    DATABASE_URL,
    echo=False,
    pool_pre_ping=True,  # 连接健康检查
    pool_size=5,
    max_overflow=10,
)

# 异步引擎（用于业务逻辑）
async_engine = create_async_engine(
    ASYNC_DATABASE_URL,
    poolclass=AsyncAdaptedQueuePool,
    pool_size=20,              # 连接池大小
    max_overflow=10,           # 最大溢出连接数
    pool_recycle=3600,         # 连接回收时间（秒）
    pool_pre_ping=True,        # 连接健康检查
    echo=False,                # 生产环境关闭SQL日志
    connect_args={
        "server_settings": {
            "application_name": "joylaw_genie_tool",
            "jit": "off",      # 关闭JIT（提升小查询性能）
        },
        "command_timeout": 60,  # 查询超时时间（秒）
        "timeout": 10,          # 连接超时时间（秒）
    }
)

# 异步Session工厂
async_session_local: Callable[..., AsyncSession] = async_sessionmaker(
    bind=async_engine,
    class_=AsyncSession,
    expire_on_commit=False,    # 提交后不自动过期对象
    autoflush=False,           # 手动控制flush
)


async def get_async_session() -> AsyncGenerator[AsyncSession, None]:
    """
    异步Session生成器，用于FastAPI的Depends依赖注入
    
    Example:
        @app.get("/users")
        async def get_users(session: AsyncSession = Depends(get_async_session)):
            result = await session.execute(select(User))
            return result.scalars().all()
    """
    async with async_session_local() as session:
        try:
            yield session
            await session.commit()
        except Exception as e:
            await session.rollback()
            logger.error(f"数据库事务错误: {e}")
            raise
        finally:
            await session.close()


def init_db():
    """
    初始化数据库（创建所有表）
    注意：实际生产环境建议使用 init_database.sql 脚本初始化
    """
    from genie_tool.db.models import *  # 导入所有模型
    
    try:
        SQLModel.metadata.create_all(engine)
        logger.info("数据库初始化完成")
    except Exception as e:
        logger.error(f"数据库初始化失败: {e}")
        raise


async def close_db():
    """关闭数据库连接池"""
    await async_engine.dispose()
    logger.info("数据库连接池已关闭")


async def check_db_connection():
    """检查数据库连接是否正常"""
    try:
        async with async_session_local() as session:
            await session.execute("SELECT 1")
        logger.info(f"数据库连接正常: {DB_HOST}:{DB_PORT}/{DB_NAME}")
        return True
    except Exception as e:
        logger.error(f"数据库连接失败: {e}")
        return False


if __name__ == "__main__":
    import asyncio
    
    # 测试数据库连接
    async def test():
        is_connected = await check_db_connection()
        if is_connected:
            print("✅ PostgreSQL连接成功")
        else:
            print("❌ PostgreSQL连接失败")
    
    asyncio.run(test())

