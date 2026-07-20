# Pastera README 与社区文档改版设计

## 目标

把 GitHub 仓库首页和自动展示的社区文档统一为中文，让普通用户能快速理解、下载和安全试用 Pastera，也让潜在贡献者能找到准确的开发、测试、行为规范和漏洞报告入口。

本次改版不改变产品行为、发布流程、开源许可证或历史作者信息。

## 已确认方向

- 采用“产品首页 + 社区入口”方案。
- README、Code of Conduct、Contributing 和 Security 统一使用中文。
- MIT LICENSE 保持标准英文正文及现有版权归属。
- Clipy 只保留在必要的历史归属和许可证说明中，不再出现在当前产品定位、贡献方向或仓库介绍中。
- 启用 GitHub Private Vulnerability Reporting，给敏感漏洞提供可操作的私密入口。
- 在当前工作树和当前分支实施，只触达本规格明确列出的文档、README 视觉资产与 GitHub 安全设置。

## 设计判断

这是面向普通用户、贡献者和安全研究者的 GitHub 项目入口。视觉语言应克制、可信、接近 GitHub Primer 的原生阅读体验，同时保留 Pastera 的 macOS 产品气质。

- `DESIGN_VARIANCE: 5`
- `MOTION_INTENSITY: 1`
- `VISUAL_DENSITY: 4`

GitHub README 由 Markdown 和受限 HTML 渲染，不引入 CSS、JavaScript、外部字体或运行时依赖。层级、文案、真实界面图和稳定链接构成主要设计手段。

## 当前问题

### README

- 顶部下载入口和更新说明仍指向 `2.0.1-beta`，当前发布版本已经是 `3.0.0-beta`。
- Hero 视觉内仍硬编码 `1.2.2beta`，容易持续过期。
- 中英文混排，产品定位、发布说明和开发文档的阅读节奏不一致。
- 普通用户信息与维护者命令连续堆叠，下载、风险提示和构建入口缺少清晰优先级。
- 当前产品能力已经扩展到 OCR、脚本、密码箱和同步，但 Highlights 仍主要描述早期剪贴板能力。

### 社区文档

- Contributing 仍使用“derived from Clipy”和“fork roadmap”等旧产品关系表述。
- 本地化说明仍以旧 `.strings` 路径为主，需要按当前仓库事实重新核对。
- Security 要求敏感报告“私下联系维护者”，但仓库未提供实际私密入口。
- Code of Conduct、Contributing 和 Security 均为英文，与已确认的中文公开文档方向不一致。

## README 信息架构

### 1. 品牌与首要操作

- 保留 Pastera Hero，但删除具体版本号，改成长期有效的产品能力表达。
- Hero 下方提供精简导航：下载、功能、安装、构建、贡献、安全。
- 主标题后的首段用一句中文说明产品价值，再补一段独立产品与当前平台状态。
- 首要操作指向 Releases 总入口，避免每次 beta 发布都需要修改顶部 CTA。

### 2. 下载与信任提示

- 当前版本显示为 `3.0.0-beta`，链接到对应 Release。
- 明确系统要求为 macOS 13 或更高版本。
- 使用 GitHub Warning 提示当前 DMG 为 ad-hoc 签名且未经 Apple 公证。
- 提供最短的首次打开指引，但不鼓励绕过系统安全机制。

### 3. 产品能力

按用户任务分成四组，不使用三个等宽功能卡片：

1. 历史记录与搜索：文本、图片、文件、富文本和分类检索。
2. 复用与自动化：片段文件夹、脚本转换和键盘优先操作。
3. OCR 与资源控制：图片 OCR、持久化任务队列和可见处理状态。
4. 隐私与同步：KDBX 密码箱、按需 OneDrive 文件夹同步和本地数据边界。

功能描述只写当前已经交付的事实，规划中的 Windows 客户端单独放在项目状态中。

### 4. 真实界面

- 复用仓库中不含真实隐私数据的当前应用截图。
- 以一张设置总览和两张主菜单状态图组成非对称画面。
- 所有图片提供准确的中文替代文本。
- 不生成虚构界面，不用装饰性库存图替代真实产品。

### 5. 安装、构建与开发

- 普通用户安装放在前面，开发者构建放在后面。
- 保留仓库内 Homebrew Cask 路径，但清楚说明它依赖匹配的 GitHub DMG。
- 保留无签名构建命令和 `install_local.sh`，不在 README 重复完整测试矩阵。
- 将完整贡献流程、架构入口和验证命令链接到 Contributing。

### 6. 项目状态与社区

- 说明 macOS 是当前可执行基线，Windows 为同仓库下的后续原生客户端方向。
- 说明仓库是独立 Pastera 产品，不跟踪产品 upstream。
- 集中提供 Contributing、Code of Conduct、Security、Governance、路线图和许可证入口。
- 历史归属保持简短，详细内容链接到 LICENSE 和 NOTICE。

## 社区文档设计

### Code of Conduct

采用简洁的项目专用行为规范，包含：

- 项目承诺。
- 期待行为。
- 不可接受行为。
- 适用范围。
- 报告方式。
- 执行原则。

报告行为问题与报告安全漏洞使用不同入口，避免把敏感漏洞发到普通 Issue。

### Contributing

按贡献路径重组：

1. 可以贡献什么。
2. 开始前如何确认范围。
3. 本地环境与构建要求。
4. 测试与手工验证。
5. Pull Request 检查清单。
6. 本地化更新方式。
7. 隐私、凭据和用户数据边界。
8. 关键代码与协议入口。

贡献文档不再称 Pastera 为 fork，也不要求贡献者理解 Clipy 的开发节奏。

### Security

- 列出当前支持范围：最新公开 beta 和 `develop`。
- 敏感漏洞通过 GitHub Private Vulnerability Reporting 提交。
- 不含敏感信息的普通缺陷通过 GitHub Issues 提交。
- 给出复现环境、权限状态、剪贴板类型、影响和最小样本清单。
- 明确本地数据、网络上传、遥测、自动粘贴、TCC、Accessibility、签名与凭据边界。
- 不编造固定响应 SLA，只承诺确认报告、评估影响并通过私密报告线程同步进展。

### LICENSE 与 NOTICE

- LICENSE 不修改，继续保留标准 MIT 英文正文以及 Clipy Project 和 Pastera contributors 的版权行。
- NOTICE 保留历史来源、Pastera 后续维护和第三方依赖归属。
- README 中只做必要的历史归属摘要，不重复大段法律文本。

## GitHub 设置

调用 GitHub 仓库接口启用 Private Vulnerability Reporting。启用后，Security 文档链接到：

`https://github.com/pastera-app/Pastera/security/advisories/new`

该设置只新增私密报告通道，不改变仓库可见性、成员权限、分支、Release 或 Actions。

## 可访问性与维护规则

- 图片必须有有效替代文本。
- 不用颜色作为唯一信息表达。
- 不使用 Emoji 充当结构化图标。
- 不加入滚动动画、自动播放媒体或依赖主题的低对比装饰。
- 不使用长串徽章墙，最多保留发布、平台和许可证等必要状态。
- Hero 和导航不硬编码 beta 版本，具体版本只在“当前版本”区域出现一次。
- README 可随 GitHub 明暗主题正常阅读，不在文档中锁定单一页面主题。
- 所有可见中文不使用英文长破折号或短破折号作为装饰分隔符。

## 文件范围

计划修改：

- `docs/superpowers/specs/2026-07-20-pastera-readme-community-docs-design.md`
- `README.md`
- `docs/assets/readme-hero.svg`
- `CODE_OF_CONDUCT.md`
- `.github/CONTRIBUTING.md`
- `SECURITY.md`

只审校、不修改：

- `LICENSE`
- `NOTICE`

远端设置：

- `pastera-app/Pastera` Private Vulnerability Reporting

不在范围：

- 应用源码、测试源码和 Xcode 工程。
- Release 资产、标签、版本号和发布正文。
- Git 历史、commit 作者和 Contributors 统计。
- Governance、Funding、路线图和 Windows 实现文档的内容重写。

## 验证与验收

### 文档验证

- 检查 Markdown 标题层级和内部锚点。
- 检查仓库内相对链接和图片路径存在。
- 检查 README 不再出现 `1.2.2beta`、`2.0.1-beta` 或当前 fork 产品表述。
- 检查 Contributing 不再出现已经失效的 `.strings` 路径和 fork 方向表述，同时保留片段编辑器仍在使用的真实 `.strings` 入口。
- 检查所有改版文档为中文，代码标识、路径、产品名和 API 名称保持原文。
- 检查 README 可见文本不含装饰性英文长破折号和短破折号。
- 检查 `git diff --check`。

### 远端验证

- 回读 `private-vulnerability-reporting`，必须得到 `enabled: true`。
- 验证私密报告 URL 可由 GitHub Security 页面访问。
- 回读仓库身份，继续保持 `isFork: false`、`parent: null`。

### 工作区边界

- 最终 diff 只能包含本规格列出的设计规格、文档和 Hero 资产。
- 当前密码箱功能源码、测试、`.codex/config.toml` 和 `.superpowers/` 不得暂存、修改或清理。

## 成功标准

1. 用户在仓库首页首屏能识别 Pastera、找到下载入口并看见签名限制。
2. README 的产品能力与 `3.0.0-beta` 当前事实一致，版本迭代时不需要修改 Hero 和顶部导航。
3. 贡献者能在一个中文文档中完成范围确认、本地构建、测试和 PR 自检。
4. 敏感安全报告具有真实、私密、可回读的 GitHub 入口。
5. LICENSE、NOTICE、历史作者和现有开发工作区保持完整。
