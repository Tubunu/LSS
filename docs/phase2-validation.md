# Phase 2 验收记录

## 状态

**PASS**

## 实现范围

- `FrameSignatureBuilder` 将全尺寸帧缩小为最多 32 × 72 的灰度签名。
- `FrameSignature` 生成 64-bit average hash。
- `FrameSamplingEngine` 计算哈希距离、像素变化率、纵向位移、匹配误差和运动置信度。
- 集中式 `FrameSamplingThresholds` 管理分析间隔、最小位移、快速位移、重复帧和最大间隔阈值。
- 静止重复帧直接丢弃；正常滚动按最小位移选帧；快速变化提高采样密度；有变化但无可靠位移时使用最大间隔保护。
- 每张关键帧在 `frames.json` 中保存原因、分数、位移、变化率、哈希距离、匹配误差和源尺寸。
- 原始帧只在决策选中后编码，落盘总量有 240 张硬上限。

## 自动化测试

`FrameSamplingEngineTests` 覆盖：

- 完全相同帧静止 10 秒；
- 轻微滚动；
- 正常滚动；
- 快速滚动；
- 小幅回滚后继续向下；
- 小动画区域；
- 最大间隔保护；
- 最大容量。

真机执行全部测试：16 tests / 0 failures，其中 Phase 2 新增 8 tests。

## 真机会话证据

- 设备：iPhone 16 Pro / iOS 27.0
- 会话 ID：`8753AD02-2532-4DDC-931C-B624BC134484`
- 状态：捕获已完成（App 内 stop）
- 接收 / 有效 / 无效：751 / 751 / 0
- 后台时长与帧增量：16.739 秒 / 401
- 关键帧：37
- 决策原因：initial 1、movement 5、fastMovement 31
- 元数据时间跨度：21.279 秒
- 平均关键帧间隔：0.591 秒
- PNG / `frames.json`：37 / 37
- 会话缓存：约 26 MB
- 图像尺寸：1206 × 2622

用户实际会话约 23 秒，短于操作说明中的 45 秒，因此没有将其描述为“真机静止 10 秒验证”。静止页面 10 秒只保留首帧由确定性 fixture 验证。用户屏幕内容仅导出到 `/tmp` 做本地文件计数和元数据检查，未查看或提交仓库。

## 签名与安装

- 签名 Team 与 `com.taoking.LongShot` 仅通过 `xcodebuild` 命令参数传入。
- DerivedData：`/tmp/SnapFlow-Phase2-Device`
- `codesign --verify --deep --strict --verbose=4`：PASS。
- `devicectl device install app`：PASS。
- `devicectl device process launch`：PASS。
