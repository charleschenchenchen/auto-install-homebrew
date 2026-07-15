# auto-install-homebrew

一键安装与配置 [Homebrew](https://brew.sh/) 的 Bash 脚本，针对**国内网络环境**做了镜像加速、自动测速与安装后验证，同时支持境外网络自动切换官方源。

> 脚本版本：**V2.1.0** | 文件：`install-brew.sh`

---

## 特性

| 类别 | 说明 |
|------|------|
| 多平台 | macOS（Intel / Apple Silicon M1/M2/M3）、Linux / WSL |
| 智能网络 | 自动检测 GitHub 连通性；支持代理环境变量识别；境内/境外模式可手动确认 |
| 国内镜像 | Git 源码镜像（清华、Gitee）、Bottle 二进制镜像（阿里、清华、中科大、腾讯） |
| 镜像测速 | 境内模式下自动测速 Git 与 Bottle 镜像，辅助选择 |
| 互备克隆 | 清华 / Gitee 克隆失败时自动切换备用源 |
| 环境清理 | 可选备份并删除旧版 Homebrew 至桌面 |
| 安装验证 | 目录结构、命令可用性、Git 仓库、权限、镜像、网络、`brew update`、测试包安装 |
| 运维能力 | 一键卸载、仅切换镜像、权限自动修复、`brew doctor` 检测 |
| 安全机制 | 进程锁防重复运行、信号捕获清理、sudo 后台保活、完整日志记录 |

---

## 系统要求

### 支持的平台

| 系统 | 架构 | Homebrew 安装路径 |
|------|------|-------------------|
| macOS 12+ | `arm64`（Apple Silicon） | `/opt/homebrew` |
| macOS 12+ | `x86_64`（Intel） | `/usr/local` |
| Linux / WSL | `x86_64` / `arm64` | `/home/linuxbrew/.linuxbrew` |

### 前置依赖

- **git**、**curl**（脚本可尝试自动安装）
- **sudo** 权限（安装与部分目录操作需要）
- 磁盘剩余空间建议 **≥ 5 GB**（不足时会提示确认）
- macOS 需安装 **Xcode Command Line Tools**（缺失时脚本会触发安装）

### 不支持的架构

- 32 位 ARM（`armv6l` / `armv7l`）

---

## 快速开始

### 下载并运行

```bash
# 克隆仓库
git clone https://github.com/charleschenchenchen/auto-install-homebrew.git
cd auto-install-homebrew

# 添加执行权限并运行
chmod +x install-brew.sh
./install-brew.sh
```

### 一行命令（远程执行）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/charleschenchenchen/auto-install-homebrew/main/install-brew.sh)"
```


### 安装完成后

```bash
# 立即加载环境变量
source ~/.zprofile        # zsh（macOS 默认）
# 或
source ~/.bash_profile    # bash

# 验证安装
brew -v
brew doctor
```

---

## 命令行参数

| 参数 | 说明 |
|------|------|
| `--no-color` | 禁用彩色终端输出 |
| `--uninstall` | 完整卸载 Homebrew（含备份、清理缓存与 Shell 配置） |
| `--switch-mirror` | 仅切换镜像源，不重新安装 Homebrew |

### 使用示例

```bash
# 标准安装
./install-brew.sh

# 无彩色输出（适合 CI 或日志重定向）
./install-brew.sh --no-color

# 仅切换镜像（已安装 brew 时使用）
./install-brew.sh --switch-mirror

# 一键卸载
./install-brew.sh --uninstall
```

---

## 安装流程

脚本按以下顺序执行：

```
启动 → 创建进程锁 → 解析参数
  ↓
识别系统与架构 → 校验兼容性 → 检测磁盘空间
  ↓
检查 git/curl 依赖 → 清理 Git 代理干扰 → 启动 sudo 保活
  ↓
检测网络区域（境内 / 境外）
  ↓
选择 Git 源码镜像（交互式菜单）
  ↓
┌─ 全新安装 ─────────────────────────────────┐
│  备份/删除旧版 → 克隆 install 仓库          │
│  → 替换 GitHub 地址 & 注入 Bottle 变量       │
│  → 执行官方 install.sh                      │
└────────────────────────────────────────────┘
┌─ 已安装 brew ──────────────────────────────┐
│  选项 3：跳过安装，仅写镜像环境变量           │
│  选项 4/5：修改现有 brew 的 Git remote       │
└────────────────────────────────────────────┘
  ↓
选择 Bottle 二进制镜像 → 写入 Shell 配置文件
  ↓
brew update-reset → brew update → brew doctor → 权限修复
  ↓
安装后验证（目录 / 命令 / Git / 权限 / 镜像 / 网络 / 测试包）
  ↓
输出报告 → 释放锁与 sudo 保活进程
```

---

## 交互式菜单

### Git 源码镜像（境内模式）

运行时会先展示镜像测速结果，然后选择：

| 序号 | 镜像 | 地址 |
|------|------|------|
| 1（默认） | 清华大学 | `https://mirrors.tuna.tsinghua.edu.cn/git/homebrew` |
| 2 | Gitee | `https://gitee.com/mirrors/homebrew-install` |
| 3 | 已安装 brew，仅配置镜像不重装 | — |
| 4 | 仅修改现有 brew 远程地址（清华） | — |
| 5 | 仅修改现有 brew 远程地址（Gitee） | — |

### Bottle 二进制镜像（境内模式）

| 序号 | 镜像 | 说明 |
|------|------|------|
| 1 | 中科大 | USTC |
| 2 | 清华大学 | TUNA |
| 3 | 腾讯云 | Tencent Cloud |
| 4（默认） | 阿里云 | 脚本推荐 |

境外模式下自动使用 GitHub 官方源，不配置国内 Bottle 镜像。

---

## 镜像与环境变量

脚本会在 Shell 配置文件中写入带 `#brew-mirror-auto` 标记的配置块，便于识别与清理。

### 境内模式写入的变量

```bash
export HOMEBREW_BOTTLE_DOMAIN=<所选 Bottle 镜像>
export HOMEBREW_API_DOMAIN=<对应 API 域名>
export HOMEBREW_PIP_INDEX_URL=<对应 PyPI 镜像>
eval $(/path/to/brew shellenv)
```

### 境外模式写入的变量

```bash
eval $(/path/to/brew shellenv)
```

### 配置文件路径

| 环境 | 写入文件 |
|------|----------|
| macOS + zsh | `~/.zprofile` |
| macOS + bash | `~/.bash_profile` 或 `~/.profile` |
| Linux | `/etc/profile` |

---

## 网络检测逻辑

1. 若检测到 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`，判定为**境外网络**，使用 GitHub 官方源。
2. 否则尝试连接 `https://github.com/Homebrew/brew`（超时 3 秒，最多重试 2 次）。
3. 连通 → 境外模式；不通 → 提示手动选择境内（默认）或境外。

---

## 安装后验证

脚本会在安装完成后自动执行以下检查，并生成验证报告：

| 检查项 | 内容 |
|--------|------|
| 目录结构 | `bin`、`Cellar`、`Homebrew`、`opt` |
| 命令可用性 | `brew --version`，必要时修复 PATH |
| Git 仓库 | remote 地址、`git fsck` 完整性 |
| 目录权限 | Cellar、bin 是否可写 |
| 镜像配置 | 境内/境外模式变量是否正确 |
| 网络连通 | 测试镜像或 GitHub 可达性 |
| 更新功能 | `brew update` |
| 安装测试 | 安装并卸载 `hello` 测试包 |

验证结果分为三档：

- **全部通过** — 安装成功
- **有警告无错误** — 安装成功但存在潜在问题
- **有错误** — 安装验证未通过，脚本以退出码 `1` 结束

---

## 卸载

```bash
./install-brew.sh --uninstall
```

卸载操作包括：

1. 备份旧 Homebrew 目录至 `~/Desktop/Old_Homebrew_Backup/<时间戳>/`
2. 删除 `/opt/homebrew`、`/usr/local/Homebrew` 等安装目录
3. 清理 Homebrew 缓存与日志
4. 从 Shell 配置中移除 `#brew-mirror-auto` 标记的配置块

---

## 仅切换镜像

适用于已安装 Homebrew、只需更换国内加速源的场景：

```bash
./install-brew.sh --switch-mirror
```

流程：检测网络 → 选择 Git 镜像 → （可选）修改 brew remote → 选择 Bottle 镜像 → 重写环境变量 → `brew update-reset` / `brew doctor`。

---

## 日志与临时文件

| 路径 | 用途 |
|------|------|
| `~/.brew_install.log` | 完整安装日志（含 INFO / WARN / ERROR） |
| `~/.brew_install_tmp/` | 临时克隆 install 仓库（安装完成后自动删除） |
| `/tmp/brew_install.lock` | 进程锁，防止脚本并发运行 |
| `~/Desktop/Old_Homebrew_Backup/` | 旧版 Homebrew 备份目录 |

查看最近日志：

```bash
tail -n 100 ~/.brew_install.log
```

---

## 常见问题

### 提示「脚本正在运行」

另一个实例可能正在执行，或上次异常退出未清理锁文件：

```bash
rm -f /tmp/brew_install.lock
```

### 权限错误

```bash
sudo chown -R $(whoami) /opt/homebrew    # Apple Silicon
sudo chown -R $(whoami) /usr/local       # Intel Mac
sudo chown -R $(whoami) /home/linuxbrew/.linuxbrew  # Linux
brew doctor
```

### Git 仓库异常

```bash
brew update-reset
brew update
```

### 网络 / 镜像问题

- 重新运行 `./install-brew.sh --switch-mirror` 切换镜像
- 检查防火墙或代理设置
- 境内用户确认选择了合适的 Bottle 镜像

### macOS 版本过旧

Homebrew 官方最低支持 macOS 12。脚本检测到更低版本时会警告，可选择强制继续或升级系统。

### brew 命令找不到

```bash
source ~/.zprofile   # 或对应的 Shell 配置文件
echo 'eval $(/opt/homebrew/bin/brew shellenv)' >> ~/.zprofile  # Apple Silicon 示例
```

---

## 项目结构

```
auto-install-homebrew/
├── install-brew.sh    # 主安装脚本（V2.1.0）
└── README.md          # 项目说明文档
```

---

## 免责声明

- 本脚本**非 Homebrew 官方项目**，安装过程会调用 Homebrew 官方 `install.sh`。
- 国内镜像由第三方维护（清华、Gitee、阿里云等），可用性与同步延迟以各镜像站为准。
- 卸载与覆盖旧安装前会提示确认，但**仍建议自行备份重要数据**。
- 使用本脚本即表示你了解并接受上述风险。

---

## 许可证

MIT License

---

## 贡献

欢迎提交 Issue 与 Pull Request：

- 报告 Bug 或兼容性问题
- 补充/更新镜像源地址
- 改进文档与脚本逻辑
