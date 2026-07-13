# Pastera Main Panel C1 Glass Implementation Plan

**Goal:** 将主面板实现为 C1 克制玻璃视觉，并统一新增组件和模块间距。

**Architecture:** 复用现有 AppKit 主面板结构，通过统一布局常量、系统材质表面和图标操作组件完成改造，不改变数据与安全链路。

**Tech Stack:** Swift, AppKit, XCTest/Swift Testing

## Tasks

1. 先补充统一尺寸、间距、纯图标新增入口和底部无新增入口的失败测试。
2. 调整主面板布局常量与表面材质，统一标题、内容、工具栏的间距和圆角。
3. 将内容区新增组件改为 28×28 图标按钮，补齐 tooltip、辅助功能标签和状态样式。
4. 统一片段、密码箱普通态与编辑态的内容区结构。
5. 运行聚焦测试、完整构建、截图验收、`git diff --check` 和本地安装。
