# Ben

轻量的 macOS 翻译工具

**召之即来，用后即去。**

https://github.com/user-attachments/assets/397bad63-6429-443e-a2b9-60477b274453

选中文字后按 **Option + C**，在浮窗中查看译文；按 **Option + Z** 或从菜单栏打开「翻译文本」手动输入。两个全局快捷键都可在设置中点击录入新组合，并支持恢复默认。

- 原生菜单栏应用，使用 Swift、SwiftUI、AppKit。
- 支持微软、谷歌、百度翻译和 B站 Index-Translate 大模型，设置中手动选择，默认微软。
- 百度查词显示英美音标、词性释义、词形和标签，支持系统语音朗读。
- 支持中英自动方向、手动选择原文语种和复制译文。
- 浮窗随内容调整大小，支持拖动和长文本滚动。
- 版本：0.0.1；最低系统：macOS 15；Bundle ID：`com.yuyanpo.ben`。

## 使用说明

选词翻译需要在系统设置中开启 Ben 的辅助功能权限，手动输入无需授权。设置快捷键时检查 Ben 内部重复、系统快捷键及其他应用的独占注册，检测到冲突时保留原配置并提示；非独占注册或底层键盘监听实现的快捷键无法可靠检测。

翻译需要联网，原文只发送给当前选定服务；失败时不会自动切换。当前接口无需填写 Key，公开免费服务可能限流或调整。原文与译文不写入日志，不保存翻译历史；重复请求使用内存缓存，退出后清空。

## 本地开发

使用 Xcode 27.1，配置 Apple Development 签名后，打开 `Ben.xcodeproj`，选择 **Ben / My Mac**，按 **⌘R** 运行。也可以在项目目录执行：

```sh
./scripts/run-dev.sh
```

脚本构建并重启 Debug 应用，产物位于 `build/Build/Products/Debug/Ben.app`。开发阶段只使用 Debug。

仅验证编译时：

```sh
xcodebuild -project Ben.xcodeproj -scheme Ben -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

快捷键注册与冲突检查：`./scripts/check-shortcuts.sh`（使用独立的临时偏好域和快捷键，不修改 Ben 的用户配置）。

快捷键设置布局与焦点检查：`./scripts/check-shortcut-settings.sh`，渲染默认、录入、错误和深色状态并检查控件位置不变。

## 项目结构

- `Ben/`：应用源码与资源。
- `scripts/`：开发运行与图标生成脚本；`run-dev.sh` 会先生成最新图标，再构建并重启 Debug 应用。
- `reference/`：宣传视频与原始 Logo；Logo 更新后运行 `./scripts/generate-app-icons.sh` 生成图标。
- `specs/`：[产品需求](specs/PRD.md)与[验收记录](specs/VALIDATION.md)。
