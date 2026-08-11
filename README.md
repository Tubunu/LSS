# LongShot

LongShot 是一款面向 iPhone / iOS 27+ 的原生滚动长截图 App。用户通过 ScreenCaptureKit 系统 Full Display Picker 授权后，App 可在后台接收跨 App 屏幕帧，后续将用于关键帧筛选和长图拼接。

## 当前状态

Phase 0 技术 Gate 已在 iPhone 16 Pro / iOS 27.0 真机通过：

- 系统 Full Display Picker 正常；
- ScreenCaptureKit `SCStream` 启动和停止正常；
- 切换到其他 App 后后台持续收帧 59.47 秒；
- 2932 帧全部有效，后台新增 751 帧；
- 限量诊断帧能落盘且内容来自其他 App。

完整阶段规划见 [PLAN.md](PLAN.md)，真机验证见 [docs/phase0-device-verification.md](docs/phase0-device-verification.md)。

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

当前仓库处于 Phase 0，只包含经真机验证的捕获 PoC。拼接、编辑、导入、历史和导出将按 `PLAN.md` 后续 Phase 顺序实现。
