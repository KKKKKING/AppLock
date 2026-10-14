# AppLock.dylib

一个极小的 iOS 注入动态库。通过 TrollStore 生态的注入工具把 `AppLock.dylib` 注入微信、相册、Telegram 等目标 App 后，每次打开或重新进入 App 都会显示全屏 PIN 锁。

## 行为

- 固定 6 位 PIN：`930809`
- PIN 正确：解除遮挡并继续使用 App
- PIN 错误：保持全屏遮挡，并弹出“PIN码验证失败，禁止使用”提示
- App 进入后台：立即恢复锁定，避免从多任务切回时绕过
- 支持 iOS 14 及以上的 arm64 设备

> 这是本地访问门禁，不是加密方案。PIN 存在于动态库二进制中，有逆向能力的人仍可提取或修改它。

## 构建

需要安装带 iPhoneOS SDK 的 Xcode：

```sh
make clean verify
```

产物位于 `build/AppLock.dylib`。每次推送到 `main` 后，GitHub Actions 也会构建并上传名为 `AppLock-dylib` 的产物。

## 注入

在已安装 TrollStore 的设备上，使用兼容的 dylib 注入工具选择目标 App 和 `AppLock.dylib`，完成注入并重签名后重新打开目标 App。只向你有权修改的 App 注入；系统相册能否注入取决于设备系统版本、注入工具和越狱/巨魔环境。
