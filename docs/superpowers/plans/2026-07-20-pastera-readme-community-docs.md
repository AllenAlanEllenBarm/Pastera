# Pastera README 与社区文档改版实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 GitHub 仓库首页和自动展示的社区文档统一为中文，让普通用户能快速理解、下载和安全试用 Pastera，也让贡献者和安全研究者获得准确入口。

**Architecture:** 采用 GitHub 原生 Markdown 和受限 HTML 重组 README 信息层级，复用现有品牌 Hero 与脱敏真实应用截图，不引入网页运行时或新依赖。社区文档按行为规范、贡献流程和安全报告三个职责分别重写，敏感漏洞入口通过 GitHub Private Vulnerability Reporting 落地，LICENSE 与 NOTICE 继续承担法律和历史归属。

**Tech Stack:** GitHub Flavored Markdown、受限 HTML、SVG、GitHub REST API、Git、Shell

## Global Constraints

- README、Code of Conduct、Contributing 和 Security 的公开说明统一使用中文。
- MIT LICENSE 保持标准英文正文及现有版权归属，不修改 `LICENSE` 或 `NOTICE`。
- Clipy 只保留在必要的历史归属和许可证说明中，不再作为当前产品定位、贡献方向或仓库介绍。
- Hero 和顶部导航不硬编码 beta 版本，具体版本只在“当前版本”区域出现一次。
- README 不引入 CSS、JavaScript、外部字体、远程图片或运行时依赖。
- 只使用仓库内现有品牌资产和已经脱敏验证的真实应用截图，不生成虚构界面。
- 图片必须有有效中文替代文本，不用颜色作为唯一信息表达，不使用 Emoji 充当结构化图标。
- README 适配 GitHub 明暗主题，不加入滚动动画、自动播放媒体或低对比装饰。
- 所有新增可见中文不使用英文长破折号或短破折号作为装饰分隔符。
- 当前密码箱功能源码、测试、`.codex/config.toml` 和 `.superpowers/` 不得暂存、修改或清理。
- 本计划不改变产品行为、发布资产、标签、Git 历史、作者信息或 Contributors 统计。

---

## Goal

- 让普通用户在 README 首屏识别 Pastera、找到下载入口并理解当前签名限制。
- 让贡献者通过中文 Contributing 完成范围确认、本地构建、测试和 PR 自检。
- 让安全研究者在 Security 中明确区分公开缺陷和敏感漏洞，并能使用真实私密入口。
- 保持许可证、历史归属、现有产品行为和当前密码箱开发工作完整。

## Architecture

- README 负责产品定位、下载、能力、真实界面、安装、开发和社区路由，不承载完整治理或测试细节。
- Hero 只负责长期有效的品牌识别，不显示具体 beta 版本；版本事实集中到 README 的单一“当前版本”区域。
- Code of Conduct、Contributing 和 Security 各自保持单一职责，通过相互链接形成社区入口。
- GitHub Private Vulnerability Reporting 提供敏感报告通道，GitHub Issues 继续承担不含敏感信息的普通缺陷。
- 本文件是本需求唯一计划和 Delivery Record，设计、实施、验证与偏差持续回写到这里。

## Design System

这是面向普通用户、贡献者和安全研究者的 GitHub 项目入口。视觉语言采用克制、可信、接近 GitHub Primer 的原生阅读体验，同时保留 Pastera 的 macOS 产品气质。

- `DESIGN_VARIANCE: 5`
- `MOTION_INTENSITY: 1`
- `VISUAL_DENSITY: 4`
- 重设计模式：保留式优化
- 页面系统：GitHub 原生 Markdown 与 Primer 渲染语义

## Current Findings

- README 顶部下载入口和更新说明仍指向 `2.0.1-beta`，当前发布版本为 `3.0.0-beta`。
- Hero 仍硬编码 `1.2.2beta`，并混用英文产品文案。
- README 中英文混排，普通用户信息和维护者命令缺少清晰优先级。
- Contributing 仍使用“derived from Clipy”和“fork roadmap”等旧关系表述。
- Contributing 的本地化路径没有反映当前 `Localizable.xcstrings` 与片段编辑器 `.strings` 的真实组合。
- Security 要求敏感报告私下联系维护者，但仓库的 Private Vulnerability Reporting 当前为 `enabled: false`。

## Business Scope / Out of Scope

### In Scope

- 把已经确认的设计规格合并进本文件，保持本需求只有一个计划和交付记录。
- 重写 `README.md` 的品牌入口、下载、能力、界面、安装、构建、状态和社区层级。
- 将 `docs/assets/readme-hero.svg` 改成长期有效的中文品牌视觉并移除版本号。
- 将 `CODE_OF_CONDUCT.md`、`.github/CONTRIBUTING.md` 和 `SECURITY.md` 重写为中文。
- 启用 `pastera-app/Pastera` 的 GitHub Private Vulnerability Reporting。
- 通过静态检查、GitHub Markdown 渲染 API 和 GitHub 仓库 API 回读验证结果。

### Out of Scope

- 修改 `LICENSE`、`NOTICE`、`GOVERNANCE.md`、Funding、路线图或 Windows 实现文档。
- 修改应用源码、测试源码、Xcode 工程、运行时行为或用户数据。
- 修改 Release 资产、标签、版本号、发布正文、分支保护、成员权限或仓库可见性。
- 重写 Git 历史、commit 作者或 Contributors 统计。
- 创建站点、GitHub Pages、独立官网或额外文档框架。

## File Structure

- `docs/superpowers/plans/2026-07-20-pastera-readme-community-docs.md`：本需求唯一计划、验收映射和交付记录。
- `docs/assets/readme-hero.svg`：README 首屏品牌视觉，保留现有尺寸和结构，改成无版本依赖的中文文案。
- `README.md`：面向用户和开发者的 GitHub 项目首页。
- `CODE_OF_CONDUCT.md`：社区参与者行为边界、报告和执行原则。
- `.github/CONTRIBUTING.md`：贡献范围、本地环境、测试、PR、本地化和凭据边界。
- `SECURITY.md`：支持范围、公开缺陷与敏感漏洞分流、安全边界和报告信息。
- `LICENSE`、`NOTICE`：只读审校基线，不产生 diff。

## Tasks

### Task 1: 将 Hero 改成长期有效的中文品牌视觉

**Files:**
- Modify: `docs/assets/readme-hero.svg`

**Interfaces:**
- Consumes: 现有 `1280 x 520` SVG 画布、Pastera 品牌图形、深色中性基调和蓝绿单一强调色。
- Produces: README 可直接引用、无 beta 版本依赖、XML 合法且带中文无障碍描述的 Hero。

- [x] **Step 1: 记录当前 Hero 的过期文案证据**

Run:

```bash
rg -n '1\.2\.2beta|Searchable history|Keyboard-first workflow|Keyword' docs/assets/readme-hero.svg
```

Expected: 返回版本号和英文可见文案，证明当前资产需要更新。

- [x] **Step 2: 更新 Hero 可见文案与无障碍描述**

保持现有几何结构、圆角体系、背景和蓝绿强调色，只做以下内容修改：

- `<title>` 改为 `Pastera macOS 剪贴板效率工具`。
- `<desc>` 改为 `Pastera 深色品牌横幅，展示历史搜索、片段复用和键盘优先操作。`。
- 副标题改为两行：`搜索、复用、粘贴` 和 `保持工作流连续。`。
- 删除 `1.2.2beta` 版本胶囊及其背景矩形，不用其他标签替代。
- `Search history instantly` 改为 `即时搜索历史记录`。
- `Keyboard-first workflow` 改为 `键盘优先操作`。
- `Keyword`、`All`、`Text` 改为 `关键词`、`全部`、`文本`。
- `AI Prompt`、`Screenshot.png` 改为 `AI 提示词`、`截图.png`。

- [x] **Step 3: 验证 SVG 结构和版本独立性**

Run:

```bash
xmllint --noout docs/assets/readme-hero.svg
! rg -n '1\.2\.2beta|2\.0\.1-beta|3\.0\.0-beta|Searchable history|Keyboard-first workflow|Keyword' docs/assets/readme-hero.svg
```

Expected: `xmllint` 退出码为 0，第二条命令无匹配且退出码为 0。

### Task 2: 重写 README 为中文产品首页

**Files:**
- Modify: `README.md`
- Read: `docs/windows-reference/main-panel/03-snippets-empty-dark.jpg`
- Read: `docs/windows-reference/main-panel/04-vault-locked-dark.jpg`
- Read: `docs/windows-reference/preferences/01-general-dark.jpg`
- Read: `docs/funding/OPEN_COLLECTIVE.md`
- Read: `Casks/pastera.rb`

**Interfaces:**
- Consumes: Task 1 的 Hero、`v3.0.0-beta` Release 事实、现有脱敏 macOS 界面截图和仓库内开发命令。
- Produces: 普通用户优先、开发者入口清楚、版本维护面受控的中文 README。

- [x] **Step 1: 记录 README 的现有失败条件**

Run:

```bash
rg -n '2\.0\.1-beta|Latest Beta|Project Status|Highlights|Product Direction|derived from|fork|upstream' README.md
```

Expected: 返回旧版本、英文标题和历史产品关系文案。

- [x] **Step 2: 建立首屏品牌、导航和产品定位**

README 顶部按以下顺序实现：

```markdown
<p align="center">
  <img src="docs/assets/readme-hero.svg" alt="Pastera macOS 剪贴板效率工具" width="100%" />
</p>

<p align="center">
  <a href="#下载">下载</a>&nbsp;&nbsp;
  <a href="#核心能力">功能</a>&nbsp;&nbsp;
  <a href="#安装">安装</a>&nbsp;&nbsp;
  <a href="#构建与本地开发">构建</a>&nbsp;&nbsp;
  <a href="#参与贡献">贡献</a>&nbsp;&nbsp;
  <a href="#安全与隐私">安全</a>
</p>

# Pastera
```

标题后使用两段中文：第一段说明 Pastera 是独立、开源、键盘优先的 macOS 剪贴板效率工具；第二段说明当前 macOS 产品能力和 Windows 原生客户端方向，不把 Clipy 写入产品定位。

- [x] **Step 3: 建立下载、系统要求和可信安装说明**

新增“下载”和“安装”区：

- 顶部 CTA 指向 `https://github.com/pastera-app/Pastera/releases`。
- “当前版本”只出现一次 `3.0.0-beta`，链接到对应 Release。
- 系统要求写为 macOS 13 Ventura 或更高版本。
- 使用 GitHub `> [!WARNING]` 说明 DMG 为 ad-hoc 签名且未经过 Apple 公证。
- 首次打开指引只引导用户在“系统设置 > 隐私与安全性”确认来源，不提供关闭 Gatekeeper 的命令。
- Homebrew Cask 使用仓库内 `Casks/pastera.rb`，说明 GitHub 必须存在匹配 DMG。

- [x] **Step 4: 按用户任务重组核心能力**

使用四个二级内容组，不创建三列等宽卡片：

1. 历史记录与搜索：文本、图片、文件、富文本、分类检索和快速粘贴。
2. 复用与自动化：片段文件夹、脚本转换、快捷键和数字选择。
3. OCR 与资源控制：图片 OCR、持久化任务队列、可见处理状态和有界后台资源。
4. 隐私与同步：KDBX 密码箱、按需 OneDrive 文件夹同步、本地数据和显式权限边界。

只写当前已交付能力，不把规划功能写成已完成。

- [x] **Step 5: 加入非对称真实界面区**

在“界面预览”中使用一张 62% 宽设置图和两张 28% 宽主菜单图：

```html
<p align="center">
  <img src="docs/windows-reference/preferences/01-general-dark.jpg" alt="Pastera 深色模式基础设置页面" width="62%" />
</p>
<p align="center">
  <img src="docs/windows-reference/main-panel/03-snippets-empty-dark.jpg" alt="Pastera 深色模式片段空状态" width="28%" />
  <img src="docs/windows-reference/main-panel/04-vault-locked-dark.jpg" alt="Pastera 深色模式密码箱锁定状态" width="28%" />
</p>
```

紧随图片说明这些画面使用脱敏合成内容，不包含真实剪贴板数据。

- [x] **Step 6: 收拢构建、状态、社区和归属**

- “构建与本地开发”保留 `xcodebuild` build 命令和 `./script/install_local.sh`，完整测试命令链接到 Contributing。
- “项目状态”说明仓库 `isFork: false` 的独立产品边界、macOS 当前基线和 Windows 后续方向。
- “参与贡献”链接 `.github/CONTRIBUTING.md`、`CODE_OF_CONDUCT.md` 和 `GOVERNANCE.md`。
- “安全与隐私”链接 `SECURITY.md` 和 GitHub Security 页面。
- “历史归属与许可证”只保留一句来源摘要，链接 `LICENSE` 和 `NOTICE`。
- 删除旧 Funding 申请状态文案，只保留指向 `docs/funding/OPEN_COLLECTIVE.md` 的稳定资金政策入口。

- [x] **Step 7: 验证 README 旧文案清理和资源存在**

Run:

```bash
! rg -n '1\.2\.2beta|2\.0\.1-beta|Latest Beta|Project Status|Highlights|Product Direction|derived from Clipy|fork roadmap' README.md
for task_asset in docs/assets/readme-hero.svg docs/windows-reference/preferences/01-general-dark.jpg docs/windows-reference/main-panel/03-snippets-empty-dark.jpg docs/windows-reference/main-panel/04-vault-locked-dark.jpg Casks/pastera.rb script/install_local.sh; do test -e "$task_asset"; done
```

Expected: 旧文案无匹配，全部相对资源路径存在。

### Task 3: 重写行为规范与贡献指南

**Files:**
- Modify: `CODE_OF_CONDUCT.md`
- Modify: `.github/CONTRIBUTING.md`
- Read: `pastera/Resources/Localizable.xcstrings`
- Read: `pastera/Sources/Snippets/Base.lproj/CPYSnippetsEditorWindowController.xib`
- Read: `pastera/Sources/Snippets/zh-Hans.lproj/CPYSnippetsEditorWindowController.strings`
- Read: `docs/verification/VERIFICATION.md`

**Interfaces:**
- Consumes: 当前项目安全、隐私、数据和验证边界，以及仓库真实本地化文件结构。
- Produces: 中文行为规范和可从零执行的中文贡献流程。

- [x] **Step 1: 重写 Code of Conduct**

使用以下固定结构：

```markdown
# 社区行为准则
## 我们的承诺
## 期待的行为
## 不可接受的行为
## 适用范围
## 报告与处理
## 执行原则
```

保留尊重、聚焦代码与用户影响、隐私保护、禁止骚扰、禁止泄露凭据和禁止隐藏剪贴板行为等项目专用边界。行为问题通过普通 Issue 或仓库维护者处理，不把漏洞报告流程混入行为规范。

- [x] **Step 2: 重组 Contributing 的贡献路径**

使用以下固定结构：

```markdown
# 参与 Pastera
## 可以贡献什么
## 开始之前
## 本地开发环境
## 构建与测试
## Pull Request 检查清单
## 本地化
## 隐私、凭据与用户数据
## 代码与协议入口
## 评审标准
```

具体要求：

- 删除“derived from Clipy”“fork roadmap”和偏离 fork 目标等当前产品表述。
- 保留 macOS 13+、Xcode 26.5、Swift Package Manager、ad-hoc 本地签名和默认全量测试命令。
- PR 检查清单包含单一行为链、无无关格式化、测试证据、用户数据兼容、权限透明和无凭据。
- 本地化入口写为 `pastera/Resources/Localizable.xcstrings`；片段编辑器继续引用 Base XIB 和现有语言 `.strings`，不列出已经不存在的 Preferences `.strings` 路径。
- 代码入口使用当前 AGENTS 中的 AppDelegate、MenuManager、Services、Database、SnippetRepository 和验证文档路径。
- 路线图名称改成“独立产品路线图”，不使用“Fork roadmap”。

- [x] **Step 3: 验证中文结构和失效路径清理**

Run:

```bash
rg -n '^#|^##' CODE_OF_CONDUCT.md .github/CONTRIBUTING.md
! rg -n -i 'derived from Clipy|fork roadmap|moves the fork|pastera/Resources/.+Localizable\.strings|Preferences/.+\.strings' CODE_OF_CONDUCT.md .github/CONTRIBUTING.md
rg -n 'Localizable\.xcstrings|CPYSnippetsEditorWindowController\.strings|clean test' .github/CONTRIBUTING.md
```

Expected: 标题均为中文，旧产品关系和失效路径无匹配，真实本地化入口与测试命令存在。

### Task 4: 启用私密漏洞报告并重写 Security

**Files:**
- Modify: `SECURITY.md`
- Remote setting: `pastera-app/Pastera` Private Vulnerability Reporting

**Interfaces:**
- Consumes: 用户已确认的远端设置授权、GitHub 仓库管理员权限和当前安全边界。
- Produces: `enabled: true` 的私密报告通道，以及指向该通道的中文安全政策。

- [x] **Step 1: 记录远端设置基线并再次确认仓库目标**

Run:

```bash
gh api repos/pastera-app/Pastera/private-vulnerability-reporting
gh repo view pastera-app/Pastera --json nameWithOwner,isFork,parent --jq '{nameWithOwner,isFork,parent}'
```

Expected: 第一条当前返回 `{"enabled":false}`；第二条返回 `pastera-app/Pastera`、`isFork: false`、`parent: null`。

- [x] **Step 2: 启用并回读 Private Vulnerability Reporting**

Run:

```bash
gh api --method PUT repos/pastera-app/Pastera/private-vulnerability-reporting
gh api repos/pastera-app/Pastera/private-vulnerability-reporting --jq '.enabled'
```

Expected: PUT 成功，回读输出 `true`。若启用失败，停止 Security 文档实施，不发布不可用的私密链接。

- [x] **Step 3: 重写 Security 为中文安全政策**

使用以下固定结构：

```markdown
# 安全政策
## 支持范围
## 报告安全漏洞
## 请提供的信息
## 安全与隐私边界
## 当前分发限制
```

具体要求：

- 最新公开 beta 和 `develop` 为当前支持范围。
- 敏感漏洞链接到 `https://github.com/pastera-app/Pastera/security/advisories/new`。
- 不含敏感信息的普通缺陷链接到 `https://github.com/pastera-app/Pastera/issues/new`。
- 报告信息包含 macOS 与 Pastera 版本、权限状态、最小复现、剪贴板类型、影响、脱敏样本和日志。
- 明确本地数据、网络上传、遥测、自动粘贴、TCC、Accessibility、签名、Apple 公证和凭据边界。
- 不承诺固定 SLA，只说明维护者会确认报告、评估影响并在私密线程同步处理进展。

- [x] **Step 4: 验证 Security 链接与远端状态**

Run:

```bash
rg -n 'security/advisories/new|issues/new|最新公开 beta|develop|ad-hoc|Apple 公证' SECURITY.md
test "$(gh api repos/pastera-app/Pastera/private-vulnerability-reporting --jq '.enabled')" = true
```

Expected: 两类报告入口和关键边界存在，远端回读为 `true`。

### Task 5: 完成跨文档验证并回写交付记录

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-pastera-readme-community-docs.md`
- Verify: `README.md`
- Verify: `docs/assets/readme-hero.svg`
- Verify: `CODE_OF_CONDUCT.md`
- Verify: `.github/CONTRIBUTING.md`
- Verify: `SECURITY.md`
- Verify unchanged: `LICENSE`
- Verify unchanged: `NOTICE`

**Interfaces:**
- Consumes: Tasks 1-4 的本地文档和 GitHub 设置结果。
- Produces: 可复核的 Markdown 渲染、静态检查、远端回读和同一计划内 Delivery Record。

- [x] **Step 1: 运行文本、XML 和工作树卫生检查**

Run:

```bash
git diff --check -- README.md docs/assets/readme-hero.svg CODE_OF_CONDUCT.md .github/CONTRIBUTING.md SECURITY.md docs/superpowers/plans/2026-07-20-pastera-readme-community-docs.md
xmllint --noout docs/assets/readme-hero.svg
! rg -n '—|–' README.md CODE_OF_CONDUCT.md .github/CONTRIBUTING.md SECURITY.md docs/assets/readme-hero.svg
! rg -n '1\.2\.2beta|2\.0\.1-beta|derived from Clipy|fork roadmap|moves the fork' README.md CODE_OF_CONDUCT.md .github/CONTRIBUTING.md SECURITY.md docs/assets/readme-hero.svg
git diff --quiet HEAD -- LICENSE NOTICE
```

Expected: 全部退出码为 0，LICENSE 和 NOTICE 无 diff。

- [x] **Step 2: 通过 GitHub API 渲染全部 Markdown**

Run:

```bash
for task_doc in README.md CODE_OF_CONDUCT.md .github/CONTRIBUTING.md SECURITY.md; do
  task_rendered_bytes=$(jq -Rs --arg task_context 'pastera-app/Pastera' '{text: ., mode: "gfm", context: $task_context}' "$task_doc" | gh api markdown --input - | wc -c | tr -d ' ')
  test "$task_rendered_bytes" -gt 100
done
```

Expected: 四个文档均成功渲染，HTML 输出大于 100 字节。

- [x] **Step 3: 回读 GitHub 仓库状态**

Run:

```bash
gh api repos/pastera-app/Pastera/private-vulnerability-reporting --jq '{enabled}'
gh repo view pastera-app/Pastera --json nameWithOwner,isFork,parent,defaultBranchRef --jq '{nameWithOwner,isFork,parent,defaultBranch: .defaultBranchRef.name}'
```

Expected: `enabled: true`，仓库仍为 `pastera-app/Pastera`、`isFork: false`、`parent: null`、默认分支 `develop`。

- [x] **Step 4: 检查本次范围与既有工作区边界**

Run:

```bash
git status --short
git diff --name-only -- README.md docs/assets/readme-hero.svg CODE_OF_CONDUCT.md .github/CONTRIBUTING.md SECURITY.md docs/superpowers/plans/2026-07-20-pastera-readme-community-docs.md
```

Expected: 本次新增 diff 只涉及计划列出的六个路径；密码箱源码、测试、本机配置和 `.superpowers/` 保持进入本任务前的状态且未暂存。

- [x] **Step 5: 回写同一计划的 Delivery Record**

把真实实现、偏差、影响、验证命令结果、远端回读、剩余风险和后续项写入本文件，不创建第二份规格、计划、验证或交付文档。

- [x] **Step 6: 准备单一文档闭环提交**

```bash
git add README.md docs/assets/readme-hero.svg CODE_OF_CONDUCT.md .github/CONTRIBUTING.md SECURITY.md docs/superpowers/plans/2026-07-20-pastera-readme-community-docs.md
git diff --cached --check
git diff --cached --name-only
git commit -m "docs(readme): 优化中文项目入口与社区文档"
```

Expected: 暂存区只包含本计划列出的六个路径，不包含当前密码箱功能或本机配置。

## Acceptance Mapping

| 验收项 | 实施任务 | 自动化或平台证据 | 人工检查 |
| --- | --- | --- | --- |
| 首屏能识别 Pastera、找到下载并看见签名限制 | Task 1、Task 2 | GitHub Markdown API 渲染、旧版本扫描 | 检查首屏层级和 Warning 位置 |
| README 能力与 `3.0.0-beta` 当前事实一致 | Task 2 | Release 回读、关键文案扫描 | 核对四组能力没有规划冒充已交付 |
| Hero 和顶部导航不随 beta 版本过期 | Task 1、Task 2 | SVG 与 README 版本扫描 | 检查版本只在“当前版本”出现一次 |
| README 使用真实脱敏界面且图片可访问 | Task 2 | `test -e` 路径检查、Markdown 渲染 | 检查截图内容和替代文本 |
| 行为规范与贡献指南统一为中文 | Task 3 | 标题与旧关系扫描、Markdown 渲染 | 检查行为、PR、本地化和凭据边界 |
| 敏感漏洞具有真实私密入口 | Task 4、Task 5 | PVR `enabled: true` API 回读 | 检查 Security 的公开与私密分流 |
| LICENSE、NOTICE 和现有开发工作不受影响 | Task 5 | `git diff --quiet`、暂存区路径回读 | 对照任务前 `git status` |

Evidence Profile: `standard`。本任务具有 XML 静态检查、GitHub Markdown 渲染 API、GitHub 设置 API 和仓库身份回读；不涉及应用行为，因此不运行 Xcode 测试或重新安装应用。

## Risks, Rollback and Observation

- GitHub Markdown 对受限 HTML 的移动端布局可能与桌面不同。先通过 GFM API 渲染，再在后续推送后人工查看仓库首页；若截图过小，回滚到单列大图。
- `3.0.0-beta` 仍可能在后续发布时过期。版本只保留在单一“当前版本”区域，下一次发布只需改一处。
- 全中文文档降低非中文贡献者的直接可读性。这是用户明确选择；代码路径、命令、产品名和 API 名称保持原文以便检索。
- Private Vulnerability Reporting 是远端设置。若启用后需要回滚，使用 `gh api --method DELETE repos/pastera-app/Pastera/private-vulnerability-reporting`，并先把 Security 私密链接改回可用渠道。
- Hero 中的中文字体由 GitHub 和浏览器系统字体解析。若渲染异常，回滚 Hero 文案修改并保留 README 中文替代文本，不引入外部字体。
- 不修改 LICENSE 和 NOTICE；若两者出现 diff，立即停止并从本任务暂存范围排除，不使用重置命令处理用户改动。
- 当前分支含密码箱开发改动。所有暂存操作使用显式 pathspec，并在 commit 前回读暂存文件清单。

## Delivery Metadata

- Plan Path: `docs/superpowers/plans/2026-07-20-pastera-readme-community-docs.md`
- Plan Status: `implemented-and-verified`
- Evidence Profile: `standard`
- Story ID: `not-requested`
- Task IDs: `not-requested`
- Superpowers Task Mapping: `Task 1-5` 构成一个 README 与社区文档业务闭环
- ZenTao Sync Status: `not-synced`
- ZenTao Readback Evidence / Time: `not-requested`
- Design Approval: 用户于 `2026-07-20` 确认“产品首页 + 社区入口”、全中文文档和启用 Private Vulnerability Reporting
- Last Updated: `2026-07-20`

## Delivery Record

### Actual Implementation

- 将 README 重组为中文产品首页，提供长期有效的品牌首屏、下载与签名限制、四组当前能力、真实脱敏界面、安装构建、项目状态、社区入口、安全分流和历史归属。
- 将 Hero 改为无版本依赖的中文品牌视觉，补充中文 `<title>` 与 `<desc>`，移除旧 beta 胶囊和英文界面标签。
- 将 Code of Conduct、Contributing 和 Security 按各自职责重写为中文，补齐真实构建、本地化、隐私、凭据和安全报告边界。
- 已为 `pastera-app/Pastera` 启用 GitHub Private Vulnerability Reporting，并让 Security 指向真实私密报告入口。

### Plan Deviations

- 初始设计记录位于 `docs/superpowers/specs/`。为满足仓库“一项需求只保留一个计划/交付文件”的规则，已将其迁移并合并进本计划，不保留平行规格文件。
- 初选的历史与搜索截图带有可见的 `Windows V1 synthetic` 样本文案。最终改用片段空状态和密码箱锁定状态，避免公开 README 产生平台定位混淆，同时保留脱敏内容说明。
- 当前 `Casks/pastera.rb` 仍对应旧版资产，因此 README 只保留维护者入口，并明确要求版本、SHA-256 和 DMG 一致后再使用，没有把它描述为当前推荐安装方式。

### Impact

- 本地影响仅限 `README.md`、Hero、三份社区文档和本计划，不改变应用源码、测试、Xcode 工程、用户数据、发布资产、`LICENSE` 或 `NOTICE`。
- 远端影响仅为 Private Vulnerability Reporting 从 `enabled: false` 改为 `enabled: true`；仓库身份、默认分支、可见性和权限未变。
- 当前分支中的密码箱源码、测试、本机配置和 `.superpowers/` 既有改动未被修改、清理或纳入本次暂存范围。

### Verification

- `git diff --check`、`xmllint --noout docs/assets/readme-hero.svg`、长破折号扫描、旧版本与旧产品关系扫描均退出 0；`LICENSE` 和 `NOTICE` 无 diff。
- 仓库内 Hero、三张界面图、Cask、安装脚本和 README 引用的本地文档路径均存在。
- GitHub Markdown API 成功渲染四份文档：README `9117` 字节、Code of Conduct `3320` 字节、Contributing `8074` 字节、Security `3739` 字节。
- GitHub API 回读 PVR 为 `enabled: true`；仓库仍为 `pastera-app/Pastera`、`isFork: false`、`parent: null`、默认分支 `develop`。
- Hero 已通过 Quick Look 生成缩略图并人工检查文字、对比度和裁切；临时预览目录随后移入废纸篓。
- 本任务只涉及文档、SVG 和 GitHub 设置，按 `standard` 证据档位不运行 Xcode 测试或安装应用。

### Remaining Risks

- 当前文档位于功能分支，只有推送并合入默认分支后才会替换 GitHub 仓库首页和社区标签内容。
- GitHub 移动端对受限 HTML 图片宽度的实际呈现仍需在默认分支页面人工观察；若两张窄图过小，可回退为单列大图。
- `Casks/pastera.rb` 仍对应 `2.0.1-beta`，发布下一版 Cask 前必须同步版本、SHA-256 和 DMG。
- GitHub Contributors 由保留的 Git 历史计算，本任务没有重写历史或更改贡献者统计。

### Follow-ups

- 后续推送并合入 `develop` 后，人工检查 GitHub 桌面端与移动端首屏、图片和社区标签渲染。
- 发布新的 Homebrew Cask 时同步更新并验证 `Casks/pastera.rb`。

### ZenTao Closeout

- 用户未要求 ZenTao 同步，本任务未查询、未写入、未回读 ZenTao。
