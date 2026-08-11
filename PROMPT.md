# Codex Master Prompt — LongShot iOS 27+ 滚动长截图 App

你现在位于一个用于开发 iOS App 的项目目录中。

请完整阅读当前目录中的：

```text
PLAN.md
PROMPT.md
AGENTS.md（如果存在）
README.md（如果存在）
```

然后检查：

```bash
pwd
git status
git branch --show-current
git log --oneline --decorate -15
git remote -v
find . -maxdepth 2 -type f | sort | head -200
```

你的任务是开发一款：

> **iOS 27+ 原生滚动长截图 App。用户通过 ScreenCaptureKit 授权 Full Display Capture 后，可以切换到其他 App 持续滚动；本 App 在后台接收屏幕帧，智能抽取关键帧、识别重叠区域和固定 UI，自动生成一张连续长截图，并支持基础编辑、导出、历史管理。**

项目工作名称：

```text
LongShot
```

如果现有 Xcode 工程已有正式名称，不要为了工作名称强行重命名已有工程。

---

# 一、最高优先级原则

严格按：

```text
PLAN.md
```

中的 Phase 顺序执行。

不要一上来同时开发所有功能。

必须：

```text
Phase 0
→ 验收
→ commit

Phase 1
→ 验收
→ commit

Phase 2
→ 验收
→ commit

...
```

只有上一 Phase 已达到 Gate 条件，才进入下一阶段。

如果某个阶段因为系统 API、签名、真机、权限或 Xcode 环境无法完成：

1. 不要假装成功；
2. 不要用 mock 代替必须的真机验证并宣称通过；
3. 明确记录 blocker；
4. 完成所有仍然可以可靠完成的部分；
5. 提供具体下一步；
6. 保持代码可编译、可恢复。

---

# 二、平台要求

必须：

```text
iPhone
iOS 27.0+
Swift
SwiftUI
ScreenCaptureKit
```

核心屏幕捕获路线：

```text
SCContentSharingPicker
        ↓
SCStream
        ↓
SCStreamOutput
        ↓
CMSampleBuffer
        ↓
FrameSampler
        ↓
Key Frames
        ↓
StitchEngine
        ↓
Long Screenshot
```

不需要支持：

```text
iOS 26
ReplayKit Broadcast Upload Extension
```

除非在当前 iOS 27 SDK 中 Apple 官方 API 与计划存在重大变化，需要调整时必须先以实际 SDK 编译结果和 Apple 官方文档为准。

---

# 三、开始开发前：先核实现有 SDK

iOS 27 / ScreenCaptureKit 属于新平台能力。

不要根据模型记忆直接编造 API。

首先：

1. 检查 Xcode 版本；
2. 检查当前 SDK；
3. 检查项目 Deployment Target；
4. 在本机 SDK 中确认 ScreenCaptureKit iOS API；
5. 必要时使用：
   - Xcode SDK headers / Swift interfaces；
   - `xcrun`；
   - `xcodebuild`；
   - Apple Developer Documentation。

重点确认：

- `SCContentSharingPicker`
- Full Display Capture；
- `SCStream`
- `SCStreamConfiguration`
- Background `screen-capture` mode；
- `NSScreenCaptureUsageDescription`
- 进入后台后 Stream 生命周期。

如果 PLAN.md 中 API 名称与当前 SDK 实际发生变化：

- 以当前 SDK 为准；
- 更新代码；
- 在 docs 中记录差异；
- 不降低产品目标。

---

# 四、Phase 0 必须首先完成

不要先开发漂亮首页。

首先建立最小 PoC，验证：

```text
LongShot
→ 调起系统 Screen Capture Picker
→ 用户选择 Full Display
→ SCStream 开始
→ App 接收到 CMSampleBuffer
→ 用户切换到其他 App
→ 用户滚动至少 30 秒
→ LongShot 在后台继续收到有效帧
→ 用户返回
→ frame counter 继续增长过
→ 保存数张测试关键帧
→ 测试帧确实来自其他 App
→ 正常 stop
```

这项验证是整个项目的 P0 Gate。

如果当前执行环境没有 iOS 27 真机：

- 完成可编译 PoC；
- 创建 `docs/phase0-device-verification.md`；
- 写出精确手动验收步骤；
- Phase 0 状态只能标为：

```text
CODE COMPLETE / DEVICE VERIFICATION PENDING
```

不能写 PASS。

---

# 五、项目架构要求

建议分层：

```text
UI
↓
Feature / ViewModel
↓
Capture / Stitch / Storage Services
↓
Core Imaging
```

必须确保：

## Capture

负责：

- ScreenCaptureKit；
- SCStream lifecycle；
- capture state；
- frame delivery。

不负责：

- UI；
- 大型图像拼接；
- History 页面。

## FrameSampler

负责：

- 控制采样；
- 重复帧检测；
- movement detection；
- key frame decision。

## StitchEngine

负责：

- overlap detection；
- offset estimation；
- fixed regions；
- seam selection；
- stitch plan。

必须可以完全脱离 ScreenCaptureKit 做单元测试。

## Renderer

负责：

- preview；
- tile rendering；
- final output。

## Editor

操作的是：

```text
StitchPlan
```

而不是直接破坏原始截图。

---

# 六、禁止保存全部帧

这是硬性要求。

禁止：

```text
SCStream 60fps
→ 每个 CMSampleBuffer
→ UIImage
→ PNG
→ 磁盘
```

正确方向：

```text
CMSampleBuffer
      ↓
cheap sampling
      ↓
thumbnail/signature
      ↓
duplicate check
      ↓
motion check
      ↓
key frame
      ↓
only useful frame persisted
```

要避免：

- memory explosion；
- disk explosion；
- CPU explosion；
- thermal problem。

不要频繁把 `CVPixelBuffer` 转成 `UIImage`。

优先：

- CoreVideo；
- CoreImage；
- Accelerate；
- Metal（仅真正需要时）。

---

# 七、StitchEngine 要求

不要实现成：

```swift
overlapHeight = image.height / 2
```

或者：

```text
固定裁掉 200 px
```

必须真正进行图像匹配。

第一阶段优先解决：

```text
Frame A
Frame B

↓
estimate vertical displacement
↓
detect overlap
↓
calculate confidence
↓
select seam
↓
create StitchSegment
```

数据结构至少要能够表示：

```text
offset
overlap
confidence
seam
fixed regions
warning
```

算法 threshold 必须集中管理。

不要散落 magic number。

---

# 八、固定 UI 区域

必须专门处理：

- status bar；
- navigation bar；
- fixed header；
- search bar；
- tab bar；
- bottom input bar；
- floating buttons。

不能让每一屏都重复：

```text
顶部导航
内容
顶部导航
内容
顶部导航
内容
```

应该通过：

```text
multi-frame stable region detection
```

识别固定区域。

自动算法无法确定时：

- 保留原始 frame；
- 标记低 confidence；
- 交给 Editor 手动处理。

---

# 九、滚动行为

优先支持：

```text
向下滚动
```

需要容忍：

- 停顿；
- 非匀速；
- 小幅向上回滚；
- 再继续向下。

不强制 V1 完美支持：

- 大范围来回滚；
- 横向 feed；
- 横纵混合滚动；
- 页面实时大量重排。

不要因为 edge case 让整个 session 崩溃。

---

# 十、超长图片

必须避免：

```text
把最终 100 屏图片全部作为一个巨大 UIImage 长期留在内存
```

使用：

- preview proxy；
- StitchPlan；
- segment；
- Tile Rendering；
- 分阶段 export。

目标：

- 普通长文章流畅；
- 10 / 30 / 50 屏稳定；
- 更长内容合理退化；
- 资源不足时给用户明确提示而不是 OOM。

---

# 十一、UI / UX

产品设计必须有明显完成度。

关键词：

```text
原生
克制
现代
轻
内容优先
iOS 27
```

首页核心：

```text
LongShot

把滚动页面
变成一张完整截图。

[ 开始滚动截图 ]

导入截图拼接

最近项目
```

避免：

- 工具箱式首页；
- 十几个彩色按钮；
- Android 风格 floating overlay；
- 复杂 tab；
- 大面积无意义 gradient；
- 自绘假的 system picker；
- 过量 blur；
- 过量玻璃。

使用系统 Navigation / Toolbar / Sheet / Menu / Picker。

加入：

- 合适 animation；
- haptic；
- progress；
- success feedback；
- recoverable error UI；
- Dark / Light；
- accessibility。

---

# 十二、Capture UX

首次点击「开始滚动截图」时：

简洁说明：

```text
1. 选择整个屏幕
2. 切换到需要截图的 App
3. 缓慢向下滚动
4. 完成后停止捕获
5. 返回 LongShot 自动生成
```

明确说明：

> 屏幕内容仅在设备本地处理。

开始后：

- UI 状态清晰；
- 不出现复杂设置；
- 记录 elapsed time；
- 记录 selected key frames；
- stop action 明确。

---

# 十三、Processing UX

Capture 结束：

```text
正在整理截图…
↓
正在匹配滚动内容…
↓
正在生成长截图…
↓
Editor
```

不要向普通用户显示：

```text
running NCC
offset=824
MSE=0.031
```

这些内容只进入 diagnostics / debug log。

---

# 十四、Editor

第一版只做最重要功能：

```text
裁剪
接缝
片段
导出
```

必须：

### Crop

- top；
- bottom；
- left；
- right。

### Seam

- 点击问题接缝；
- 上下微调；
- 可恢复自动结果。

### Segment

- 删除错误段；
- Undo；
- 保留原始 frame。

### Export

- PNG；
- JPEG；
- Photos；
- Share Sheet。

---

# 十五、导入已有截图

使用 PhotosPicker。

支持：

```text
2
5
10
30
```

张截图。

流程：

```text
Select
→ Order
→ Analyze
→ Stitch
→ Editor
→ Export
```

导入模式必须与实时 Capture 共用同一个：

```text
StitchEngine
```

禁止复制第二套拼接实现。

---

# 十六、测试要求

算法不能只靠人工点 App。

必须建立：

```text
Tests/Fixtures
```

测试至少包括：

- identical frames；
- small vertical displacement；
- normal scrolling；
- fast scrolling；
- rollback；
- fixed header；
- fixed footer；
- image feed；
- long text；
- dynamic region。

对 OverlapDetector：

验证：

```text
expected offset ± tolerance
confidence
failure case
```

对 StitchEngine：

验证：

```text
segment count
final height
frame order
overlap
warnings
```

---

# 十七、性能要求

定期使用 Instruments 或等价工具检查：

- Memory；
- CPU；
- file I/O；
- thermal；
- leaks；
- hangs。

特别注意：

```text
CMSampleBuffer
CVPixelBuffer
CIContext
CGImage
UIImage
Task
DispatchQueue
```

生命周期。

不要：

- 无界 Task；
- 无界 frame queue；
- 主线程编码 PNG；
- 主线程 overlap matching；
- 主线程长图 export。

---

# 十八、第三方依赖

原则：

```text
zero dependency preferred
```

如果系统框架可以完成，不引入第三方包。

引入任何 dependency 前必须说明：

- 为什么系统 API 不够；
- package 活跃度；
- license；
- binary size；
- maintenance risk。

不要为了几个 helper 引入巨型库。

---

# 十九、隐私

默认：

```text
LOCAL ONLY
```

禁止：

- 上传用户屏幕截图；
- analytics 收集截图内容；
- logging OCR / UI 文本；
- 把截图打进 crash log；
- 把 Capture frame 提交 Git。

README 写清：

> Screen captures are processed locally on the device.

---

# 二十、Git 工作规范

开始每个 Phase：

```bash
git status
git log --oneline -10
```

结束：

```bash
git diff
```

先做代码自审。

确认：

- 没有 debug junk；
- 没有临时截图；
- 没有 secrets；
- 没有 DerivedData；
- tests pass；
- build pass。

然后 commit。

每个 Phase 一个或少量语义明确的 commit。

示例：

```text
feat: validate iOS 27 full display capture
feat: build screen capture pipeline
feat: add adaptive key frame sampling
feat: implement initial stitch engine
feat: improve stitching for fixed interface regions
feat: add long screenshot editor
perf: harden long capture and stitching pipeline
test: complete longshot regression coverage
docs: document architecture and release workflow
```

不要把所有阶段 squash 成一个毫无信息量的 commit。

---

# 二十一、每个 Phase 验收报告格式

每完成一个阶段输出：

```text
Phase:
Phase X — ...

Status:
PASS
或
CODE COMPLETE / DEVICE VERIFICATION PENDING
或
BLOCKED

Implemented:
- ...
- ...

Files:
- ...

Tests:
- ...

Build:
PASS / FAIL

Device verification:
PASS / PENDING / N/A

Known issues:
- ...

Git:
<branch>
<commit sha>
<commit message>

Next:
Phase X+1 — ...
```

然后继续下一阶段。

除非 PLAN 中的 Gate 阻止继续。

---

# 二十二、文档

必须完成：

```text
README.md

docs/
architecture.md
capture-pipeline.md
stitch-engine.md
testing.md
privacy.md
release-checklist.md
```

README 不只是开发日志。

要像一个正式 public GitHub project：

- 项目介绍；
- Features；
- Screenshots（有正式界面后再加入）；
- Architecture；
- Requirements；
- Build；
- Permissions；
- Privacy；
- Limitations；
- Roadmap；
- License。

---

# 二十三、最终 GitHub 公共仓库

整个项目达到 Definition of Done 后：

首先执行：

```bash
git status
git remote -v
git branch --show-current
git log --oneline --decorate -20
```

## 如果已有 GitHub remote

使用已有仓库。

不要新建重复 repo。

将稳定代码推送到目标稳定分支：

```text
main
```

如果仓库当前默认分支不是 main：

- 尊重现有仓库；
- 不做破坏性重命名；
- 在最终报告说明。

## 如果没有 remote

使用 `gh`。

先确认认证：

```bash
gh auth status
```

然后：

```bash
gh repo create <project-name> \
  --public \
  --source=. \
  --remote=origin \
  --push
```

必须是：

```text
PUBLIC
```

除非用户后来明确修改要求。

不要把任何密钥、证书、个人 provisioning 数据上传到 public repo。

---

# 二十四、公开前 Secrets Audit

在 public push 之前进行检查。

搜索：

```text
OPENAI_API_KEY
API_KEY
TOKEN
PASSWORD
SECRET
PRIVATE KEY
BEGIN RSA
BEGIN EC
.mobileprovision
.p12
```

检查 Git history。

如果 secrets 曾经被 commit：

**删除当前文件不够。**

需要：

- 阻止 public push；
- 清理 history 或给出明确 blocker；
- 不得将泄漏历史直接公开。

同时确认 `.gitignore`：

```text
DerivedData
xcuserdata
*.xcuserstate
build
temporary capture data
local screenshots
archives not intended for release
```

---

# 二十五、Release Build

最终版本默认：

```text
1.0.0
```

如果已有版本，则遵循项目现状。

执行：

- clean；
- build；
- tests；
- Release configuration；
- archive。

如果可以：

```bash
xcodebuild archive ...
```

具体 workspace / scheme 根据实际项目决定。

不要复制一个未经验证的固定命令。

---

# 二十六、IPA / Signing

如果本机已有有效 Apple Developer Team / provisioning：

1. 使用正规 Xcode signing；
2. archive；
3. export；
4. 生成 `.ipa`；
5. 不上传证书；
6. 不上传 private key；
7. 不上传 provisioning profile；
8. 生成 SHA256；
9. Release attach IPA。

如果本机没有合法签名：

禁止：

- fake signing；
- 禁用 Apple 安全机制；
- 伪造“已生成 IPA”；
- 上传不可用空壳 IPA。

应该：

1. 完成 Release archive 能做到的部分；
2. 保存 build / test report；
3. `RELEASE_NOTES.md` 明确说明；
4. README 写明使用自己的 Developer Team 构建；
5. GitHub Release 仍然创建；
6. Release 可以附可安全公开的构建产物；
7. 最终报告 IPA 状态为：

```text
NOT PRODUCED — SIGNING IDENTITY NOT AVAILABLE
```

---

# 二十七、GitHub Release

Release 前确保：

```text
working tree clean
tests pass
release build pass
docs complete
public repo pushed
```

创建：

```text
tag: v1.0.0
title: LongShot 1.0.0
```

生成：

```text
RELEASE_NOTES.md
```

至少包含：

```text
Highlights
Requirements
Features
Screen Capture
Stitching
Editor
Export
Privacy
Known Limitations
Build / Install
Checksums
```

然后使用：

```bash
gh release create ...
```

如果有产物：

```bash
gh release upload ...
```

必须实际检查：

```bash
gh release view v1.0.0
```

不要仅因为命令 exit 0 就结束。

---

# 二十八、最终 GitHub 状态检查

最终执行：

```bash
git status
git remote -v
git log -1 --oneline
gh repo view
gh release view v1.0.0
```

确认：

- Repo public；
- 最新 commit 已 push；
- release tag 指向正确 commit；
- assets 正确；
- README 正常；
- repository 无临时文件。

---

# 二十九、最终报告

项目全部完成后输出：

```text
========================================
LongShot Final Delivery
========================================

Platform:
iOS 27+

Repository:
https://github.com/...

Visibility:
PUBLIC

Stable branch:
main

Final commit:
<sha>

Version:
1.0.0

Tag:
v1.0.0

Release:
https://github.com/.../releases/tag/v1.0.0

Release assets:
- ...
- ...

IPA:
AVAILABLE
或
NOT PRODUCED — SIGNING IDENTITY NOT AVAILABLE

Build:
PASS

Tests:
PASS

ScreenCaptureKit Full Display:
PASS / DEVICE VERIFICATION PENDING

Background cross-app capture:
PASS / DEVICE VERIFICATION PENDING

Long screenshot:
PASS

Import screenshot stitching:
PASS

Editor:
PASS

Export:
PASS

Performance regression:
PASS

Secrets audit:
PASS

Known limitations:
- ...

Documentation:
- README.md
- docs/architecture.md
- docs/capture-pipeline.md
- docs/stitch-engine.md
- docs/testing.md
- docs/privacy.md
- docs/release-checklist.md

========================================
```

---

# 三十、开发行为要求

整个任务过程中：

- 直接工作，不只提供建议；
- 有问题先读代码和日志；
- 能测试就测试；
- 能编译就编译；
- 不凭感觉宣布成功；
- 不删除用户已有功能；
- 不做与 LongShot 无关的大规模重构；
- 不修改系统安全设置；
- 不上传秘密；
- 不上传个人数据；
- 不把 ScreenCapture 测试图片提交到 public repo；
- 不使用假实现通过验收；
- 不把 TODO 当完成；
- 不把 mock 当真机验证；
- 不因 UI 完成就宣布产品完成。

最终目标不是生成 Demo，而是得到：

> **一个可维护、可测试、具备设计完成度、能够真实执行 iOS 27 Full Display Capture → 跨 App 滚动 → 智能拼接 → 编辑 → 导出的 LongShot 1.0，并将完整代码发布到 GitHub 公共仓库，同时创建正式 GitHub Release。**
