#!/bin/bash

# 开始启动后端程序
JAR_FILE="./target/genie-backend-0.0.1-SNAPSHOT.jar"
LOGFILE="./genie-backend_startup.log"

# 检查jar文件是否存在
if [ ! -f "$JAR_FILE" ]; then
    echo "错误: 找不到jar文件 $JAR_FILE"
    echo "请先运行 mvn clean package 进行编译打包"
    exit 1
fi

echo "正在启动 genie-backend..."
# 静默启动
java -jar -Dfile.encoding="UTF-8" "$JAR_FILE" > "$LOGFILE" 2>&1 &
# 前台启动
# java -jar -Dfile.encoding="UTF-8" "$JAR_FILE"
echo "启动完成，日志文件: $LOGFILE"
