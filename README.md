# Nezha Agent Proot 部署工具

专为 **Proot容器环境** 优化的Nezha Agent部署方案，无需systemd/init.d支持，完美适配Termux/Chroot/Linux容器等受限环境。


## 📦 核心特性

- 🚀 零依赖部署 - 仅需`wget`+`unzip`基础工具
- 🔒 安全加固 - 自动生成隔离配置文件
- 📡 断线自愈 - 内置进程守护机制
- 🌐 智能加速 - 自动切换中科大镜像源
- 📊 状态监控 - 实时日志输出支持
- 🛠️ 多架构支持：
  - ✅ x86_64
  - ✅ ARMv7/v8
  - ✅ MIPS
  - ✅ RISC-V

## 🚀 快速部署

### 基础安装（推荐）

```bash
curl -L https://raw.githubusercontent.com/fxlqwq/nezhahq_scripts_without_service/refs/heads/main/agent.sh -o agent.sh && chmod +x agent.sh && env NZ_SERVER=your_dashboard.com:5555 NZ_TLS=false NZ_CLIENT_SECRET=your_secret_key ./agent.sh
```

#### 国内用户可以使用

```bash
curl -L https://raw.bgithub.xyz/fxlqwq/nezhahq_scripts_without_service/refs/heads/main/agent.sh -o agent.sh && chmod +x agent.sh && env NZ_SERVER=your_dashboard.com:5555 NZ_TLS=false NZ_CLIENT_SECRET=your_secret_key ./agent.sh
