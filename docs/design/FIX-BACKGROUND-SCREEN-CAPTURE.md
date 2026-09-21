# 修复切到其他 App 后台录制被系统强制中断设计方案（FIX-BACKGROUND-SCREEN-CAPTURE）

## 1. 缺陷背景与根因

### 1.1 缺陷现象
用户点击【开始捕获】，并在系统面板选择「共享整个屏幕」后，录制成功开始。但当用户上滑切回桌面或打开其他 App（如微信、Safari、设置）时，录制立即中断，状态栏录屏红点消失，返回 LongShot 显示已停止。

### 1.2 根因定位
1. **iOS 强制要求 `UIBackgroundModes: screen-capture`**：
   苹果在 iOS 上开放 `ScreenCaptureKit` 支持跨 App 捕获屏幕时，规定应用必须在 `Info.plist` 中声明 `UIBackgroundModes` 包含 `screen-capture`。
2. **构建包被剥离后台模式声明**：
   在历史提交 `9284fa0` 中，为了排查自签安装完整性问题，在 `project.yml`、`Info.plist` 以及 `.github/workflows/build-ipa.yml`（通过 PlistBuddy Delete 指令）中将 `UIBackgroundModes` 彻底移除。
3. **内核级掐断流**：
   缺乏该配置导致应用一旦退至后台，iOS 内核立即认定该应用无权在后台维持屏幕捕获流，直接终止 `SCStream` 并抛出错误码 `-3824`（`SCStreamError.Code.missingBackgroundMode`）。

---

## 2. 解决方案设计

### 2.1 恢复项目配置与构建流水线
1. **`project.yml`**：
   在 `targets.LongShot.info.properties` 中添加：
   ```yaml
   UIBackgroundModes:
     - screen-capture
   ```
2. **`LongShot/Info.plist`**：
   添加标准键值：
   ```xml
   <key>UIBackgroundModes</key>
   <array>
       <string>screen-capture</string>
   </array>
   ```
3. **`.github/workflows/build-ipa.yml`**：
   删除以下两行防御性删除脚本：
   ```bash
   # 移除 UIBackgroundModes 防御性检查（避免个人免费证书因未授权后台模式导致 iOS installd 报无法验证完整性）
   /usr/libexec/PlistBuddy -c "Delete :UIBackgroundModes" Payload/LongShot.app/Info.plist 2>/dev/null || true
   ```
   保留完整的 Ad-Hoc 代码签名（`codesign --force --deep --sign -`）与保留软链接归档（`zip -qr -y`），确保主流签名工具正常安装。

### 2.2 增加后台任务保活双保险（`ScreenCaptureManager.swift`）
在切出应用至后台的过程中，系统可能在捕获流建立前将进程短期冻结。通过 `UIApplication.shared.beginBackgroundTask` 申请系统过渡保活时间片：
```swift
private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

func appDidEnterBackground() {
    guard state == .capturing else { return }
    backgroundStartedAt = Date()
    backgroundStartFrameCount = captureDiagnostics.snapshot().validFrames

    if backgroundTaskIdentifier == .invalid {
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "LongShot.ScreenCapture") { [weak self] in
            self?.endBackgroundTaskIfNeeded()
        }
    }
}

func appDidBecomeActive() {
    endBackgroundTaskIfNeeded()
    ...
}

private func endBackgroundTaskIfNeeded() {
    if backgroundTaskIdentifier != .invalid {
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }
}
```

### 2.3 异常中断精确诊断
在 `handleUnexpectedStop` 中增加中断原因细化：
```swift
private func handleUnexpectedStop(_ error: Error) {
    guard !isIntentionalStop else { return }
    session = nil
    endBackgroundTaskIfNeeded()
    let snapshot = captureDiagnostics.snapshot()
    if snapshot.selectedFrames >= 2 {
        state = .completed
    } else {
        state = .failed(message: "屏幕捕获已中断：\(error.localizedDescription) (\((error as NSError).code))")
    }
    writeDiagnostics(state: state)
}
```
