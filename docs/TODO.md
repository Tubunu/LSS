# 项目台账（Project Ledger）

本文档是 LongShot 项目的唯一真相台账，记录所有待办需求与技术债务。

## 1. 活跃需求池（Active Requirements）

| # | 模块 | 需求描述 | 状态 | 关联批次 | 优先级 |
|:---|:---|:---|:---|:---|:---|
| 1 | Capture | 修复点击【开始捕获】系统选择器闪退缺陷 | 已收口 | `docs/batches/2026-09-21-FIX-CAPTURE-CRASH.md` | P0 |
| 2 | Capture | 修复关闭屏幕选择器返回 App 误触发提前停止捕获缺陷 | 已收口 | `docs/batches/2026-09-21-FIX-PREMATURE-CAPTURE-STOP.md` | P0 |
| 3 | Capture | 恢复 screen-capture 后台模式与保活，修复切到其他 App 录制中断缺陷 | 已收口 | `docs/batches/2026-09-21-FIX-BACKGROUND-SCREEN-CAPTURE.md` | P0 |
| 4 | Stitch | 修复过渡帧污染与拼接引擎低置信度阻塞缺陷 | 已收口 | `docs/batches/2026-09-21-FIX-STITCH-TRANSITION-FRAMES.md` | P0 |

*状态流转：`待讨论` -> `已规划` -> `进行中` -> `已收口` -> `已挂起`*

---

## 2. 技术债与缺陷记录（Tech Debt & Backlog）

| # | 发现来源 | 问题描述 | 阻塞级别 | 计划处置批次 |
|:---|:---|:---|:---|:---|
| D1 | 真机运行 | iOS 27 真机点击开始捕获闪退（unrecognized selector `presentUsing:`） | 🔴 Critical（已闭环） | 2026-09-21-FIX-CAPTURE-CRASH |
| D2 | 真机运行 | 选择屏幕后关闭选择器浮层时 appDidBecomeActive 误将前台激活判定为切回而提前 stopCapture | 🔴 Critical（已闭环） | 2026-09-21-FIX-PREMATURE-CAPTURE-STOP |
| D3 | 真机运行 | 缺失 UIBackgroundModes: screen-capture 导致切出前台时 SCStream 被系统 -3824 掐断 | 🔴 Critical（已闭环） | 2026-09-21-FIX-BACKGROUND-SCREEN-CAPTURE |
| D4 | 真机运行 | 采样混入前台过渡帧导致 StitchEngine 首尾不匹配，且 lowConfidence 一票否决阻断渲染 | 🔴 Critical（已闭环） | 2026-09-21-FIX-STITCH-TRANSITION-FRAMES |

---

## 3. 归档记录（Archived）

| # | 事项 | 最终状态 | 闭环批次 | 闭环日期 |
|:---|:---|:---|:---|:---|
| 1 | 修复点击【开始捕获】闪退缺陷 | 已收口 | BATCH-20260921-FIX-CAPTURE-CRASH | 2026-09-21 |
| 2 | 修复关闭选择器误提前停止捕获缺陷 | 已收口 | BATCH-20260921-FIX-PREMATURE-CAPTURE-STOP | 2026-09-21 |
| 3 | 恢复后台屏幕捕获与保活 | 已收口 | BATCH-20260921-FIX-BACKGROUND-SCREEN-CAPTURE | 2026-09-21 |
| 4 | 修复过渡帧污染与拼接低置信度阻塞缺陷 | 已收口 | BATCH-20260921-FIX-STITCH-TRANSITION-FRAMES | 2026-09-22 |
| - | Phase 0~3 核心功能开发与 CI 打包发布 | 已收口 | 初始批 | 2026-09-21 |
