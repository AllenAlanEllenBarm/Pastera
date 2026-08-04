# 提示词优化多模型与中转网关设计

## 背景

Pastera 当前已经通过一条 OpenAI Chat Completions 兼容链路支持 OpenAI、
Gemini、Ollama、LM Studio 和自定义地址，但设置模型仍是“一个远端配置 + 一个
全局 API Key”。用户切换服务时必须覆盖当前地址、模型和密钥，无法同时保留
ChatGPT、Ollama、DeepSeek-V4-Flash 与企业中转网关配置。

本轮将远端能力升级为“多个独立配置档案 + 一个当前启用档案”。现有
OpenAI-compatible 请求、端点校验、来源确认、输出清理和失败保留原文的边界
继续复用，不为每家服务复制一套客户端。

用户给出的中转网关按自定义 OpenAI-compatible 档案处理：

- Base URL：`https://aigateway.variflight.com/api`
- Model：`aliyun/deepseek-v4-flash-0731`
- API Key：只允许在 Pastera 安全输入框中录入并保存到 Keychain，不写入源码、
  UserDefaults、仓库文档、测试夹具或日志。

已经在聊天中暴露过的旧密钥不再作为可用凭据，实施和验收前必须在网关侧轮换，
再把新密钥录入 Pastera。

## 目标

1. 同时保存并切换多个远端模型档案，至少覆盖 OpenAI/ChatGPT、Ollama、
   DeepSeek 官方 API 和自定义中转网关。
2. 每个档案独立保存名称、预设、Base URL、模型名、HTTP 安全选项和 API Key。
3. 保留现有 Ollama `qwen2.5:7b-instruct` 配置与行为，不因升级丢失用户设置或
   Keychain 凭据。
4. 支持模型名包含 `/`、`:`、`-` 和数字，例如
   `aliyun/deepseek-v4-flash-0731` 与 `deepseek-v4-flash:cloud`。
5. 中转地址末尾可以是版本路径或业务路径；上述 `/api` 地址必须解析为
   `/api/chat/completions`，不能重复拼接路径。
6. DeepSeek 官方档案默认使用非思考模式完成提示词改写，以降低响应延迟并避免
   思考内容影响结构化改写结果。
7. 连接测试继续只发送固定探针文本，不发送剪贴板历史或用户草稿。

## 非目标

- 不实现 OpenAI Responses API、Anthropic Messages API 或各厂商私有协议。
- 不实现跨多个档案的自动重试、负载均衡、降级或故障转移，避免文本在未明确
  选择的服务间流转并产生额外费用。
- 不把 API Key 同步到 iCloud、OneDrive、UserDefaults 或其他设备。
- 不在仓库中内置用户专属中转网关或真实凭据；网关地址和模型只作为可输入、
  可验证的兼容示例。
- 不在本轮拉取体积巨大的本地 DeepSeek-V4-Flash 权重。Ollama 的云模型标签
  可以作为可编辑模型名使用，但运行和鉴权仍由本机 Ollama 管理。
- 不改变 Apple Foundation Models 与本地格式化的自动免费路径。

## 方案选择

采用“多档案配置 + 共享 OpenAI-compatible 客户端”。

- 每个远端服务或账号对应一个稳定 UUID 档案。
- 设置只记录非敏感配置；API Key 使用档案 UUID 隔离在 Keychain 中。
- 当前启用档案决定优化和连接测试的唯一目标。
- 预设负责提供默认地址、模型与有限的请求能力差异；自定义档案只使用通用
  Chat Completions 字段。

未采用“继续扩充单一预设枚举”的方案，因为它仍会覆盖当前配置和全局密钥；
未采用“每家服务一个客户端”的方案，因为这些服务已经共享同一请求、响应和
错误语义，复制客户端会放大维护和安全审查范围。

## 配置模型

### 远端档案

新增 `PromptOptimizationRemoteProfile`：

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| `id` | `UUID` | 档案稳定标识，也是 Keychain 账户隔离键 |
| `displayName` | `String` | 设置页显示名，由用户编辑 |
| `preset` | `OpenAICompatiblePreset` | 默认值与请求能力选择 |
| `baseURL` | `String` | OpenAI-compatible Base URL |
| `model` | `String` | 原样发送的模型标识，不限制 `/`、`:` 等合法字符 |
| `allowsInsecureHTTP` | `Bool` | 仅沿用现有非 HTTPS 明示允许策略 |

`PromptOptimizationSettings` 调整为：

- `provider`：继续在“自动免费”和“OpenAI 兼容 — 自备服务”之间选择。
- `remoteProfiles`：远端档案有序列表。
- `activeRemoteProfileID`：当前启用档案 UUID。
- `confirmedOrigins`：沿用按 origin 记录的远端发送确认集合。

设置模型提供一个明确的 `activeRemoteProfile` 解析入口。若保存的活动 UUID 不再
存在，加载时选择列表第一项并回写修复；档案列表为空时创建一个 OpenAI
默认档案，但 provider 仍保持原值。档案显示名去除首尾空白后必须非空，并在
同一列表内按大小写不敏感规则保持唯一；新建重名档案时自动追加数字后缀。

### 预设默认值

预设值只用于新建档案或用户明确应用预设，字段始终允许编辑。

| 预设 | 默认 Base URL | 默认模型 | 请求差异 |
| --- | --- | --- | --- |
| OpenAI / ChatGPT | `https://api.openai.com/v1` | `gpt-5.6-luna` | 通用字段 |
| DeepSeek | `https://api.deepseek.com` | `deepseek-v4-flash` | 增加非思考模式字段 |
| Ollama | `http://127.0.0.1:11434/v1` | `qwen2.5:7b-instruct` | 允许空 API Key |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | 留空 | 通用字段 |
| LM Studio | `http://127.0.0.1:1234/v1` | 留空 | 允许空 API Key |
| 自定义中转 | 留空 | 留空 | 仅发送通用字段 |

OpenAI 默认模型针对低延迟提示词改写选择 Luna，但模型字段不锁定。Ollama 用户
也可以把模型改为 `deepseek-v4-flash:cloud`；Pastera 仍只连接本机 Ollama
端点，不直接处理 Ollama 云服务凭据。

### 旧设置迁移

当新的档案列表键不存在时，设置存储执行一次惰性迁移：

1. 读取现有 preset、Base URL、model 和 `allowsInsecureHTTP`。
2. 生成一个 UUID，将旧远端配置原样放入首个档案并设为当前档案。
3. 保留 provider 与 `confirmedOrigins`。
4. 将完整 `PromptOptimizationSettings` 编码为一个带版本号的 Codable Data，
   写入新的 UserDefaults 键，使档案列表、活动 UUID 和确认来源作为一个快照
   保存。
5. 另存一个非敏感的“旧凭据迁移目标 UUID”标记，供 Keychain 迁移使用。
6. 保留旧 UserDefaults 字段一个兼容周期，但新代码不再写入它们。

当前 Ollama 地址和 `qwen2.5:7b-instruct` 模型因此原样保留。没有旧远端内容的
新安装创建一个带预设地址和模型的 OpenAI 默认档案，继续默认使用“自动免费”。

## 凭据存储与迁移

Keychain service 保持
`com.pastera-app.Pastera.prompt-optimization.v1`，账户从单一固定值改为：

`PasteraPromptOptimizationAPIKey.<profile UUID>`

API Key 存储接口改为按档案 ID 执行 `contains`、`load`、`save` 和 `delete`。
档案 A 的任何操作不得读取、覆盖或删除档案 B 的密钥。安全输入框加载时只展示
“已保存/未保存”状态，不回填明文。

旧固定账户的迁移与设置迁移绑定：

1. 仅首个由旧配置迁移出的档案可以接收旧 Keychain 项。
2. 若新账户不存在，则先复制旧值到新账户；写入成功后再删除旧账户。
3. 若新账户已经存在，不用旧值覆盖它。
4. 任一步骤遇到 Keychain 错误时保留旧账户并报告错误，确保重试可恢复。
5. 复制和删除都成功后清除“旧凭据迁移目标 UUID”标记；中断后可以幂等重试。
6. 迁移不得把密钥读入日志、错误文案或测试快照。

删除已保存档案前必须确认。先删除对应 Keychain 项，成功后再从设置中移除档案；
若 Keychain 删除失败，则保留档案并提示错误，避免产生用户无法管理的孤立凭据。
最后一个档案不可直接删除，可重置为带预设默认值的 OpenAI 档案。

## 组件边界

- `PromptOptimizationRemoteProfile` 只表达一个可持久化档案，不访问网络或
  Keychain。
- `PromptOptimizationSettingsStore` 负责编解码版本化设置快照、旧字段迁移和
  活动档案自修复，不读取密钥。
- `PromptOptimizationAPIKeyStore` 只负责 UUID 到 Keychain account 的映射及旧
  账户迁移，不理解供应商或模型。
- `PromptOptimizationEndpointPolicy` 继续只负责 URL 与安全策略，不推断模型
  类型。
- `OpenAICompatiblePromptOptimizer` 根据档案预设生成最小请求能力差异，并继续
  统一处理 Chat Completions 响应和输出安全校验。
- `PromptOptimizationPreferenceSection` 负责档案选择和用户动作；档案草稿管理
  拆成独立的小型状态对象，避免把迁移、Keychain 规则或请求组装塞入 AppKit
  视图。

这些边界只拆分本功能新增职责，不重构无关的偏好设置或其他模型路径。

## 请求与数据流

### 优化请求

1. `PromptOptimizationService` 加载设置并解析唯一的当前档案。
2. 校验模型非空、Base URL 合法、HTTP 策略和 origin 确认状态。
3. 按当前档案 UUID 从 Keychain 读取密钥。
4. `PromptOptimizationEndpointPolicy` 在 Base URL 后恰好追加一次
   `chat/completions`。
5. 共享客户端发送 `POST`、`Content-Type: application/json`，有非空密钥时
   才发送 `Authorization: Bearer ...`。
6. 请求体保留 `stream: false`、`temperature: 0`、system/user messages 和可选
   `max_tokens`。
7. 只在 `preset == .deepSeek` 时增加
   `"thinking": {"type": "disabled"}`。自定义中转档案不发送厂商专属字段，
   即使模型名包含 `deepseek`。
8. 响应继续读取 `choices[0].message.content`，并经过现有长度限制、语言保持、
   技术标识/URL/占位符/单位锚点和隐藏指令泄露校验。

对示例中转配置，最终请求地址必须是
`https://aigateway.variflight.com/api/chat/completions`，请求体中的模型必须精确为
`aliyun/deepseek-v4-flash-0731`。

### 连接测试

连接测试使用与优化相同的当前档案、端点和 Keychain 项，只发送固定文本
`Return OK`，并限制最大输出 token。首次向新的 origin 发送前继续展示来源确认，
文案明确测试可能产生费用。确认记录按 origin 共享，因此相同 host、scheme、
port 的多个档案不重复确认；路径和模型变化不扩大已确认的网络来源。

### 切换语义

设置页选择另一个档案后，只有保存成功才更新运行时的
`activeRemoteProfileID`。优化请求不自动尝试列表中的其他档案。切换不复制密钥、
不继承上一个档案的测试状态，也不修改其他档案。

## 设置界面

“OpenAI 兼容 — 自备服务”区域增加：

- 当前档案下拉框。
- 新建、重命名和删除档案操作。
- 预设、Base URL、模型、允许不安全 HTTP、API Key 和连接测试控件。
- 当前档案独立的“API Key 已保存/未保存”状态。

编辑使用内存草稿：切换档案时把当前输入写入草稿，不发起网络请求；点击保存时
统一校验并原子写入非敏感设置。新建但尚未保存的档案不能保存 API Key，避免
取消设置后遗留孤立 Keychain 项。测试连接先保存当前设置和待保存密钥，再按
既有来源确认流程执行。

应用预设不会覆盖用户已经编辑的地址或模型，除非用户明确执行“应用预设默认值”。
创建档案时则直接填入所选预设的默认值。自定义中转档案完整保留 Base URL 的
路径部分和模型名，不进行供应商名称推断。

验证错误继续显示在当前卡片中：名称为空、模型为空、地址无效、非本地 HTTP
未明示允许、Keychain 失败、未授权、限流、超时和服务端拒绝都必须可区分。
切换档案时清除上一个档案的瞬时连接结果。

## 错误与安全边界

- 非 loopback HTTP 默认拒绝；用户必须显式允许不安全 HTTP。
- URL 不允许用户名、密码、query 或 fragment，避免凭据进入可见配置。
- HTTPS 中转网关仍必须经过首次 origin 确认。
- 401/403、429、超时、取消、无效响应和其他服务端状态保持现有分类。
- 远端优化失败不自动切换模型，也不覆盖原草稿；输出校验失败返回
  `.invalidResponse`，上层保留原文。
- 请求和错误日志不得包含 API Key、Authorization header、用户正文或完整响应。
- 自定义中转只承诺 OpenAI Chat Completions 兼容性；厂商私有字段由中转服务
  自行处理。

## 测试策略

### 模型与设置存储

- 各预设的默认 Base URL、默认模型和请求能力准确。
- 多档案保存、顺序、当前档案切换和无效活动 UUID 自修复。
- 旧单配置只迁移一次，UUID 稳定，Ollama 模型和确认来源不丢失。
- 空白新安装仍默认走自动免费路径。

### Keychain

- 不同 UUID 的密钥完全隔离。
- 旧固定账户只迁移到旧配置对应档案，不覆盖已有新账户。
- 复制成功后删除旧账户；写入或删除失败时保持可恢复状态。
- 删除档案失败时不移除设置记录；最后一个档案执行重置。

### 端点与请求

- `/api`、`/v1` 和已带 `/chat/completions` 的地址都只追加一次目标路径。
- 模型名含 `/`、`:`、`-` 时按原值编码到 JSON。
- 非空密钥发送 Bearer header，空密钥不发送 Authorization。
- DeepSeek 官方预设发送非思考字段；OpenAI、Ollama 和自定义中转不发送该字段。
- 当前档案决定地址、模型和密钥，失败时不调用其他档案。
- 连接测试只发送固定探针并使用当前档案。

### 设置界面与安装验收

- 新建、重命名、切换、保存和删除档案的状态转换。
- 切换后显示正确的字段与 Keychain 状态，瞬时测试结果不会串档案。
- 自定义中转示例保存后生成正确端点与模型。
- 相关单元测试和完整 macOS 回归通过后运行 `./script/install_local.sh`。
- 在安装版中分别验证本机 Ollama 与一个已轮换密钥的 HTTPS 中转档案；不得在
  命令行参数、构建日志或截图中暴露密钥。

## 验收标准

1. 用户可以同时保留 OpenAI/ChatGPT、Ollama、DeepSeek 官方与自定义中转档案，
   并明确选择其中一个作为当前模型。
2. 现有 Ollama `qwen2.5:7b-instruct` 配置和旧 API Key 在升级后仍可使用。
3. 每个档案只访问自己的 Keychain 密钥，删除和切换不会影响其他档案。
4. DeepSeek 官方请求使用 `deepseek-v4-flash` 和非思考模式。
5. 示例中转地址正确请求 `/api/chat/completions`，模型名保持
   `aliyun/deepseek-v4-flash-0731`，且不发送 DeepSeek 厂商专属字段。
6. 所有远端请求都保留 HTTPS/HTTP、来源确认、固定连接探针和输出安全校验边界。
7. 远端失败不会静默切换到其他服务，也不会用无效输出覆盖用户草稿。
8. 用户轮换后的新密钥只通过安装版安全输入框录入；仓库和测试产物中不存在
   明文凭据。
