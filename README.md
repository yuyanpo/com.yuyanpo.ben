# Ben

轻量的 macOS 翻译工具

- **Bundle ID**：`com.yuyanpo.ben`
- **版本**：0.0.1（构建号 1）
- **技术栈**：Swift 6、SwiftUI、AppKit、Apple Translation framework
- **最低系统**：macOS 15.0
- **开发环境**：Xcode 27.1（包含 Icon Composer 图标编译支持，已验证）
- **默认服务**：macOS 系统本地翻译；首次使用可能需要下载语言模型

## 开始开发

初期开发只构建和运行 Debug，无需打 Release 包。在项目目录执行下面的命令，会按 Xcode 中的 Apple Development 配置签名构建 Debug 应用，并重启本目录下已运行的 Debug 版本：

```sh
./scripts/run-dev.sh
```

应用位于 `build/Build/Products/Debug/Ben.app`，启动后从屏幕顶部菜单栏进入，默认没有 Dock 图标。代码修改后再次运行脚本即可；已有最新产物时也可以直接打开这个 App。

也可以打开 `Ben.xcodeproj`，选择 Ben scheme / My Mac，按 ⌘R。Xcode 的 Run 使用 Debug 配置；使用此方式时，先退出命令行启动的 Ben，避免重复运行。首次可从菜单栏选择「翻译文本…」，直接输入文本测试，无需辅助功能权限。

仅检查是否编译通过时，可使用无签名命令：

```sh
xcodebuild -project Ben.xcodeproj -scheme Ben -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

本机构建运行使用固定的 Apple Development 签名。Release 构建、分发打包、Developer ID 签名和公证留待分发阶段处理。

使用全局选词翻译前，在 Ben 设置中点击辅助功能授权，并在系统设置中开启 Ben。如果百度翻译已占用 Option+C，请先由你在百度翻译中关闭该快捷键或退出它，然后在 Ben 设置中点击「重试注册」。Ben 不会自动退出其他软件。

设置打开、窗口重新获得焦点、返回 Ben 和主动刷新时，都会重新读取系统辅助功能权限。若系统里的 Ben 已开启但应用仍未授权，先退出重开；仍无效时，在系统辅助功能列表移除旧 Ben，再添加 `build/Build/Products/Debug/Ben.app` 并开启。未授权时，Ben 设置提供「在 Finder 中显示当前 Ben」入口。从旧 ad-hoc 签名切换到 Apple Development 后可能需要重新授权一次，后续保持相同签名身份和应用路径。

如需诊断，使用 `open -n -W -g -a "$PWD/build/Build/Products/Debug/Ben.app" --stdout "$PWD/build/accessibility-check.log" --args --check-accessibility`，结果只包含当前进程的权限布尔状态。应通过系统启动检查，直接从已授权的终端运行可能继承终端权限，不能代表日常启动的 Ben。

## 当前基础版本

- 菜单栏常驻、原生浮窗、手动输入，以及「关于 Ben…」应用信息弹窗。
- 固定 Option+C 注册，冲突状态提示。
- 辅助功能 API 直接读取选中文字，不使用剪贴板取词兜底。
- 系统翻译、基本语言方向设置、复制译文和错误状态。
- 自动识别为中英阅读优化：最多 3 个词、40 个 ASCII 字母的短文本优先按英语处理；原文语种菜单可手动纠正并重译，新捕获选区重置为自动。面板按内容调整高度，长输入和译文分别滚动。
- 按住浮窗顶部的 Logo、标题或空白区域即可拖动窗口。
- 统一 Provider 协议、第三方 API 和大模型占位实现。
- 提供的 `reference/logo.svg` 已生成品牌图片、应用图标和菜单栏模板图标。

API / 大模型尚未接入真实请求，设置中不会让用户保存无效凭据。完整需求、分期和验收表见 [specs/PRD.md](specs/PRD.md)。

## 目录

Xcode 使用与 One 一致的蓝色文件系统同步文件夹。`Ben` 下新增的 Swift 文件会自动加入应用构建；`specs`、`scripts` 和 `reference` 仅用于导航，不加入应用 Target。`Info.plist` 作为构建配置输入，不复制到资源目录；内嵌的 `BenIcon.icon` 保留单独资源引用。

```text
Ben/App         应用生命周期、菜单栏、浮窗控制
Ben/Models      请求结果、语言方向、界面状态
Ben/Services    取词、快捷键、翻译 Provider
Ben/Views       翻译面板和设置
Ben/Resources   Info.plist 和图标资源
specs           PRD 与开发验收记录
scripts         本地工程检查
reference       原始 Logo 参考（保留原件）
```

系统翻译通过 SwiftUI `translationTask` 获取 session，适配层只在有效视图任务内使用它。未来网络服务实现 `TranslationProvider`，不改变结果 UI。

## 更新图标

替换 `reference/logo.svg` 后运行 `./scripts/generate-app-icons.sh`。脚本生成 `BenIcon.icon` 原生 Icon Composer 资源，使用纯白背景与独立的黑色 SVG 符号，关闭符号玻璃效果和阴影，避免旧式图标在系统中出现双层灰框。Xcode 编译为应用的 `BenIcon.icns` 和图标资源；同时生成 16–1024px 纯白底 PNG 供检查与复用。高清 BrandMark 保留白色圆角底板和四周透明边距（1024px 画布每边 100px）；菜单栏使用前景符号生成的透明 18/36px 模板图标。关于弹窗直接显示 BrandMark。原始素材保持不变，衍生资源位于 `Ben/Resources/Assets.xcassets`，无需安装第三方依赖。

## 后续工作

可配置快捷键、模拟复制兜底、更多源/目标语言、模型准备入口、第三方 API、Keychain、大模型流式翻译及签名分发。基础版本仍需真机验证语言模型下载、实际翻译和跨应用取词。
