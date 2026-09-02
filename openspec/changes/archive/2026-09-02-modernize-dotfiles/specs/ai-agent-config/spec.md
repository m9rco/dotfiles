## ADDED Requirements

### Requirement: AI 配置单一真源

系统 SHALL 把 AI 相关配置的真源集中在 `config/ai/` 下：`mcp.json`（MCP server 清单）、`agents/`（agent 定义）、`skills/`（skill 定义）、`commands/`（slash command 定义）。同一份内容 MUST NOT 在仓库中存在多份平行副本。

#### Scenario: 真源目录存在

- **WHEN** 检查仓库结构
- **THEN** `config/ai/` 下存在 `mcp.json`、`agents/`、`skills/`、`commands/`

#### Scenario: 无重复副本

- **WHEN** 检索仓库中的 agent 与 skill 定义
- **THEN** 每份定义只存在于 `config/ai/` 下一处

### Requirement: agent 与 skill 跨工具链接

系统 SHALL 通过符号链接把 `config/ai/agents/`、`config/ai/skills/`、`config/ai/commands/` 接入各 AI 工具期望的目录位置。链接 MUST 使用统一的备份原语，MUST NOT 在未备份的情况下覆盖用户已有的真实目录。

#### Scenario: agents 目录被链接

- **WHEN** 执行该模块
- **THEN** 目标工具的 agents 目录成为指向 `config/ai/agents/` 的符号链接

#### Scenario: 已有真实目录被备份

- **WHEN** 目标工具的 agents 位置已存在用户的真实目录
- **THEN** 原目录被移动到备份位置
- **AND** 目标位置成为指向仓库的符号链接
- **AND** 备份内容与原目录一致

#### Scenario: 修改立即对所有工具生效

- **WHEN** 在 `config/ai/agents/` 中新增一个 agent 定义
- **THEN** 所有已链接的 AI 工具都能看到该 agent
- **AND** 无需重复复制文件

### Requirement: MCP 配置渲染

由于各 AI 工具的 MCP 配置 schema 不同，系统 SHALL 从 `config/ai/mcp.json` 渲染出各工具所需的配置文件，而不是为每个工具维护一份手写配置。渲染逻辑 MUST 集中在单一模块内。渲染产物 MUST 是确定性的：相同输入产生相同输出。

#### Scenario: 从单一清单渲染多工具配置

- **WHEN** 执行该模块
- **THEN** 各目标 AI 工具的 MCP 配置文件由 `config/ai/mcp.json` 渲染生成

#### Scenario: 修改清单后各工具同步

- **WHEN** 在 `config/ai/mcp.json` 中新增一个 MCP server 条目
- **THEN** 重新执行该模块后各工具的配置都包含该 server
- **AND** 只需修改一处

#### Scenario: 渲染确定性

- **WHEN** 在 `mcp.json` 未变更的情况下连续两次执行渲染
- **THEN** 两次生成的配置文件内容完全一致

#### Scenario: 渲染逻辑集中

- **WHEN** 某 AI 工具的 MCP schema 发生变化
- **THEN** 只需修改渲染模块一处即可适配

### Requirement: 清单格式校验

系统 SHALL 在渲染前校验 `config/ai/mcp.json` 是合法 JSON 且符合约定的必需字段。校验失败时 MUST 报告具体的错误位置或缺失字段，并 MUST NOT 写出任何工具配置文件（避免用损坏内容覆盖可用配置）。

#### Scenario: 非法 JSON 被拒绝

- **WHEN** `config/ai/mcp.json` 存在语法错误
- **THEN** 系统输出具体错误信息并使该模块失败
- **AND** 现有的工具 MCP 配置文件未被修改

#### Scenario: 缺少必需字段被拒绝

- **WHEN** 某 MCP server 条目缺少必需字段
- **THEN** 系统报告该条目及缺失的字段名
- **AND** 不写出任何工具配置文件

### Requirement: 配置的平台无关表示

`config/ai/` 中的配置 SHALL 以平台无关方式表达路径与命令。任何需要绝对路径或平台特有命令的地方 MUST 使用可在渲染时解析的占位表示，MUST NOT 硬编码某台机器或某个平台的绝对路径。

#### Scenario: 无硬编码用户路径

- **WHEN** 检索 `config/ai/` 下所有文件
- **THEN** 不存在硬编码的用户主目录绝对路径

#### Scenario: 占位符在渲染时解析

- **WHEN** 配置中使用了路径占位表示且执行渲染
- **THEN** 生成的配置文件中占位符被替换为当前平台的实际路径

#### Scenario: 同一清单在三平台可用

- **WHEN** 在 macOS、Linux 与 Windows 上分别渲染同一份 `mcp.json`
- **THEN** 三个平台各自得到路径正确的可用配置

### Requirement: 保留工具的本地配置

系统 MUST NOT 覆盖 AI 工具配置文件中不由本仓库管理的用户本地设置。渲染 MUST 只更新受管理的部分，或提供不入库的本地覆盖文件机制。

#### Scenario: 本地设置在渲染后保留

- **WHEN** 某 AI 工具的配置文件中包含不由仓库管理的用户设置且执行渲染
- **THEN** 这些用户设置在渲染后仍然存在

### Requirement: 幂等与预演

该模块 SHALL 幂等：已正确链接与已渲染且内容未变时 MUST NOT 产生文件变更。在 `--dry-run` 下 MUST 只输出将建立的链接与将渲染的目标文件，MUST NOT 写入任何文件。

#### Scenario: 重复执行无变更

- **WHEN** 该模块已成功执行过且清单未变更，再次执行
- **THEN** 没有文件被修改
- **AND** 没有新增备份

#### Scenario: dry-run 只打印计划

- **WHEN** 执行 `./bootstrap.sh --dry-run --only ai-agent-config`
- **THEN** 输出将建立的符号链接与将渲染的配置文件路径
- **AND** 没有任何文件被写入

### Requirement: 工具未安装时的处理

系统 SHALL 在目标 AI 工具未安装时跳过其配置链接与渲染，并输出跳过原因，MUST NOT 因此使模块失败。

#### Scenario: 工具缺失则跳过其配置

- **WHEN** 某 AI 工具未安装而执行该模块
- **THEN** 该工具的配置步骤被跳过并说明原因
- **AND** 其他已安装工具的配置正常完成
- **AND** 模块以成功状态结束
