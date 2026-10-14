# AppLockManager

用于 TrollStore 的批量 App PIN 门禁工具。GitHub Actions 同时生成：

- `AppLockManager.tipa`：由 TrollStore 安装的管理 App
- `AppLock.dylib`：可单独使用的注入动态库

## 功能

- 首次打开管理 App 不要求密码
- 在“设置”中保存任意 6 位数字 PIN
- 设置 PIN 后，管理 App 每次重新打开或从后台返回都会要求验证
- 展示可注入 App 的图标、名称和 Bundle ID，可搜索、全选或多选
- 对所选 App 批量注入或批量移除 `AppLock.dylib`
- 目标 App 每次打开或从后台返回时显示全屏 PIN 门禁
- PIN 错误时保持遮挡，并显示“PIN码验证失败，禁止使用”

修改 PIN 后，需要重新勾选目标 App 并执行“批量注入”，新 PIN 才会写入这些 App。

## 安全移除策略

注入时会同时写入专属的 `Frameworks/AppLock.owner` 标记。批量移除必须同时满足：

1. 目标中存在 `Frameworks/AppLock.dylib`；
2. `AppLock.owner` 内容完全匹配；
3. Mach-O 中确实存在该 dylib 的加载记录。

任一条件不满足都会跳过并报错，因此不会删除其他注入器或其他插件的 dylib。移除只处理 `AppLock.dylib`、`AppLock.pin`、`AppLock.owner` 和 AppLock 对应的 Mach-O 加载命令。

## 安装和使用

1. 从 GitHub Actions 下载 `AppLockManager-tipa` 构建产物。
2. 解压 artifact，使用 TrollStore 安装其中的 `.tipa`。
3. 首次打开 AppLock，在“设置”中保存 6 位 PIN。
4. 返回“应用”，勾选目标 App，点击“批量注入”。
5. 若要卸载门禁，勾选目标 App 并点击“批量移除”。

注入会终止目标 App；完成后重新打开即可。App 更新或重新安装后通常需要再次注入。系统 App 的可注入性取决于 iOS 版本和 TrollStore 环境。

## 构建

构建依赖 Theos、iPhoneOS SDK、`ldid`、`dpkg` 和 Xcode：

```sh
export THEOS=/path/to/theos
make package
```

输出位于 `packages/AppLockManager_*.tipa`，独立 dylib 位于 `build/AppLock.dylib`。

## 第三方组件

批量注入、Mach-O 处理和 CoreTrust 辅助逻辑基于 MIT 许可的 [Lessica/TrollFools](https://github.com/Lessica/TrollFools)。原始许可保存在 `LICENSE-TrollFools`。

本工具仅应用于你有权修改的设备和 App。PIN 配置保存在目标 App 包中，是访问门禁而不是数据加密；具备逆向或文件系统访问能力的人仍可能提取或修改它。
