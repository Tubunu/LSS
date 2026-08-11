# Phase 1 验收记录

## 状态

**CODE COMPLETE / DEVICE VERIFICATION PENDING**

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

## 待验证

- 在重构后的 Phase 1 页面通过系统 Picker 完成一次短捕获与正常 stop。
- 连续捕获 3 分钟，确认无明显内存持续增长。
- 确认 background / foreground 不破坏 session，且新 session 目录中诊断 JSON 与帧数一致。

阻塞原因是 iOS 系统 Full Display Picker 需要真机上的用户手动确认；`devicectl` 不提供该安全操作。
