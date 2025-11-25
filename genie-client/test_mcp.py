#!/usr/bin/env python3
"""
测试 MCP 服务器连接的脚本

使用方法:
1. 确保 genie-client 服务正在运行 (端口 8188)
2. TARGET_MCP_URL 改为需要测试的mcp服务的地址
3. 运行此脚本: python test_mcp.py
"""

import requests

# 配置
GENIE_CLIENT_URL = "http://localhost:8188"
TARGET_MCP_URL = "http://127.0.0.1:9382/sse"
TARGET_API_KEY = ""


def print_section(title: str):
    """打印分节标题"""
    print("\n" + "=" * 60)
    print(f"  {title}")
    print("=" * 60)


def test_health_check() -> bool:
    """测试 genie-client 健康检查"""
    print_section("1. 测试 Genie Client 健康检查")
    try:
        response = requests.get(f"{GENIE_CLIENT_URL}/")
        if response.status_code == 200:
            data = response.json()
            print(f"✓ Genie Client 运行正常")
            print(f"  状态: {data.get('status')}")
            print(f"  版本: {data.get('version')}")
            print(f"  时间: {data.get('timestamp')}")
            return True
        else:
            print(f"✗ Genie Client 响应异常: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print(f"✗ 无法连接到 Genie Client (http://localhost:8188)")
        print(f"  请确保 genie-client 服务已启动:")
        print(f"    cd /Users/wangxu/projects/joyagent-jdgenie/genie-client")
        print(f"    python server.py")
        return False
    except Exception as e:
        print(f"✗ 测试失败: {str(e)}")
        return False


def test_ping_Target() -> bool:
    """测试 Target MCP 服务器连通性"""
    print_section("2. 测试 Target MCP 服务器连通性")
    try:
        # 准备请求数据
        payload = {
            "server_url": TARGET_MCP_URL
        }
        
        # 准备请求头 (包含 api_key)
        headers = {
            "Content-Type": "application/json",
            "api_key": TARGET_API_KEY
        }
        
        print(f"正在 ping 服务器: {TARGET_MCP_URL}")
        response = requests.post(
            f"{GENIE_CLIENT_URL}/v1/serv/pong",
            json=payload,
            headers=headers,
            timeout=10
        )
        
        data = response.json()
        
        if data.get("code") == 200:
            print(f"✓ Target MCP 服务器连接成功!")
            print(f"  消息: {data.get('message')}")
            return True
        else:
            print(f"✗ Target MCP 服务器连接失败")
            print(f"  代码: {data.get('code')}")
            print(f"  消息: {data.get('message')}")
            return False
            
    except requests.exceptions.Timeout:
        print(f"✗ 连接超时")
        print(f"  请确保 Target MCP 服务器正在运行 (http://127.0.0.1:9382)")
        return False
    except Exception as e:
        print(f"✗ 测试失败: {str(e)}")
        return False


def test_list_Target_tools() -> bool:
    """测试获取 Target MCP 工具列表"""
    print_section("3. 获取 Target MCP 工具列表")
    try:
        # 准备请求数据
        payload = {
            "server_url": TARGET_MCP_URL
        }
        
        # 准备请求头 (包含 api_key)
        headers = {
            "Content-Type": "application/json",
            "api_key": TARGET_API_KEY
        }
        
        print(f"正在获取工具列表...")
        response = requests.post(
            f"{GENIE_CLIENT_URL}/v1/tool/list",
            json=payload,
            headers=headers,
            timeout=10
        )
        
        data = response.json()
        
        if data.get("code") == 200:
            tools = data.get("data", [])
            print(f"✓ 成功获取 {len(tools)} 个工具")
            
            if tools:
                print("\n工具列表:")
                for i, tool in enumerate(tools, 1):
                    # 检查 tool 是否是字典
                    if isinstance(tool, dict):
                        tool_name = tool.get('name', 'N/A')
                        tool_desc = tool.get('description', 'N/A')
                    else:
                        # 如果是对象，尝试访问属性
                        tool_name = getattr(tool, 'name', 'N/A')
                        tool_desc = getattr(tool, 'description', 'N/A')
                    
                    print(f"  {i}. {tool_name}")
                    print(f"     描述: {tool_desc[:80]}..." if len(str(tool_desc)) > 80 else f"     描述: {tool_desc}")
            else:
                print("  (没有可用的工具)")
            
            return True
        else:
            print(f"✗ 获取工具列表失败")
            print(f"  代码: {data.get('code')}")
            print(f"  消息: {data.get('message')}")
            return False
            
    except Exception as e:
        print(f"✗ 测试失败: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


def test_call_Target_tool() -> bool:
    """测试调用 Target MCP 工具 (可选)"""
    print_section("4. 测试调用 Target 工具 (可选)")
    print("跳过此测试 - 需要先了解可用的工具及其参数")
    return True


def main():
    """主测试流程"""
    print("\n" + "=" * 60)
    print("  Target MCP 服务器测试")
    print("=" * 60)
    print(f"\n配置信息:")
    print(f"  Genie Client: {GENIE_CLIENT_URL}")
    print(f"  Target MCP: {TARGET_MCP_URL}")
    print(f"  API Key: {TARGET_API_KEY[:20]}...")
    
    # 执行测试
    results = []
    
    # 测试 1: 健康检查
    results.append(("Genie Client 健康检查", test_health_check()))
    
    if not results[-1][1]:
        print("\n" + "=" * 60)
        print("  测试终止: Genie Client 未运行")
        print("=" * 60)
        return
    
    # 测试 2: Ping Target
    results.append(("Target 连通性测试", test_ping_Target()))
    
    if results[-1][1]:
        # 测试 3: 获取工具列表
        results.append(("Target 工具列表", test_list_Target_tools()))
        
        # 测试 4: 调用工具 (可选)
        results.append(("Target 工具调用", test_call_Target_tool()))
    
    # 打印测试总结
    print_section("测试总结")
    for test_name, passed in results:
        status = "✓ 通过" if passed else "✗ 失败"
        print(f"  {status} - {test_name}")
    
    # 总体结果
    passed_count = sum(1 for _, passed in results if passed)
    total_count = len(results)
    
    print(f"\n总计: {passed_count}/{total_count} 测试通过")
    
    if passed_count == total_count:
        print("\n🎉 所有测试通过! Target MCP 服务器配置成功!")
    else:
        print("\n⚠️  部分测试失败，请检查上述错误信息")
    
    print("=" * 60 + "\n")


if __name__ == "__main__":
    main()

