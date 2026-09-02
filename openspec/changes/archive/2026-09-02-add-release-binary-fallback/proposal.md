## Why

`config/cli/tools.txt` 的第 4 列声明「包管理器里没有这个包时依次尝试的回退方式」。有 10 个工具这一列是空的，于是包管理器一失败就直接报：

```
could not install fzf (tried yum and 0 fallback method(s))
```

而仓库明确声明支持这些平台（`platform-detection` spec 点名 RHEL/CentOS 7 与 Amazon Linux 2）。实际缺口逐个核实过：

| 工具 | 哪里装不上 |
|---|---|
| fzf | EPEL 7 里没有（CentOS 7 / Amazon Linux 2） |
| lazygit | apt 与所有 RHEL 仓库都没有 |
| gh | apt 没有 |
| yq | apt 没有 |
| direnv | dnf/yum 没有（base 与 EPEL 9 都查过） |

这几个工具都是 Go 写的，`cargo` 装不了；官方 release 的预编译二进制是唯一的路。

`modern-cli-toolchain` 的「包管理器不可用时的回退」已经把「官方发布二进制」列为受支持的方式，也已经要求预编译二进制优先于源码编译 —— 但在此之前只有 starship 真的走到过那条路（经 `script:`）。所以这次改动主要是**补齐一条已被要求、却没有实现的路径**，而不是新增能力。

真正需要新写进 spec 的是三件既有条文没覆盖的事：预编译二进制的**来源可见性**、**解包前的完整性校验**、以及**本平台没有资产**时的表述。外加一条实现上不得不面对的约束：加了网络回退之后，离线机器不能因此变慢。

## What Changes

- 新增 `github:owner/repo` 回退方式。清单里只写来源仓库，资产名与归档结构在 `lib/release.sh` 的配方表里 —— 二进制**从哪来**是读清单的人该一眼看到的供应链事实，资产名不是。
- 6 个工具接上这条回退：`fzf`、`lazygit`、`gh`、`yq`、`direnv`、`jq`。
- `tmux` / `htop` 的回退列保持为空**并加注释说明理由**：两个项目从不发布预编译二进制（只有源码 tarball，tmux 还要 libevent+ncurses），且五个包管理器全都收录了它们。空在那里从此表示「查过，没有」而不是「没想过」。
- 字体模块私有的下载/校验/解包 helper 提升为 `lib/download.sh`，release 与 fonts 共用。校验从只认 zip 推广到 zip / gzip / 裸二进制。
- 新增 `DOT_NO_GITHUB_RELEASE=1` 开关，以及一次性的「github 不可达」短路 —— 离线机器不该因为多了一条网络回退而逐个超时。
- 预编译二进制装到 `~/.local/bin`，不碰系统目录、不需要提权。

## Non-goals

- **不做 sha256 / 签名校验。** checksum 文件与资产同源、走同一个 TLS 连接，能替换资产的人也能替换 checksum；它防的是传输损坏（TLS 已覆盖）与截断（gzip 解压失败已覆盖），防不住被投毒的 release —— 那需要 sigstore/cosign 或 `gh attestation verify`，而用 `gh` 去装 `gh` 是循环依赖。明示接受的残余风险：CDN 返回一个陈旧但结构完好的对象会通过校验，后果是版本不对，不是代码执行。
- **不给 cargo 系工具（ripgrep/fd/bat/eza/delta/…）加这条回退。** `eza` 的收益其实最大（现在在 CentOS 7 上意味着 600MB rustup 加现场编译），但 20 条配方一次上不可评审。本次的配方表结构不阻碍后续加行。
- **不给 `btop` / `duf` 加。** 两者有官方二进制，但都是 `optional` 层、默认不装（btop 还只有 Linux 资产）。等真有人要再加两行配方即可 —— 它们那两种最容易出错的归档结构已经有测试用例在防着了。
- **不解决「github 装的二进制不会被升级」。** 幂等判定只看「PATH 里可执行」，而 `~/.local/bin` 排在包管理器之前。这次改动让该情形更常见，但升级机制是独立的一个改动。

## Capabilities

### Modified Capabilities

- `modern-cli-toolchain`: 「包管理器不可用时的回退」补两条 scenario（本平台无资产、来源必须可见）；新增「发布二进制的获取与校验」一条 requirement，覆盖解包前校验、代理返回 HTML 错误页的识别、以及离线时不逐个超时。
