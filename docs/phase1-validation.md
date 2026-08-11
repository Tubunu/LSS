# Phase 1 验收记录

## 状态

**PASS**

## 已完成

- `ScreenCaptureManager` 管理系统 Picker 与顶层状态。
- `ScreenCaptureSession` 封装 `SCStream` 生命周期。
- `StreamOutputHandler` 在有界串行队列接收帧。
- `FrameSampler` 阶段性限制为最多 60 张、最短间隔 3 秒，不保存所有视频帧。
- `TemporaryFrameStore` 使用 Caches 内的独立 session 目录，并排除 iCloud 备份。
- Capture 状态机防止重复 start，stop 入口只在 starting / capturing 可用。
- Home / Capture 页面、用时与关键帧反馈、本地隐私说明。

## 已验证

- iPhoneOS 27.0 无签名 clean build：PASS。
- iOS 27 真机单元测试：PASS，8 tests / 0 failures。
- 临时 Team / Bundle ID 签名 clean build：PASS。
- `codesign --verify --deep --strict`：PASS。
- `devicectl` 安装与启动：PASS。
- 首页真机视觉检查：PASS。
- 重构后 App 内正常 stop：PASS（两次会话均记录为“捕获已完成”）。
- background / foreground 保持 session：PASS。
- 连续后台捕获 376.16 秒：PASS。
- 长会话后台新增 17,688 帧，总计 18,133/18,133 有效帧、0 无效帧。
- 长会话关键帧严格封顶 60 张，JSON `selectedFrames` 与落盘 PNG 数一致；帧尺寸均为 1206 × 2622。
- 系统捕获控件停止路径：PASS，诊断正确记录“用户已停止流播放”。

## 内存验证边界

本阶段没有采集 Instruments 或 RSS 时间序列，因此不能声称完成了精确内存曲线分析。验收“无明显内存持续增长”的依据是：真机后台持续运行超过 6 分钟并处理 18,133 帧、接收队列有界、只持久化最多 60 张帧、App 全程存活且无崩溃。更严格的内存与分配分析留到 Phase 11 性能与稳定性阶段。

## 真机会话证据

- 长会话 ID：`D4BA478E-B3C7-4136-9A6F-9282287C2414`
- 后台时长：376.155 秒
- 后台帧增量：17,688
- 接收 / 有效 / 无效：18,133 / 18,133 / 0
- 选择帧：60（落盘 PNG：60）
- 会话缓存占用：约 237 MB
- 停止方式：iOS 系统捕获控件

用户屏幕内容只导出到 `/tmp` 做本地计数和元数据检查，未提交仓库。
