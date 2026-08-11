# Phase 0 真机验收

## 目标

验证 iOS 27 ScreenCaptureKit Full Display Capture 能在 LongShot 进入后台后继续交付来自其他 App 的有效屏幕帧。

## 环境

- Xcode 27.0 Beta（`DEVELOPER_DIR=/Users/tao/Downloads/Xcode-beta.app/Contents/Developer`）
- iPhoneOS 27.0 SDK
- iPhone 16 Pro，iOS 27.0
- 临时签名参数：Team 和 Bundle ID 仅在构建命令中传入，不写入仓库

## 验收步骤

1. 使用独立 DerivedData 构建并严格验签。
2. 通过 `xcrun devicectl device install app` 安装。
3. 通过 `xcrun devicectl device process launch --console` 启动。
4. 点击“开始 Full Display”，在系统选择器中选择整个屏幕。
5. 确认 LongShot 显示“正在捕获”且有效帧计数增长。
6. 切换到 Safari 或设置，连续滚动至少 30 秒。
7. 返回 LongShot，确认“后台帧增长”大于 0，且有效帧总数明显增长。
8. 点击“停止”，确认状态回到“尚未开始”。
9. 从 App Data Container 导出 `Documents/Phase0Frames/<session-id>/`。
10. 检查 `diagnostics.json`，并逐张查看 `frame-*.png`，确认至少一张来自其他 App。

## Gate 判定

- Full Display 系统选择器可用。
- Stream 启动、停止无错误。
- 后台 30 秒期间有效帧计数持续增长。
- 诊断帧内容来自其他 App。
- 上述任一项未取得客观证据时，Phase 0 不得标记 PASS。

## 2026-08-11 实机结果

Status: **PASS**

- 签名 Debug 构建：PASS。
- `codesign --verify --deep --strict --verbose=4`：PASS，Designated Requirement 满足。
- `devicectl device install app`：PASS。
- `devicectl device process launch`：PASS。
- 系统 Full Display Picker：PASS。
- 跨 App 后台持续时间：59.474637 秒。
- 后台新增有效帧：751。
- 该 session 导出时帧数：2932 received / 2932 valid / 0 invalid。
- 诊断帧：8 张，1206 × 2622，已在临时目录视觉检查，包含系统 Picker 和其他 App 内容。
- 正常停止：PASS，状态恢复为 idle，诊断 JSON 成功落盘。

真机诊断帧和 App Data Container 导出物仅保存在 `/tmp`，不提交到仓库。
