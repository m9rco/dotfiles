## 1. 共享下载原语

- [x] 1.1 新建 `lib/download.sh`，把 `modules/fonts/module.sh` 里的下载、校验、诊断、解压四个 `_dot_font_*` helper 提升为 `dot_dl_fetch` / `dot_dl_verify` / `dot_dl_describe` / `dot_dl_unzip`
- [x] 1.2 四个 `_dot_font_*` 保留原名与签名、函数体改为一行委托，调用点不动；验收标准是 `test/fonts_test.sh` **零改动**通过（35/35）
- [x] 1.3 魔数判断从 `od -An -c` 的字符形式改为十六进制：zip 的 `PK` 恰好可打印，但 gzip 的 `1f8b` 与 ELF 的 `7f454c46` 不行。`dot_dl_verify` 接受 `zip` / `gzip` / `binary` 三种 kind，`binary` 用 {ELF, Mach-O} 白名单而不是「不像 HTML 就放过」
- [x] 1.4 `dot_dl_fetch` 的超时与重试改为可选参数，默认值保持字体原有的 20s/2 次
- [x] 1.5 新增 `dot_dl_untar`：`gzip -dc | tar -xf -`，**不用** `--strip-components`（busybox tar 没有，而 Alpine 在支持列表里且无 CI 覆盖，依赖它会静默解不出东西）
- [x] 1.6 新增 `dot_dl_find_file`：平铺解包后按**文件名**定位可执行文件，`-type f` 排除同名目录。实测四种真实归档结构：fzf（根部）、gh（目录名带版本）、btop（`./btop/bin/btop` 且有同名目录）、duf（旁边有 `duf.1`）
- [x] 1.7 `lib/runner.sh` 显式 source `download.sh` —— fonts 直接用这些函数，不该依赖 pkg.sh 间接带进来
- [x] 1.8 `lib/README.md` 职责表加行

## 2. 发布二进制的获取

- [x] 2.1 新建 `lib/release.sh`，本文件永不碰 `PATH`、永不设 `DOT_PKG_PATH_NOTICE`（那是 `pkg.sh` 的契约），保持 `pkg.sh → release.sh → download.sh` 单向依赖
- [x] 2.2 配方表 `_dot_release_recipe`：按逻辑名索引，设置 `_dot_rr_asset` / `_dot_rr_kind` / `_dot_rr_name` 三个全局量。刻意**不做**架构词汇映射表 —— 三种词汇互不兼容（`amd64`/`arm64`、`x86_64`/`arm64`、`x86_64`/`aarch64`），映射表只会把知识搬个地方再加一层间接
- [x] 2.3 `{v}` 占位符作为模式开关：含 `{v}` 先解析 tag，不含直接走 `releases/latest/download`（零额外往返）
- [x] 2.4 tag 解析用 `releases/latest` 的 302 加 `%{url_effective}`，**不用** `api.github.com`（未认证 API 在共享出口 IP 上两三次就 403，而引导是无人值守的）
- [x] 2.5 tag → 版本号：只在 `v` 后紧跟数字时剥前缀 —— jq 的 tag 是 `jq-1.8.2`，没有 `v`
- [x] 2.6 版本号形状校验（代理守卫）：拒绝空串、字面量 `latest`、无数字、含异常字符。返回 200 却不重定向的代理会让字面量 `latest` 被代进资产名，产生一个莫名的 404
- [x] 2.7 落地到 `~/.local/bin`：先写临时名再 `mv`（覆盖正在运行的二进制在 Linux 上是 ETXTBSY），显式 `chmod 0755`（裸下载是 0644）。刻意不用 `dot_write`，理由写进代码注释与 `lib/README.md`
- [x] 2.8 单一临时目录清理点（字体模块在 4 个出口各写一次 `rm -rf`，加第五个就会漏）
- [x] 2.9 `DOT_NO_GITHUB_RELEASE=1` 开关与一次性 `DOT_GITHUB_UNREACHABLE` 短路；超时收紧到 10s/1 次
- [x] 2.10 `DOT_GITHUB_BASE` 作为测试缝 —— 注释里写明**绝不**作为用户开关写进文档

## 3. 接入回退链

- [x] 3.1 `lib/pkg.sh` 抽出 `_dot_pkg_use_local_bin`，`_dot_pkg_try_script` 改用它（PATH 契约与提示逻辑只写一处）
- [x] 3.2 新增 `_dot_pkg_try_github` 与回退循环里的 `github)` 分支
- [x] 3.3 修正配方 kind（`targz`，说「怎么解」）与校验 kind（`gzip`，说「魔数是什么」）的转换 —— 第一版直接传 `targz`，报的是「拿到的不是 targz」而文件完全正常
- [x] 3.4 更新 `dot_pkg_install` 的文档注释：spec 内不能有空格（这一列是被 word-split 的）

## 4. 清单

- [x] 4.1 6 个工具接上 `github:owner/repo`：fzf、lazygit、gh、yq、direnv、jq
- [x] 4.2 `tmux` / `htop` 的空回退加注释说明理由（官方从不发二进制，且五个包管理器都有）
- [x] 4.3 `btop` / `duf` 加注释说明为何暂不接（optional 层、btop 无 macOS 资产）
- [x] 4.4 更新清单表头的语法说明：新增 `github:` 形式、空回退的两种含义、spec 内不能有空格
- [x] 4.5 24 个资产 URL（6 工具 × 4 平台组合）逐个实测返回 200

## 5. 测试

- [x] 5.1 Tier A（`test/cli_test.sh`，替身 curl，不发网络）：包管理器成功时**断言 curl 日志为空** —— 这是「回退不抢走仓库里本来有的包」的回归保护
- [x] 5.2 Tier A：配方缺失说「未尝试」且不含「tried」；dry-run 零网络调用；无 curl/wget 时说清缺什么
- [x] 5.3 Tier A：真清单结构断言 —— `github:` 形状（抓走神的空格）、清单↔配方表双向覆盖、6 个工具回退列不能再被清空、tmux/htop 空着且注释在位、预编译优先于 cargo（推广原先只针对 starship 的那条）
- [x] 5.4 Tier B（`test/release_test.sh`）：本地 302 服务 + 现造真归档。`python3 -m http.server` 不够，因为 tag 解析要重定向
- [x] 5.5 Tier B fixture 各钉一个隐患：根部二进制、目录名带版本（`--strip-components` 会栽的地方）、同名目录不能被当成二进制、manpage 不能抓错、裸二进制 chmod、HTML 错误页、不重定向的代理
- [x] 5.6 Tier B：`TMPDIR` 隔离验证临时目录不泄漏；`DOT_TEST_NETWORK=1` 门控的真实拉取（默认关，CI 保持无网络）
- [x] 5.7 `sh` 与 `dash` 双 shell 全绿；`test/lint.sh`、`test/spec_coverage.sh --check` 通过

## 6. 真环境验证

- [x] 6.1 `debian:stable-slim`（arm64）：lazygit/gh/yq 走 GitHub release，fzf/jq/direnv 仍走 apt
- [x] 6.2 `rockylinux:9`（arm64）：lazygit/direnv 走 GitHub release，fzf/gh/jq/yq/tmux 仍走 dnf
- [x] 6.3 两边都只剩 eza 装不上（只有 cargo 回退、容器无 cargo），且第二次跑幂等
- [x] 6.4 装出来的二进制实际能运行（不只是文件存在）

## 7. 文档与 CI

- [x] 7.1 `README.md`：修正「eza/lazygit/gh/yq 在任何 RHEL 仓库里都没有」这句已过时的说法；补第三个开关 `DOT_NO_GITHUB_RELEASE`
- [x] 7.2 `.github/workflows/ci.yml` debian job：注释里写死的失败集合已过时，并加「必须走 GitHub release」的正向断言
- [x] 7.3 `.github/workflows/ci.yml` rocky job：同上；`via dnf` 那组断言现在兼任「回退不抢包」的守卫，注释说明这一点
- [x] 7.4 `test/spec_coverage.sh` 覆盖行指向新增的两个 lib 与新测试
- [x] 7.5 openspec 变更文档（proposal / spec delta / tasks）—— 本次改动的实现先落地，spec 补在同一分支
