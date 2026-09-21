# 修复过渡帧污染与拼接引擎低置信度阻塞设计方案（FIX-STITCH-TRANSITION-FRAMES）

## 1. 缺陷背景与根因分析

### 1.1 现象
用户在 iOS 真机上录屏跨 App 滚动截屏成功（灵动岛录制标志全程正常），但返回 LongShot 点击生成长截图时，处理进度中途失败，界面报错：
`处理失败：渲染拼接长图失败：部分截图无法可靠匹配，请检查问题接缝`

### 1.2 根因
1. **录制过渡帧污染（Sampling Polluted）**：
   `FrameSampler` 在 `ScreenCaptureSession` 启动时即全开采集。用户在 LongShot 中确认后到切出 App 之间产生了 LongShot 本身界面帧或桌面图标帧；切回停止时产生任务切换器帧。
2. **算法缺乏对孤立过渡帧的容忍（Rigid Stitching Loop）**：
   在 `StitchEngine.makePlan` 中，序列必须严格按 $0 \to 1 \to 2 \dots$ 进行匹配。若第 0 帧是 LongShot 界面，第 1 帧是桌面，第 2 帧是微信正文，则 $0 \to 1$ 与 $1 \to 2$ 之间重叠度为 0，匹配置信度极低。
3. **一票否决阻塞机制（Fatal Blocking on Single Warning）**：
   `StitchWarningKind.lowConfidence` 的 `isBlocking` 属性直接返回 `true`，导致只要序列中有 1 处低置信度，`plan.isRenderable` 即为 `false`，`TileRenderer` 直接抛出致命异常，导致用户整段几万像素的有效截图完全报废。

---

## 2. 详细技术方案

### 2.1 源头采样门控（`StreamOutputHandler.swift` & `ScreenCaptureSession.swift`）
在 `StreamOutputHandler` 中增加 `isSamplingActive: Bool`（默认 `false`）：
```swift
var isSamplingActive: Bool = false

func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    ...
    // 仅当采样处于激活状态时才送入采样器考虑落盘
    if isSamplingActive {
        if sampler.consider(pixelBuffer: pixelBuffer, timestamp: timestamp) {
            diagnostics.recordSelectedFrame()
        }
    }
    ...
}
```
在 `ScreenCaptureManager.swift` 中：
- `appDidEnterBackground()` 时设置 `session?.setSamplingActive(true)`；
- `appDidBecomeActive()` 与 `stopCapture()` 时设置 `session?.setSamplingActive(false)`；
- 彻底从源头剔除 LongShot 界面与返回应用切换器的多余帧。

### 2.2 拼接引擎鲁棒性重构（`StitchEngine.swift`）
在 `StitchEngine.makePlan` 中引入：
1. **前导帧智能寻优（Find Best Starting Frame）**：
   若第 0 帧与第 1 帧置信度小于 0.60，但第 1 帧与第 2 帧置信度 $\ge 0.60$，说明第 0 帧为无关前导帧，将第 0 帧记入 `skippedFrameIndices`，以第 1 帧作为有效序列起点（最多向前试探至 `min(3, frames.count - 2)`）。
2. **前瞻单帧跳跃（Lookahead 1 Skip）**：
   在遍历过程中，当 `upper` 与 `frames[i]` 匹配度小于 0.60 且非回滚时，尝试向前探测 `frames[i + 1]`（若存在）。若 `upper` 与 `frames[i + 1]` 匹配度 $\ge 0.60$，则将 `frames[i]` 记入 `skippedFrameIndices`，直接连接至 `frames[i + 1]`！
3. **尾部孤立帧自动剔除**：
   若最后一帧与前一有效帧无法匹配且无后续帧，自动将其忽略并记入 `skippedFrameIndices`。
4. **有效段判定（`isRenderable`）**：
   只要拼接计划中有有效连接段（且至少包含一个高置信度段），即视为可渲染。若某中间段因页面纯白/单色导致置信度偏低，保留其最佳候选位移平滑拼接，不抛出致命异常。

### 2.3 容错渲染（`TileRenderer.swift` & `ProcessingCoordinator.swift`）
- `TileRenderer` 在满足 `isRenderable` 条件下顺畅完成图块拼装；
- 若存在弱置信度警告，`ProcessingCoordinator` 在生成长图后将提示设为温和横幅，绝不阻断用户查看、保存相册或复制到剪贴板。
