# Phase 4 验收记录

## 状态

**PASS**

## 实现范围

- `FixedRegionDetector` 对至少三张帧执行多帧稳定边缘块分析。
- 固定区域模型包含 top bar、bottom bar、floating 三类，以及二维位置、尺寸和置信度。
- 稳定边缘块先形成横向栏候选，再对剩余块做八邻域连通组件分析，以覆盖内部搜索栏、输入区和悬浮元素。
- 固定区域被转换成分析分辨率下的二维 exclusion mask。
- overlap error、texture confidence 和 seam search 同时排除固定区域。
- seam score 在匹配误差之外加入局部边缘惩罚，降低文字、头像和图片边缘被切开的概率。
- 小幅回滚通过反向匹配确认；可信且小于集中阈值时跳过该帧，保留非阻塞 `rollbackRecovered` warning，并继续与最后一张有效向下帧匹配。
- renderer 按原始 frame index 取图，支持 StitchPlan 跳过中间回滚帧。

## 误判保护

开发中的第一次回归把周期性正文误判成固定区域。最终策略增加以下 Gate：

- 横向固定栏至少连续两个分析 block；
- 顶部 / 底部栏必须贴近屏幕边缘；
- 单个边缘栏高度不得超过屏幕 30%；
- 只有同时检测到合理顶部与底部锚点时，才启用内部 / 悬浮候选与 exclusion mask；
- 缺少可靠锚点时回退到 Phase 3 原始匹配，不激进排除内容。

## 真机测试

- 设备：iPhone 16 Pro / iOS 27.0
- `FixedRegionDetectorTests`：4 PASS
- `StitchEngineTests`：5 PASS
- `FrameSamplingEngineTests`：8 PASS
- 其余状态、诊断、存储测试：8 PASS
- 合计：25 tests / 0 failures

高级测试覆盖：

- 顶部、底部、悬浮稳定区域检测；
- exclusion mask 后 offset 仍精确命中；
- seam 不落在全宽固定栏；
- `[0, 16, 12, 28]` 小幅回滚序列跳过第三帧并输出 `[16, 12]` 位移；
- 跳帧后 renderer 使用原始 frame index，输出尺寸正确；
- Phase 3 五类 fixture 与像素级 renderer 闭环完整回归。

## 构建、签名与安装

- iPhoneOS 27.0 无签名 test build：PASS。
- 真机 `build-for-testing`：PASS。
- DerivedData：`/tmp/SnapFlow-Phase4-Device`
- `swiftformat --lint`：PASS。
- `codesign --verify --deep --strict --verbose=4`：PASS。
- `devicectl device install app`：PASS。
- `devicectl device process launch`：PASS。

Team 与 `com.taoking.LongShot` 仅作为本次命令参数传入，未写入仓库。

## 当前边界

- 检测器采用保守 Gate；只有单侧固定栏且没有底部锚点的画面可能不会启用固定区域排除，而会保持原始帧并依赖低置信度 warning。
- 大范围来回滚动、横向 feed 和大量实时重排不属于当前阶段的强保证范围。
- 人工接缝调整将在 Editor 阶段提供。
