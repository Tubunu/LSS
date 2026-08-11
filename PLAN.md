# LongShot — iOS 27+ 滚动长截图 App 开发计划

> 工作名称：LongShot  
> 平台：iPhone / iOS 27.0+  
> 技术栈：Swift、SwiftUI、ScreenCaptureKit  
> 核心目标：在用户授权后捕获整个 iPhone 屏幕，用户切换到其他 App 持续滚动，LongShot 在后台接收屏幕帧、抽取关键帧并自动拼接成高质量长截图。  
> 开发原则：先验证系统能力，再做拼接算法，再做完整产品；每个阶段独立验收、测试、提交 Git，上一阶段通过后再进入下一阶段。

## 执行状态（2026-08-11）

- 当前阶段：Phase 0 — iOS 27 ScreenCaptureKit 技术验证（PASS）。
- 开发环境：`/Users/tao/Downloads/Xcode-beta.app`，Xcode 27.0，iPhoneOS 27.0 SDK。
- 真机：`TaoiPhone`，iPhone 16 Pro，iOS 27.0，已连接且开启开发者模式。
- SDK 差异：iOS 上 `SCContentSharingPickerMode` 不可用，Full Display 使用 `presentPicker(using: .display)`；`minimumFrameInterval` / `pixelFormat` / `queueDepth` 为 macOS 专属配置。
- Gate 结果：真机 Full Display 选择 PASS；跨 App 后台 59.47 秒 PASS；后台新增 751 帧；2932/2932 有效帧；8 张诊断帧落盘；诊断帧确认来自系统 Picker 和其他 App；正常 stop 回到 idle PASS。

---

## 0. 产品目标

LongShot 是一款强调设计感、原生体验和高质量拼接效果的 iOS 长截图工具。

核心体验：

1. 用户打开 LongShot。
2. 点击「开始滚动截图」。
3. 调起 iOS 27 系统屏幕内容共享选择器。
4. 用户授权捕获整个屏幕。
5. 用户切换到 Safari、微信、小红书、设置或其他允许被系统捕获的 App。
6. 用户正常、缓慢地向下滚动。
7. LongShot 在后台持续接收 ScreenCaptureKit 输出的屏幕帧。
8. 系统自动：
   - 过滤静止帧；
   - 过滤重复帧；
   - 判断滚动方向；
   - 计算相邻帧位移；
   - 检测重叠区域；
   - 检测固定 Header / Footer / TabBar；
   - 删除重复内容；
   - 选择最佳接缝；
   - 生成长截图。
9. 用户返回 LongShot。
10. 查看生成结果并进行裁剪、接缝修正、删除错误片段。
11. 保存到照片或通过 Share Sheet 分享。

辅助模式：

- 从 PhotosPicker 导入多张已有截图；
- 自动排序、检测重叠并生成长图；
- 与实时滚动捕获共用同一套 StitchEngine。

---

# 1. 平台与硬性约束

## 1.1 最低系统

- Minimum Deployment Target：iOS 27.0
- 仅支持 iPhone。
- V1 以竖屏内容为第一优先级。
- 暂不为 iOS 26 及以下提供兼容方案。
- 不使用 ReplayKit Broadcast Upload Extension 作为主架构。
- 使用 iOS 27 ScreenCaptureKit。

## 1.2 ScreenCaptureKit

主要使用：

- `SCContentSharingPicker`
- `SCStream`
- `SCStreamConfiguration`
- `SCContentFilter`
- `SCStreamOutput`
- `CMSampleBuffer`

必须使用 Apple 提供的系统内容共享 Picker，不自行伪造或替代系统授权选择 UI。

项目需要配置：

- Screen Capture 权限说明；
- `NSScreenCaptureUsageDescription`；
- iOS 对应的 `screen-capture` Background Mode；
- 真机验证应用进入后台后 Full Display Capture 流仍然工作。

> 注意：iOS 27 API 在项目开发时可能仍处于 Beta / 新 SDK 阶段。Codex 不得仅根据旧知识猜 API。实现时应以项目当前 Xcode / iOS 27 SDK 的实际编译结果和 Apple 官方文档为准。

## 1.3 隐私原则

- 默认只在设备本地处理截图。
- 不上传屏幕内容。
- 不需要账户。
- 不需要云同步。
- 不进行后台网络传输。
- 临时帧在生成完成、取消任务或超过清理期限后自动删除。
- UI 中明确说明「屏幕内容仅在本机处理」。

---

# 2. V1 功能范围

## 2.1 核心功能

必须包含：

- 滚动长截图。
- Full Display Capture。
- 后台持续接收屏幕帧。
- 自动关键帧抽取。
- 自动重复帧过滤。
- 自动滚动方向判断。
- 自动纵向位移估计。
- 自动重叠区域识别。
- 自动固定区域检测。
- 自动接缝选择。
- 自动拼接。
- 超长图片分块 / Tile Rendering。
- 长图预览。
- 顶部 / 底部裁剪。
- 左右裁剪。
- 删除错误拼接片段。
- 手动调整接缝。
- 重新拼接。
- PNG 导出。
- JPEG 导出。
- 保存 Photos。
- Share Sheet。
- 最近项目 / 历史记录。
- 临时文件清理。
- 深色模式。
- 浅色模式。
- iOS 27 原生设计语言。
- 完整错误处理和恢复。

## 2.2 辅助功能

必须包含：

### 导入截图拼接

通过 PhotosPicker：

1. 多选截图；
2. 显示顺序；
3. 自动排序；
4. 允许手动重新排序；
5. 自动检测重叠；
6. 自动拼接；
7. 与实时 Capture 使用相同 StitchEngine；
8. 进入相同编辑和导出流程。

## 2.3 V1 暂不开发

以下功能暂不进入 V1：

- OCR。
- AI 内容理解。
- AI 自动总结。
- 马赛克 / 智能隐私识别。
- 箭头 / 文字 / 涂鸦标注。
- 水印。
- 网页 URL 自动生成整页截图。
- 浏览器扩展。
- PDF 编辑器。
- iPad 专项 UI。
- Mac 版本。
- iCloud 同步。
- 登录 / 注册。
- 订阅 / 支付。

架构可预留扩展点，但不得为了这些未来功能过度设计。

---

# 3. UX / UI 原则

## 3.1 设计目标

关键词：

- 原生
- 克制
- 内容优先
- 极少操作
- 有设计感
- 清晰的状态反馈
- 优秀动画
- 轻量触觉反馈
- 不像传统工具箱 App

优先使用：

- SwiftUI 原生组件；
- NavigationStack；
- Toolbar；
- Sheet；
- Context Menu；
- ShareLink / 系统 Share Sheet；
- PhotosPicker；
- iOS 27 系统材质和控件表现。

避免：

- 大量自定义伪玻璃背景；
- 过度渐变；
- 满屏按钮；
- 密集设置项；
- Android 风格悬浮球；
- 在其他 App 上绘制自定义悬浮控制器；
- 为“酷炫”牺牲可读性。

## 3.2 首页结构

建议：

```text
LongShot

把滚动页面
变成一张完整截图。

┌────────────────────────┐
│                        │
│      开始滚动截图       │
│                        │
└────────────────────────┘

        导入截图拼接


最近项目

┌─────┐  ┌─────┐  ┌─────┐
│     │  │     │  │     │
└─────┘  └─────┘  └─────┘
```

主 CTA 只有一个：

> 开始滚动截图

导入已有截图作为次级入口。

## 3.3 捕获前引导

第一次使用：

```text
开始屏幕捕获后：

1. 选择整个屏幕
2. 切换到需要截图的 App
3. 缓慢向下滚动
4. 完成后停止屏幕捕获
5. 返回 LongShot 自动生成长截图
```

需要说明：

- 不必匀速滚动；
- 可以短暂停顿；
- 尽量避免快速来回滚动；
- 视频、动态广告和大量动画可能影响拼接；
- 内容只在本机处理。

以后默认不强制再次展示，可从帮助中查看。

---

# 4. 建议代码架构

```text
LongShot/
├── App/
│   ├── LongShotApp.swift
│   ├── AppRouter.swift
│   └── AppEnvironment.swift
│
├── Features/
│   ├── Home/
│   ├── Capture/
│   ├── Import/
│   ├── Processing/
│   ├── Editor/
│   ├── History/
│   └── Settings/
│
├── Core/
│   ├── Capture/
│   │   ├── ScreenCaptureManager.swift
│   │   ├── ScreenCaptureSession.swift
│   │   ├── StreamOutputHandler.swift
│   │   └── FrameSampler.swift
│   │
│   ├── Stitch/
│   │   ├── StitchEngine.swift
│   │   ├── FrameAnalyzer.swift
│   │   ├── MotionDetector.swift
│   │   ├── OverlapDetector.swift
│   │   ├── FixedRegionDetector.swift
│   │   ├── SeamOptimizer.swift
│   │   ├── StitchPlan.swift
│   │   └── StitchRenderer.swift
│   │
│   ├── Imaging/
│   │   ├── ImageBuffer.swift
│   │   ├── ImageHasher.swift
│   │   ├── TileRenderer.swift
│   │   └── ImageExporter.swift
│   │
│   ├── Storage/
│   │   ├── ProjectStore.swift
│   │   ├── TemporaryFrameStore.swift
│   │   └── CleanupService.swift
│   │
│   └── Diagnostics/
│       ├── CaptureDiagnostics.swift
│       └── StitchDiagnostics.swift
│
├── Models/
│   ├── CaptureProject.swift
│   ├── CapturedFrame.swift
│   ├── StitchSegment.swift
│   └── ExportOptions.swift
│
├── Shared/
│   ├── Components/
│   ├── Extensions/
│   ├── Utilities/
│   └── DesignSystem/
│
└── Tests/
    ├── StitchEngineTests/
    ├── CaptureTests/
    └── Fixtures/
```

不要机械照抄目录。

Codex 可以根据工程规模调整，但必须保证：

- ScreenCaptureKit 与 UI 解耦；
- StitchEngine 与 Capture 解耦；
- 导入截图和实时捕获共用 StitchEngine；
- 算法模块可单元测试；
- 数据层可替换；
- Editor 不直接依赖 ScreenCaptureKit。

---

# 5. 图像处理原则

## 5.1 不保存所有视频帧

禁止：

```text
60 FPS
→ 每帧转 PNG/JPEG
→ 全部写磁盘
→ 最后再处理
```

目标：

```text
SCStream
   ↓
FrameSampler
   ↓
低成本变化检测
   ↓
Motion Detection
   ↓
Key Frame Selection
   ↓
只持久化有意义的关键帧
```

## 5.2 关键帧策略

第一版建议：

- 限制进入分析管线的采样频率；
- 对相邻帧计算低分辨率图像特征；
- 静止页面不持续保存；
- 极小位移不保存；
- 完全重复帧不保存；
- 滚动速度过快时保留足够中间帧避免断层；
- 记录时间戳和帧尺寸；
- 保留原始像素帧用于最终 Stitch，缩略图仅用于快速分析。

所有阈值集中到可配置结构，不散落 magic numbers。

## 5.3 Overlap Detection

优先实现纵向滚动场景。

输入：

```text
Frame A
Frame B
```

输出至少包含：

```text
verticalOffset
overlapRectA
overlapRectB
confidence
matchingError
```

可以使用：

- Core Image；
- Accelerate / vImage；
- Metal；
- 自研低分辨率 NCC / SAD / MSE；
- 特征匹配；

但 V1 优先选择：

> 足够稳定 + 可测试 + 性能可控 + 依赖简单

而不是为了算法复杂度使用重型 Vision / ML。

## 5.4 固定 Header / Footer

必须考虑：

- iOS Status Bar；
- Navigation Bar；
- 搜索栏；
- App 顶部固定 Header；
- 底部 Tab Bar；
- 输入框；
- 固定悬浮按钮。

算法目标：

- 识别连续多帧中位置不变的区域；
- 不让固定区域在长图中重复出现；
- 顶部固定区域原则上只保留一次；
- 底部固定区域根据内容类型决定保留最后一次或移除；
- 用户可在编辑器中修正。

## 5.5 回滚

V1 要容忍：

- 停顿；
- 小幅向上回滚；
- 再继续向下滚动。

不要求支持：

- 大范围反复上下浏览；
- 横向滚动和纵向滚动同时大量出现；
- 页面发生大量实时重排。

出现无法可靠拼接时：

- 不崩溃；
- 标记低置信度接缝；
- 在编辑器提示用户修正；
- 保留原始关键帧。

---

# 6. 超长图片与内存

不能假设整张长图始终可以一次性加载进内存。

必须：

- 采用 Tile / 分段渲染；
- 尽量使用 autoreleasepool；
- 及时释放临时 CGImage / CIImage / CVPixelBuffer；
- 不长期持有全部 full-resolution UIImage；
- 长图预览优先生成缩略代理图；
- 最终导出时再流式 / 分块渲染高分辨率结果。

重点测试：

- 10 屏；
- 30 屏；
- 50 屏；
- 100 屏级别的长内容。

不需要为了极端百万像素高度做没有意义的过度优化，但不得轻易 OOM。

---

# 7. 数据模型建议

## CaptureProject

包含：

- id
- createdAt
- updatedAt
- sourceType
  - liveCapture
  - importedScreenshots
- state
- frameCount
- segmentCount
- outputWidth
- outputHeight
- thumbnailURL
- temporaryDirectory
- finalImageURL
- errors / warnings

## CapturedFrame

包含：

- id
- timestamp
- index
- width
- height
- fileURL
- perceptualHash / lightweight signature
- motion metadata
- selectedAsKeyFrame

## StitchSegment

包含：

- sourceFrameID
- sourceRect
- destinationY
- overlapHeight
- confidence
- seamY
- userAdjusted

---

# 8. 开发阶段

---

# Phase 0 — iOS 27 ScreenCaptureKit 技术验证

## 目标

首先证明最重要的系统链路成立。

这个阶段不要开发正式 App UI。

## 必须完成

创建最小 PoC：

1. SwiftUI App，iOS 27.0+。
2. 配置 ScreenCaptureKit。
3. 配置 `NSScreenCaptureUsageDescription`。
4. 配置 `screen-capture` Background Mode。
5. 使用 `SCContentSharingPicker.shared`。
6. 启动 Full Display Capture。
7. 创建 `SCStream`。
8. 接收视频 `CMSampleBuffer`。
9. 在屏幕上显示：
   - capture state；
   - total received frames；
   - current frame size；
   - last frame timestamp；
   - dropped/invalid frame count。
10. 用户切出 LongShot。
11. 打开另一个 App。
12. 滚动至少 30 秒。
13. 回到 LongShot。
14. 能确认后台期间持续获得有效帧。
15. 正常停止 Stream。
16. 错误和权限拒绝均可恢复。

## 真机验收

必须在 iOS 27 真机验证：

```text
启动 LongShot
→ 开始 Full Display Capture
→ 切到 Safari / Settings
→ 连续滚动
→ 保持至少 30 秒
→ 回 LongShot
→ frame counter 明显增长
→ 保存若干测试帧
→ 测试帧内容确实来自其他 App
→ 正常结束 capture
```

## Gate

**Phase 0 未通过，不允许进入正式功能开发。**

如果 API 与 Apple 文档或预期不一致：

1. 记录问题；
2. 根据当前 SDK 调整；
3. 更新 PLAN 中相关 API 说明；
4. 重新验证；
5. 不得通过 mock 假装 Phase 0 已成功。

## Git

完成并通过：

```text
git add .
git commit -m "feat: validate iOS 27 full display capture"
```

---

# Phase 1 — 项目骨架与 Capture Pipeline

## 目标

将 PoC 重构为可维护产品代码。

## 开发

实现：

- App Navigation；
- Home；
- ScreenCaptureManager；
- CaptureSession；
- StreamOutputHandler；
- FrameSampler；
- Capture State Machine；
- TemporaryFrameStore；
- 基础 Diagnostics。

建议状态：

```text
idle
requestingPermission
selectingContent
starting
capturing
stopping
processing
completed
failed
```

## Capture 页面

需要：

- 捕获状态；
- 操作说明；
- 开始按钮；
- 停止按钮；
- 捕获时长；
- 已选择关键帧数量；
- 简洁视觉反馈。

不要在 Capture 阶段实时显示重型全尺寸预览。

## 验收

- 状态切换正确；
- App background / foreground 不打乱 session；
- 重复开始不会创建多个 SCStream；
- stop 可重复调用且安全；
- 权限取消可恢复；
- Stream error 可恢复；
- 临时目录创建和清理正常；
- 连续运行 3 分钟无明显内存持续增长。

## Git

```text
git commit -m "feat: build screen capture pipeline"
```

---

# Phase 2 — FrameSampler 与关键帧筛选

## 目标

从持续屏幕流中保存少量、高质量、有拼接价值的关键帧。

## 实现

包括：

- sampling interval；
- lightweight thumbnail；
- duplicate detection；
- perceptual hash / signature；
- motion estimate；
- minimum displacement threshold；
- maximum gap protection；
- key-frame scoring；
- frame metadata。

## 要求

同一静止页面停留 10 秒：

- 不能保存几十 / 几百张相同图。

正常滚动：

- 关键帧之间必须存在足够 overlap。

快速滚动：

- 尽量增加采样密度避免内容断层。

## Tests

建立 fixture：

- 完全相同帧；
- 轻微滚动；
- 正常滚动；
- 快速滚动；
- 小幅回滚；
- 动画区域。

## Git

```text
git commit -m "feat: add adaptive key frame sampling"
```

---

# Phase 3 — StitchEngine MVP

## 目标

首先让导入截图和关键帧可以可靠拼成长图。

## 实现

- FrameAnalyzer；
- OverlapDetector；
- vertical offset estimation；
- overlap confidence；
- stitch plan；
- basic seam selection；
- renderer。

## 第一阶段算法目标

优先解决：

```text
纯纵向滚动
+ 大部分内容静态
+ 相邻帧有明显重叠
```

必须避免：

- 固定写死 overlap 高度；
- 单纯按 50% 图片高度拼接；
- 遇到失败直接强行拼接。

低 confidence：

- 输出 warning；
- 保存调试信息；
- 编辑器后续可修正。

## 测试数据

建立 Fixtures：

```text
Tests/Fixtures/
├── simple_article/
├── settings_list/
├── chat_style/
├── image_feed/
└── edge_cases/
```

Fixture 需要预期：

- frame order；
- expected offsets；
- expected final approximate height。

## Git

```text
git commit -m "feat: implement initial stitch engine"
```

---

# Phase 4 — FixedRegionDetector 与高级拼接

## 目标

提升真实 App 场景拼接质量。

## 重点

检测：

- Status Bar；
- 固定导航栏；
- 固定搜索栏；
- 固定 TabBar；
- 底部输入框；
- 悬浮元素。

## 实现

- multi-frame stable region analysis；
- candidate fixed region；
- confidence；
- exclusion masks；
- seam optimization；
- minor rollback recovery。

## 拼接策略

尽量选择：

- 视觉变化较少；
- 无明显文字切割；
- 无头像 / 图片边缘切割；
- 无动态内容的 seam。

## 失败策略

不可可靠自动处理：

- 不损坏原始帧；
- 标记接缝；
- 用户可手动选择。

## Git

```text
git commit -m "feat: improve stitching for fixed interface regions"
```

---

# Phase 5 — Processing UX

## 目标

捕获完成后提供明确、高质量处理体验。

流程：

```text
Capture stopped
      ↓
Analyzing frames
      ↓
Matching overlaps
      ↓
Building stitch plan
      ↓
Rendering preview
      ↓
Editor
```

UI 只显示用户能理解的状态，例如：

- 正在整理截图…
- 正在匹配滚动内容…
- 正在生成长截图…

不要把内部算法术语直接扔给用户。

处理任务：

- 可取消；
- App 进入后台后状态保持一致；
- 出错可重试；
- 不阻塞主线程；
- 有合理 progress。

## Git

```text
git commit -m "feat: add stitching processing experience"
```

---

# Phase 6 — 长截图编辑器

## 目标

让用户可以快速修复自动拼接无法完全解决的情况。

## V1 工具

### Crop

- 顶部；
- 底部；
- 左侧；
- 右侧。

### Segment Manager

- 查看拼接段；
- 删除错误 segment；
- 恢复删除；
- reorder 仅在明确需要时提供。

### Seam Adjustment

用户点某个接缝：

```text
上一个 segment
----------------
接缝控制
----------------
下一个 segment
```

可以：

- 上下微调；
- 选择其他匹配候选；
- 恢复自动值。

### Rebuild

调整后：

- 重新生成预览；
- 不重复运行不必要的全量分析。

## UI

编辑器以长图为主角。

工具栏：

```text
裁剪    接缝    片段    导出
```

不要做成复杂修图软件。

## Git

```text
git commit -m "feat: add long screenshot editor"
```

---

# Phase 7 — 导入截图拼接

## 目标

支持普通截图拼接，同时作为 StitchEngine 的稳定测试入口。

## 功能

- PhotosPicker 多选；
- 自动按选择顺序导入；
- 分析相邻图片；
- 自动重排仅在 confidence 足够高时执行；
- 手动拖动调整顺序；
- 自动拼接；
- 编辑；
- 导出。

## 验收

测试：

- 2 张；
- 5 张；
- 10 张；
- 30 张截图。

## Git

```text
git commit -m "feat: support imported screenshot stitching"
```

---

# Phase 8 — History / Storage / Cleanup

## 功能

首页最近项目。

每个 Project：

- thumbnail；
- 时间；
- 尺寸；
- source type；
- 打开；
- 删除；
- 分享。

## Storage

原则：

- 临时帧与最终输出分离；
- project deletion 同时清理关联文件；
- app launch 执行轻量 orphan cleanup；
- 对过旧失败 session 清理；
- 不误删用户已保存 Photos 的图片。

## Git

```text
git commit -m "feat: add capture history and storage lifecycle"
```

---

# Phase 9 — Export

## 支持

- PNG；
- JPEG；
- JPEG quality；
- 保存 Photos；
- Share Sheet。

## 大尺寸输出

必须验证：

- 超高图片的 CoreGraphics 输出限制；
- Photos 保存限制；
- JPEG / PNG 编码内存；
- 无法生成单张图片时必须给用户明确错误，不可崩溃。

可根据真实系统限制考虑后续增加：

- 分段图片；
- PDF。

但 V1 不强制。

## Git

```text
git commit -m "feat: add long screenshot export"
```

---

# Phase 10 — UI / Interaction Polish

## 目标

在功能完整基础上系统打磨设计。

## 重点

- iOS 27 原生视觉；
- 页面层级；
- Typography；
- spacing；
- toolbar；
- sheet；
- empty state；
- loading；
- success；
- error；
- haptics；
- matched transitions；
- accessibility；
- Dynamic Type；
- Reduce Motion；
- VoiceOver label；
- Light / Dark。

## 禁止

- 大量无意义动画；
- 极端 blur；
- 自定义玻璃层堆叠；
- 为设计感牺牲可点击区域；
- 字号过小；
- 对比度不足。

## Git

```text
git commit -m "feat: polish iOS 27 interface and interactions"
```

---

# Phase 11 — 性能与稳定性

## 真机测试

至少验证：

### Capture

- 30 秒；
- 1 分钟；
- 3 分钟；
- 5 分钟。

### Content

- Safari 长文章；
- Settings 列表；
- 图片 Feed；
- 聊天式页面；
- 包含固定 Header；
- 包含固定 Footer；
- 包含动画；
- 小幅回滚。

### Stitch

- 10 屏；
- 30 屏；
- 50 屏；
- 更长场景。

## 关注

- Memory；
- CPU；
- Thermal；
- 临时文件大小；
- Capture frame queue；
- dropped frames；
- Stitch time；
- export time。

## 要求

- 不阻塞 MainActor；
- 不发生明显 memory leak；
- 不由于超长页面直接 OOM；
- Capture Stream 正确释放；
- CVPixelBuffer 生命周期正确；
- cancel 不留下大量垃圾文件。

## Git

```text
git commit -m "perf: harden long capture and stitching pipeline"
```

---

# Phase 12 — 自动化测试与最终回归

## Unit Tests

至少覆盖：

- duplicate detection；
- motion detection；
- overlap estimation；
- fixed region detection；
- stitch plan；
- crop math；
- segment delete / restore；
- project lifecycle。

## UI Tests

至少覆盖：

- 首页；
- 导入截图；
- 编辑；
- 导出；
- 历史项目。

系统 ScreenCapture Picker 如果不适合自动 UI 测试：

- 将 picker integration 与 capture state machine 分离；
- 对 state machine 使用 mock；
- 真机系统 Picker 使用手动验收 checklist。

## 构建

必须确认：

```bash
xcodebuild ...
```

可以在 CI / command line 下完成至少 Debug 编译和测试。

禁止只依赖 Xcode GUI 显示“看起来没报错”。

## Git

```text
git commit -m "test: complete longshot regression coverage"
```

---

# Phase 13 — 文档

生成：

```text
README.md
docs/
├── architecture.md
├── capture-pipeline.md
├── stitch-engine.md
├── testing.md
├── privacy.md
└── release-checklist.md
```

## README 至少包含

- App 简介；
- iOS 27+；
- 主要功能；
- 架构图；
- ScreenCaptureKit 说明；
- 构建要求；
- 如何运行；
- 权限说明；
- 隐私说明；
- 已知限制；
- 测试；
- License。

## 已知限制必须诚实说明

例如：

- 动态视频；
- 自动刷新广告；
- 大幅上下回滚；
- 特殊受保护内容；
- DRM / 系统禁止捕获内容；
- 极长图片的系统资源限制。

## Git

```text
git commit -m "docs: document architecture and release workflow"
```

---

# Phase 14 — GitHub 公共仓库与 Release

## 目标

开发完成后，代码必须更新到 GitHub 公共仓库，并创建正式 Release。

## 14.1 Repository

先检查：

```bash
git status
git branch --show-current
git remote -v
```

### 已存在 remote

如果已有正确 GitHub 仓库：

- 不创建新仓库；
- 检查默认分支；
- 推送所有提交；
- 确保目标分支为最终稳定分支。

### 没有 remote

如果当前目录尚未关联 GitHub 仓库：

1. 使用 GitHub CLI；
2. 仓库名优先使用当前工程名；
3. 创建 public repository；
4. 设置 `origin`；
5. 推送代码。

例如：

```bash
gh repo create <repo-name> --public --source=. --remote=origin --push
```

不要覆盖用户已有仓库。

## 14.2 Release 前检查

必须：

```bash
git status
git log --oneline --decorate -20
git remote -v
```

要求：

- working tree clean；
- 无密钥；
- 无 provisioning profile；
- 无私有证书；
- 无 DerivedData；
- 无用户个人路径；
- 无大型临时截图；
- 无 Capture 临时数据；
- `.gitignore` 正确。

进行 secrets scan：

- API Key；
- Token；
- Password；
- Signing secret；
- Developer certificate；
- private key。

发现敏感信息必须先处理，禁止直接公开仓库。

## 14.3 Release Build

执行 Release configuration 构建。

如果当前机器拥有有效 Apple Developer 签名：

1. Archive；
2. Export；
3. 根据现有 provisioning 能力导出 Development / Ad Hoc 可用的 `.ipa`；
4. 生成 checksum；
5. 将 IPA 作为 GitHub Release asset。

如果当前环境没有合法签名配置：

- 不得伪造 `.ipa`；
- 不修改或绕过 Apple signing；
- 至少生成可复现的 Release archive / build report；
- 可以打包 `.xcarchive`（如构建条件允许）或适当的构建产物；
- Release Notes 明确写明未附带可安装 IPA 的原因；
- README 写明用户如何使用自己的 Developer Team 在 Xcode 中构建。

## 14.4 Version

首个完整版本默认：

```text
1.0.0
```

Git tag：

```text
v1.0.0
```

除非项目已经存在版本体系，则遵循现有版本。

## 14.5 GitHub Release

Release Title：

```text
LongShot 1.0.0
```

Release Notes 至少包含：

- Highlights；
- Requirements；
- Core Features；
- Capture workflow；
- Stitch capabilities；
- Known limitations；
- Build / install notes；
- Privacy；
- Checksums。

创建 release：

```bash
gh release create v1.0.0 \
  --title "LongShot 1.0.0" \
  --notes-file RELEASE_NOTES.md
```

如果存在构建产物：

```bash
gh release upload v1.0.0 <artifact>
```

## 14.6 最终验收

Codex 最终必须输出：

```text
Repository:
https://github.com/...

Branch:
main

Final commit:
<sha>

Release:
https://github.com/.../releases/tag/v1.0.0

Release assets:
...

Build:
PASS / FAIL

Tests:
PASS / FAIL

Real-device ScreenCaptureKit verification:
PASS / FAIL

Known limitations:
...
```

任何 FAIL 都必须明确，不允许用模糊描述伪装完成。

---

# 9. 每个 Phase 的统一执行规范

每个阶段都执行：

```text
1. 阅读 PLAN.md 当前阶段
2. 检查当前代码和 Git 状态
3. 只实现当前 Phase
4. 编译
5. 执行相关 tests
6. 静态检查
7. 真机验证（如该 Phase 要求）
8. 修复问题
9. 再次完整验证
10. 更新必要文档
11. git diff 自审
12. commit
13. 输出 Phase 验收报告
14. 通过后进入下一阶段
```

---

# 10. Codex 自审要求

每次提交前检查：

- 是否存在主线程重计算；
- 是否错误 retain CMSampleBuffer / CVPixelBuffer；
- 是否有无界数组保存 frame；
- 是否在 UI 中直接做图像处理；
- 是否有 force unwrap；
- 是否有吞错误；
- 是否有无法取消的 Task；
- 是否存在 race；
- 是否使用 MainActor 正确；
- 是否泄漏临时文件；
- 是否有 hard-coded device size；
- 是否正确处理 scale；
- 是否正确处理 orientation；
- 是否引入无必要第三方依赖；
- 是否有重复代码；
- 是否破坏现有测试；
- 是否把 debug code 带入正式 UI。

---

# 11. 验收优先级

优先级严格按以下顺序：

```text
P0  ScreenCaptureKit 真机跨 App 捕获成立
P0  不崩溃 / 不 OOM
P0  能生成正确基础长截图

P1  拼接准确率
P1  固定栏去重
P1  编辑修复能力
P1  Capture / Processing 状态可靠

P2  UI 设计
P2  动画
P2  History
P2  细节 polish
```

不要反过来先做漂亮 UI。

---

# 12. 完成定义 Definition of Done

只有满足以下全部条件才算项目完成：

- [ ] iOS 27+ 工程可编译；
- [ ] iPhone 真机 ScreenCaptureKit Full Display Capture 已验证；
- [ ] 切换到其他 App 后后台仍收到帧；
- [ ] 可完成一次真实滚动长截图；
- [ ] 自动关键帧过滤有效；
- [ ] 自动 overlap detection 有测试；
- [ ] 固定区域重复问题有处理；
- [ ] StitchEngine 有单元测试；
- [ ] 可以导入现有截图拼接；
- [ ] 有 Crop；
- [ ] 有 Seam Adjustment；
- [ ] 有 Segment 删除；
- [ ] 有 PNG / JPEG 导出；
- [ ] 可保存 Photos；
- [ ] 可 Share；
- [ ] 有 History；
- [ ] 临时文件可清理；
- [ ] Light / Dark 正常；
- [ ] 基础 Accessibility 正常；
- [ ] 性能测试完成；
- [ ] README 完成；
- [ ] docs 完成；
- [ ] working tree clean；
- [ ] secrets scan 完成；
- [ ] 代码已推送 GitHub public repository；
- [ ] `main` 为最新稳定代码；
- [ ] 创建正式 Git tag；
- [ ] 创建 GitHub Release；
- [ ] Release Notes 完成；
- [ ] 有签名条件时已附 `.ipa`；
- [ ] 无签名条件时已明确说明并提供可复现构建说明；
- [ ] 最终验收报告包含 repo / commit / release 链接。

---

# 13. Apple 官方参考

开发时优先查阅当前 SDK 与 Apple 官方文档：

- ScreenCaptureKit  
  https://developer.apple.com/documentation/screencapturekit
- Capturing screen content on iOS  
  https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- SCContentSharingPicker  
  https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker
- SCStream  
  https://developer.apple.com/documentation/screencapturekit/scstream
- SCStreamConfiguration  
  https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration

当前开发目标是 iOS 27+，不要为了兼容旧版本重新引入 ReplayKit 主方案。
