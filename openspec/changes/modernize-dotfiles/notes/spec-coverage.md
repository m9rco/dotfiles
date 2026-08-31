# spec 覆盖度追溯

生成命令：`sh test/spec_coverage.sh`

requirement 总数：84

## ai-agent-config

8 条 requirement / 18 个 scenario

| Requirement | 实现 | 验证 |
|---|---|---|
| AI 配置单一真源 | `config/ai/` | test:ai_config_test.sh |
| agent 与 skill 跨工具链接 | `modules/ai-agent-config` | test:ai_config_test.sh |
| MCP 配置渲染 | `modules/ai-agent-config` | test:ai_config_test.sh |
| 清单格式校验 | `modules/ai-agent-config` | test:ai_config_test.sh |
| 配置的平台无关表示 | `config/ai/*` | test:ai_config_test.sh |
| 保留工具的本地配置 | `modules/ai-agent-config` | test:ai_config_test.sh |
| 幂等与预演 | `modules/ai-agent-config` | test:ai_config_test.sh |
| 工具未安装时的处理 | `modules/ai-agent-config` | test:ai_config_test.sh |

## ai-coding-clis

7 条 requirement / 17 个 scenario

| Requirement | 实现 | 验证 |
|---|---|---|
| AI 编码 CLI 安装集 | `config/ai/clis.txt` | test:ai_clis_test.sh |
| 三平台安装一致 | `modules/ai-clis` | test:ai_clis_test.sh |
| npm 全局安装的 PATH 处理 | `modules/ai-clis` | test:ai_clis_test.sh |
| 安装幂等与升级 | `modules/ai-clis + bin/dot-ai-upgrade` | test:ai_clis_test.sh |
| 版本检查为非阻断 | `modules/ai-clis` | test:ai_clis_test.sh |
| 不在安装期要求凭据 | `modules/ai-clis` | test:ai_clis_test.sh |
| 预演模式不安装 | `modules/ai-clis` | test:ai_clis_test.sh |

## bootstrap-installer

12 条 requirement / 28 个 scenario

| Requirement | 实现 | 验证 |
|---|---|---|
| 双入口引导程序 | `bootstrap.sh + bootstrap.ps1` | test:runner_test.sh |
| 模块自描述与目录发现 | `lib/runner.sh` | test:runner_test.sh |
| 平台适用性过滤 | `lib/runner.sh` | test:runner_test.sh |
| 依赖排序 | `lib/runner.sh` | test:runner_test.sh |
| 幂等执行 | `lib/fs.sh` | test:runner_test.sh |
| 预演模式 | `lib/fs.sh` | test:runner_test.sh |
| 选择性执行 | `bootstrap.sh` | test:runner_test.sh |
| 模块清单查询 | `lib/runner.sh` | test:runner_test.sh |
| 链接前备份 | `lib/fs.sh` | test:fs_test.sh |
| 统一日志输出 | `lib/log.sh` | test:runner_test.sh |
| 失败处理与退出码 | `lib/runner.sh` | test:runner_test.sh |
| 帮助信息 | `bootstrap.sh` | test:runner_test.sh |

## font-provisioning

8 条 requirement / 17 个 scenario

| Requirement | 实现 | 验证 |
|---|---|---|
| Nerd Fonts 作为字体来源 | `config/fonts/fonts.txt` | test:fonts_test.sh |
| 平台字体目录 | `platform/*` | test:fonts_test.sh |
| 字体缓存刷新 | `platform/linux.sh` | test:fonts_test.sh |
| 字体安装幂等 | `modules/fonts` | test:fonts_test.sh |
| 无图形环境跳过 | `modules/fonts` | test:fonts_test.sh |
| 下载失败处理 | `modules/fonts` | test:fonts_test.sh |
| 终端字体指向 | `modules/fonts` | manual:输出手动设置指引（无法可靠改终端配置） |
| 预演模式不下载 | `modules/fonts` | test:fonts_test.sh |

## legacy-migration

10 条 requirement / 34 个 scenario

| Requirement | 实现 | 验证 |
|---|---|---|
| 彻底移除全部 git 子模块 | `已执行` | test:migration_test.sh |
| vim 插件改由插件管理器管理 | `openspec/changes/modernize-dotfiles/notes/vim-plugins.md` | test:migration_test.sh |
| private 目录整体归档 | `legacy/private/` | test:migration_test.sh |
| 新配置为重写而非搬迁 | `config/` | lint:no-hardcoded-home |
| 旧安装脚本退出使用 | `legacy/private/install.sh` | test:migration_test.sh |
| 目录结构重排 | `仓库根` | test:migration_test.sh |
| 分阶段可用性 | `git 历史` | manual:每阶段后 lint 与测试均通过 |
| CI 从 Travis 迁移到 GitHub Actions | `.github/workflows/ci.yml` | test:migration_test.sh |
| 既有用户升级路径 | `docs/UPGRADING.md` | test:migration_test.sh |
| 文档更新 | `README.md` | test:migration_test.sh |

## modern-cli-toolchain

9 条 requirement / 19 个 scenario

| Requirement | 实现 | 验证 |
|---|---|---|
| 声明式工具清单 | `config/cli/tools.txt` | test:cli_test.sh |
| 默认工具集 | `config/cli/tools.txt` | test:cli_test.sh |
| 包管理器不可用时的回退 | `lib/pkg.sh` | test:cli_test.sh |
| 工具安装幂等 | `lib/pkg.sh` | test:cli_test.sh |
| shell 集成 hook | `config/zsh/zshrc.d/30-tools.zsh` | manual:zoxide/fzf 实测生效 |
| 别名与传统命令共存 | `config/zsh/zshrc.d/40-aliases.zsh` | manual:仅交互式生效，脚本用原命令 |
| delta 集成 git | `config/git/gitconfig` | manual:delta 缺失时回退 less 无报错 |
| 跨平台一致的工具体验 | `config/cli + platform/*` | test:cli_test.sh |
| 预演模式不安装 | `modules/modern-cli` | test:cli_test.sh |

## platform-detection

9 条 requirement / 28 个 scenario

| Requirement | 实现 | 验证 |
|---|---|---|
| 操作系统识别 | `lib/detect.sh` | test:detect_test.sh |
| CPU 架构识别 | `lib/detect.sh` | test:detect_test.sh |
| Linux 发行版识别 | `lib/detect.sh` | test:detect_test.sh |
| 包管理器识别 | `lib/detect.sh` | test:detect_test.sh |
| Homebrew 前缀探测 | `lib/detect.sh` | test:detect_test.sh |
| WSL 环境识别 | `lib/detect.sh` | test:detect_test.sh |
| 无图形环境识别 | `lib/detect.sh` | test:detect_test.sh |
| 探测结果可查询 | `bootstrap.sh --info` | test:detect_test.sh |
| 模块代码不直接探测平台 | `modules/*` | lint:modules-no-uname |

## secrets-management

8 条 requirement / 23 个 scenario

| Requirement | 实现 | 验证 |
|---|---|---|
| 仓库内零明文密钥 | `全仓` | test:secrets_test.sh |
| 平台密钥库集成 | `lib/secrets.sh` | test:secrets_test.sh |
| 密码管理器支持 | `lib/secrets.sh` | test:secrets_test.sh |
| 本地环境文件兜底 | `lib/secrets.sh + modules/secrets` | test:secrets_test.sh |
| shell 启动不同步读取密钥 | `config/zsh/zshrc.d/50-secrets.zsh` | test:secrets_test.sh |
| 误提交守卫 | `modules/secrets` | test:secrets_test.sh |
| 本地推理工具可选安装 | `modules/secrets` | test:secrets_test.sh |
| 密钥值不出现在日志 | `lib/secrets.sh` | test:secrets_test.sh |

## shell-environment

13 条 requirement / 31 个 scenario

| Requirement | 实现 | 验证 |
|---|---|---|
| zsh 安装与默认 shell 设置 | `modules/zsh` | test:cli_test.sh |
| zshrc 分片架构 | `config/zsh/zshrc + config/zsh/zshrc.d` | manual:沙箱 HOME 载入零错误 |
| 本地覆盖不入库 | `config/zsh/zshrc.d/90-local.zsh` | lint:no-tracked-local |
| Homebrew 环境正确加载 | `config/zsh/zshrc.d/10-path.zsh` | manual:Apple Silicon 上 HOMEBREW_PREFIX=/opt/homebrew |
| 失效镜像地址移除 | `config/zsh/zshrc.d/00-env.zsh` | lint:no-dead-mirror |
| 单一 zsh 框架 | `config/zsh` | manual:config 下无 zimrc |
| 条件化插件加载 | `config/zsh/zshrc.d/20-omz.zsh` | manual:缺工具时启动零错误输出 |
| starship 作为跨平台 prompt | `config/starship.toml` | manual:zsh 与 PowerShell 共用同一份 |
| 历史记录配置 | `config/zsh/zshrc.d/15-history.zsh` | manual:HISTSIZE/SAVEHIST 实测 50000 |
| 启动性能预算 | `config/zsh + bin/dot-bench` | manual:中位数 153ms（预算 200ms） |
| 补全缓存 | `config/zsh/zshrc.d/25-completion.zsh` | manual:单一 .zcompdump，失效后重建 |
| PowerShell profile | `config/powershell/profile.ps1` | test:lint_ps.sh |
| 跨 shell 共享配置 | `config/starship.toml` | manual:两侧读同一文件 |


covered: 84 / 84
every requirement maps to an implementation and a verification method
all referenced tests and implementation paths exist
