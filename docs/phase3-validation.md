# Phase 3 验收记录

## 状态

**PASS**

## 实现范围

- `FrameAnalyzer` 将 `CGImage` 转为统一的自上而下灰度分析图。
- `OverlapDetector` 在允许范围内搜索真实纵向位移，不使用固定 overlap。
- 匹配结果包含 offset、overlap、normalized error、uniqueness、texture、confidence 和前五个调试候选。
- 基础 seam 在重叠区域内按逐行误差选择，并优先靠近中部的等价候选。
- `StitchPlan` 表示 frame placement、segment、seam、fixed regions 占位、warning 和预计输出高度。
- 低于集中阈值的匹配写入 warning；基础 renderer 会拒绝低置信度 plan，不强行拼接。
- `StitchDebugWriter` 将完整 plan 与候选写为 JSON。
- 基础 renderer 使用确定性的自上而下 RGBA 行合成，并设置 32,000 px 单边保护上限。

## Fixtures

测试资源位于 `LongShotTests/Fixtures/`：

- `simple_article`
- `settings_list`
- `chat_style`
- `image_feed`
- `edge_cases`

前四类声明 frame order、expected offsets 和 expected final height；edge case 使用互不相关帧验证低置信度保护。

## 真机测试

- 设备：iPhone 16 Pro / iOS 27.0
- `FrameSamplingEngineTests`：8 PASS
- `StitchEngineTests`：5 PASS
- 其余状态、诊断、存储测试：8 PASS
- 合计：21 tests / 0 failures

拼接测试包括：

- 四类 fixture 的相邻 offset 精确命中；
- 最终高度精确命中；
- overlap + offset 等于源帧高度；
- 不相关帧产生 warning 且 renderer 抛出 `lowConfidence`；
- plan 调试 JSON 编解码一致；
- 不兼容尺寸被拒绝；
- `CGImage → FrameAnalyzer → StitchEngine → StitchRenderer` 像素级结果与合成文档一致。

像素级断言在开发中确实发现过坐标方向错误；修复为统一自上而下分析和逐行 RGBA 合成后，完整套件重新通过。

## 构建、签名与安装

- iPhoneOS 27.0 无签名 clean build：PASS。
- 真机 `build-for-testing`：PASS。
- DerivedData：`/tmp/SnapFlow-Phase3-Device-2`
- `swiftformat --lint`：PASS。
- `codesign --verify --deep --strict --verbose=4`：PASS。
- `devicectl device install app`：PASS。
- `devicectl device process launch`：PASS。

Team 与 `com.taoking.LongShot` 仅作为本次命令参数传入，未写入仓库。

## 当前边界

- Phase 3 优先解决纯纵向滚动、大部分内容静态、相邻帧有明显重叠的场景。
- 固定状态栏、导航栏、Tab Bar、输入框与悬浮元素的排除留待 Phase 4。
- 当前基础 renderer 会创建完整 RGBA 输出缓冲；tile rendering 与超长图内存优化留待后续性能阶段。
