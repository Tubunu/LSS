# LongShot

LongShot 是一款面向 iPhone / iOS 27+ 的原生滚动长截图 App。用户通过 ScreenCaptureKit 系统 Full Display Picker 授权后，App 可在后台接收跨 App 屏幕帧，后续将用于关键帧筛选和长图拼接。

## 当前状态

Phase 0 技术 Gate、Phase 1 Capture Pipeline 和 Phase 2 自适应关键帧筛选已在 iPhone 16 Pro / iOS 27.0 真机通过：

- 系统 Full Display Picker 正常；
- ScreenCaptureKit `SCStream` 启动和停止正常；
- 切换到其他 App 后后台持续收帧 59.47 秒；
- 2932 帧全部有效，后台新增 751 帧；
- 限量诊断帧能落盘且内容来自其他 App。
- 重构后的 Capture Pipeline 后台连续运行 376.16 秒；
- 18,133 帧全部有效，后台新增 17,688 帧；
- 关键帧缓存严格封顶 60 张，App 内 stop 与系统停止路径均通过。
- 自适应采样使用轻量灰度签名、感知哈希和纵向位移估计；
- Phase 2 真机会话从 751 张有效流帧中保留 37 张关键帧，并写入逐帧决策元数据。

完整阶段规划见 [PLAN.md](PLAN.md)，真机验证见 `docs/phase*-validation.md`。

## 要求

- Xcode 27.0+
- iOS 27.0+ iPhone
- 有效 Apple Development 签名身份与对应 Provisioning Profile
- XcodeGen 2.44.1+

## 构建

```bash
xcodegen generate
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer \
xcodebuild \
  -project LongShot.xcodeproj \
  -scheme LongShot \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/LongShotDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

真机构建时，通过命令行临时传入自己的 `DEVELOPMENT_TEAM` 和 `PRODUCT_BUNDLE_IDENTIFIER`，不要将个人签名信息提交到仓库。

## 权限与隐私

App 声明 `NSScreenCaptureUsageDescription` 与 `screen-capture` Background Mode。屏幕内容默认仅在设备本地处理，不上传。Phase 0 诊断帧保存在 App Documents 中，仅用于技术 Gate 验证。

## 已知限制

当前仓库已完成 Phase 2，正进入 StitchEngine MVP。编辑、导入、历史和导出将按 `PLAN.md` 后续 Phase 顺序实现。
