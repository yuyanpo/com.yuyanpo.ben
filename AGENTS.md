# Ben 开发约定

- 产品定义以 `specs/PRD.md` 为准。名称 Ben，Bundle Identifier `com.yuyanpo.ben`，最低 macOS 15。
- 使用 Swift、SwiftUI、AppKit 与 Apple 官方 Translation API。不引入 Electron、WebView 或私有翻译接口。
- 原文、译文和凭据不得写入日志。云翻译仅在用户显式选择后发起；本地失败不自动回退云端。
- API Key 使用 Keychain；不要保存到 UserDefaults 或仓库。
- 取词必须先于 Ben 激活，优先辅助功能 API。未实现的复制兜底不能读取陈旧剪贴板假装成功。
- UI 状态在 MainActor 更新。新请求取代旧请求，迟到结果不得覆盖新结果。
- 保持菜单栏应用轻量，复用浮窗，不在空闲时轮询剪贴板或选区。
- 本地构建：`xcodebuild -project Ben.xcodeproj -scheme Ben -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build`。
- 核心系统能力需真机验收；编译成功不代表权限、语言模型下载和跨应用取词已经验证。
- 保留 reference 原始素材。图标衍生文件位于 Assets.xcassets。
