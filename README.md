# 哪吒探针 Proot 安装脚本

这是一个为 Proot 容器环境定制的哪吒探针安装脚本。该脚本使用 screen 在后台运行探针，而不是依赖系统服务管理器（如 systemd）。

## 特点

- 适用于 Proot 环境
- 使用 screen 在后台运行探针
- 自动检测并安装 screen（如果需要）
- 支持中国大陆/海外网络环境
- 支持多种系统架构
- 简单的管理命令

## 使用方法

### 安装

1. 下载脚本：

```bash
wget https://raw.githubusercontent.com/fxlqwq/nezhahq_scripts_without_service/refs/heads/main/agent.sh
chmod +x nezha-agent-proot.sh
```
国内加速：
```bash
wget https://raw.bgithub.xyz/fxlqwq/nezhahq_scripts_without_service/refs/heads/main/agent.sh
chmod +x nezha-agent-proot.sh
```
2. 设置安装参数并执行：

```bash
export NZ_SERVER="你的服务端域名或IP:端口"
export NZ_CLIENT_SECRET="你的客户端密钥"
# 可选参数
export NZ_TLS=false                # 是否启用TLS
export NZ_DISABLE_AUTO_UPDATE=false  # 是否禁用自动更新
export DISABLE_FORCE_UPDATE=false    # 是否禁用强制更新
export NZ_DISABLE_COMMAND_EXECUTE=false # 是否禁用命令执行
export NZ_SKIP_CONNECTION_COUNT=false   # 是否跳过连接数统计

./nezha-agent-proot.sh
```
3. 可选方案
```bash
curl -L https://raw.bgithub.xyz/fxlqwq/nezhahq_scripts_without_service/refs/heads/main/agent.sh -o agent.sh && chmod +x agent.sh && env NZ_SERVER=yourserve:port NZ_TLS=false NZ_CLIENT_SECRET=yoursecret ./agent.sh
```


### 管理命令

- 检查状态：
  ```bash
  ./nezha-agent-proot.sh status
  ```

- 重启探针：
  ```bash
  ./nezha-agent-proot.sh restart
  ```

- 停止探针：
  ```bash
  ./nezha-agent-proot.sh stop
  ```

- 卸载探针：
  ```bash
  ./nezha-agent-proot.sh uninstall
  ```

### 查看日志

要查看探针日志：

```bash
screen -r nezha_agent
```

从screen会话中分离（不终止程序）：按 `Ctrl+A` 然后按 `D`

## 环境需求

- 支持的系统：Linux、macOS、FreeBSD
- 支持的架构：x86_64、i386、arm64、arm、s390x、riscv64、mips、mipsle
- 依赖项：wget、unzip、grep、screen

## 故障排除

1. 如果安装失败，请检查网络连接和服务器参数
2. 如果探针无法连接到服务器，请确认服务端地址和密钥正确
3. 如果运行命令时遇到权限问题，请确保脚本有执行权限

## 授权许可

本脚本基于开源社区贡献，供个人和商业使用。

## 致谢

感谢哪吒监控项目团队提供的优秀监控解决方案。
