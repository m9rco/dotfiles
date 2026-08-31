# modules/

安装模块。每个子目录一个模块，由 `lib/runner.sh` 扫描 `modules/*/module.sh` **自动发现** —— 新增模块不需要修改 `bootstrap.sh` 或任何中心清单。

旧 `install.sh` 每加一个任务要改三处（函数、`usage()` 文案、`case` 分支），必然漂移：它的 `usage()` 里列着 `zsh_rc`，而 `case` 分支实际是 `zsh_omz`。目录发现让清单的唯一来源是文件系统。

## module.sh 格式

```sh
MODULE_DESC="一句话描述"           # 必需，显示在 --list 中
MODULE_PLATFORMS="macos linux"     # 必需，空格分隔；不含当前平台则跳过
MODULE_TAGS="core"                 # 必需，core / ai / optional，空格分隔可多个
MODULE_REQUIRES="zsh"              # 可选，依赖的模块名，空格分隔
MODULE_NEEDS_GUI="1"               # 可选，置 1 则在 headless 环境下跳过

install() {
    # 安装逻辑
}
```

缺少必需声明或 `install()` 的模块会被拒绝并使引导报错终止。

## 约定

- **不要自己判断平台**：不得调用 `uname` 或读 `/etc/os-release`（CI 会检查）。只用 `lib/detect.sh` 导出的 `DOT_*` 变量与 `platform/` 层的函数。
- **不要直接写文件**：所有写操作走 `lib/fs.sh` 的原语，否则会绕过备份与 dry-run。
- 配置内容放 `config/`，这里只放逻辑。
- `install()` 必须幂等：已就位时跳过，连续两次执行第二次应零变更。
- 返回非零表示失败。单个模块失败不会中断其余模块，但依赖它的模块会被跳过。

用 `./bootstrap.sh --list` 查看当前所有模块。
