# Ben 初始化验证记录

日期：2026-11-12

## Cursor 集成终端取词（2026-11-24）

- 真机检查 Cursor 终端焦点链：焦点为 xterm 隐藏输入框 `xterm-helper-textarea`，其 AXSelectedText 为空，终端选区不经辅助功能暴露，只能走复制兜底。
- 原兜底对 VS Code、Cursor 一律要求 Monaco 非空选区标记；xterm 复制只写纯文本，因此有选区时也被拒绝。现仅在焦点位于 xterm 时免除该标记，编辑器区仍拒绝无选区整行复制；终端无选区时复制不写剪贴板，仍报告未取到。
- Debug 构建通过并已重启；诊断只记录剪贴板是否变化及类型，不输出文本。终端有选区时按 Option+C 的完整流程仍需人工确认。

## 两个翻译快捷键联测（2026-11-20）

- 重建并启动 Apple Development 签名的 Debug 版本，确认辅助功能已授权。
- 在 TextEdit 临时文档中通过系统键盘事件触发快捷键：`Option + C` 将选区填入浮窗，关闭后按 `Option + Z` 会全选原文；在浮窗仍显示时更换 TextEdit 选区，再按 `Option + C` 会填入新选区。这里只验证取词与输入行为，未验证其他应用或翻译服务响应。

## 翻译文本浮窗输入焦点（2026-11-18）

- 「翻译文本」快捷键与菜单入口显示浮窗后，布局完成即将原文 NSTextView 设为 firstResponder；复用窗口每次显示都会恢复输入焦点。
- 临时 AppKit 窗口检查通过：首次显示、已显示时重复调用、关闭后复用显示均聚焦同一可编辑输入框；插入测试文字同步到模型，已有文字保留且不产生翻译请求。
- Apple Development Debug 构建和签名校验通过，已重启本仓库 Debug 应用。跨应用全局按键到浮窗的完整流程仍需真机验收。

## 快捷键设置间距统一（2026-11-17）

- 快捷键区域改为与翻译、权限模块相同的原生 Form 独立行，移除外层 VStack 和手动分隔线，交由 Form 提供统一内边距。
- 移除用途副标题，录入及复原控件缩为 24pt 高，底部反馈区由 52pt 缩为 24pt，消除首尾过大的留白。
- 设置布局回归检查通过：默认、录入、冲突、取消、失焦、保存和深色状态下控件位置与尺寸均保持一致；已检查默认状态渲染。
- Apple Development Debug 构建通过，已重启本仓库 Debug 应用。

## 快捷键设置布局与录入稳定性（2026-11-17）

- 移除重复的「已注册」行和常驻的技术说明，标题下改为简短用途；恢复默认改用带帮助提示的复原图标，检测说明收进信息按钮弹窗。
- 录入控件固定 120 × 30pt，使用细边框；录入时蓝色描边，保存、取消和失焦后清除录入焦点。行高和底部反馈区固定，提示及重试按钮状态变化不改变布局。
- `./scripts/check-shortcut-settings.sh` 使用临时偏好域渲染默认、录入、内部冲突、取消、失焦、成功保存和深色状态，比较两个控件的位置及尺寸完全一致；录入开始、结束后的 firstResponder 清理及失焦取消检查通过。渲染产物在 build/shortcut-validation/settings/，浅色、深色无重叠或截断。
- 这是 AppKit/SwiftUI 离屏窗口与状态检查；实际跨应用取词及快捷键触发流程仍遵循下方真机验收边界。

## 自定义全局快捷键与菜单调整（2026-11-17）

- 「翻译文本」默认 Option + Z，「翻译选中文字」默认 Option + C；移除「翻译文本」和「关于 Ben」末尾省略号，快捷键使用 NSMenuItem 原生右侧栏。
- 设置加入两个快捷键的按键录入、单项恢复默认、注册状态、冲突提示与失败重试；成功注册后保存到独立的 UserDefaults 键，菜单和浮窗提示同步更新。
- `./scripts/check-shortcuts.sh` 通过：默认值和菜单等价键、持久保存、Ben 内部重复、系统快捷键冲突、另一个进程的独占注册冲突、失败后保留旧注册与偏好、录入取消后恢复、成功录入与重新注册。检查使用临时偏好域，不修改用户配置。
- 冲突检查边界：当前 macOS 27.0.1 实测允许独占注册与其他进程的非独占注册重叠；已覆盖系统提供的快捷键列表和独占注册冲突，不能可靠检测非独占注册或底层键盘监听，也无法获取占用应用名称。设置与 PRD 已说明这一限制。
- Debug 无签名构建与 Apple Development 签名构建通过，`codesign --verify --deep --strict` 通过；已通过 run-dev.sh 重启本仓库 Debug 应用。
- 设置页 560 × 720pt 浅色离屏渲染检查通过，两个录入控件、恢复默认和权限区域无重叠或截断。
- CUA 两次连接 Ben 均超时，尚未验证实际菜单显示、点击录入、全局快捷键到窗口的完整交互；编译和底层注册检查不代替这些真机验收。其他软件抢先拦截的组合可能无法进入录入控件，需要改选组合。

## 最新 Logo 资源接入（2026-11-17）

- 应用图标使用蓝底（#336DFA）与白色 SVG 前景的 BenIcon；关于面板和翻译浮窗使用当前 BrandMark，菜单栏使用当前 MenuBarMark 透明模板。
- AppKit / SwiftUI 改用生成的类型化资源引用；浮窗和关于面板保留彩色原图，菜单栏按系统外观渲染模板。
- run-dev.sh 在构建前调用图标生成脚本，从 reference/logo.svg 更新全部衍生资源；已构建并重启本仓库 Debug 应用，Apple Development 签名严格校验通过。
- 从最终应用包加载 BrandMark（1024px）与 MenuBarMark（18pt，模板标记有效）并渲染检查；NSWorkspace 系统应用图标也已确认是最新蓝底白色 A 与选区光标。
- 菜单栏前景缩至 16pt，保持 18pt 画布；已检查 1× / 2× PNG 上下透明边距分别为 1px / 2px，并构建、重启 Debug 应用。
- CUA 连接 Ben 超时，未取得关于面板和翻译浮窗的实际界面；本次完成资源接入、打包与系统文件图标验证，实际窗口显示仍待真机验收。

## 已完成

- 环境：macOS 27.0.1、Xcode 27.1、Apple Swift 6.4；工程 Swift language mode 6，deployment target 15.0。
- Debug 无签名编译通过。
- Debug 本机 ad-hoc 签名编译通过；产物签名 identifier 为 `com.yuyanpo.ben`。
- Release 无签名编译通过，产物为 Ben.app。
- 产物 Info.plist 的 Bundle ID 为 `com.yuyanpo.ben`，`LSUIElement = true`。
- 二进制包含 arm64 和 x86_64 架构。
- 启动本机签名 Debug 版本后，进程保持运行；未自动请求辅助功能权限或启动翻译。
- Logo 参考已导入 BrandMark 和 macOS AppIcon 各尺寸资源，原件保留。
- `git diff --check` 通过。

编译日志只有 Xcode 的 AppIntents 元数据跳过提示（未依赖 AppIntents），没有 Swift 编译错误或代码警告。

## SVG 图标更新（2026-11-12）

- 以新的 `reference/logo.svg` 为源，通过 macOS AppKit 直接生成 16、32、64、128、256、512、1024px AppIcon；BrandMark 更新为 1024px，保留原始 SVG。
- 从 SVG 的内嵌前景提取菜单栏符号，生成 18px（1×）和 36px（2×）透明 PNG。AppDelegate 使用 MenuBarMark 资源，替换原先手绘图形。
- 已核对各尺寸、AppIcon 角落透明度及菜单栏纯黑前景/透明背景，并检查浅色、深色背景合成预览。
- Debug 无签名构建通过；清理未分配的 SVG 衍生文件后，最终增量构建日志无 warning/error。
- 通过 assetutil 与 AppKit 加载产物检查，MenuBarMark 两份资源均已打包，模板标记有效，逻辑大小为 18×18pt。
- 生成脚本无需第三方依赖；更新源 SVG 后执行 `./scripts/generate-app-icons.sh` 即可重新生成。
- 以上是资源和构建验证；实际系统菜单栏显示仍需重新运行 Ben 后验收。

## 未验证及原因

关于弹窗与版本更新：菜单栏新增「关于 Ben…」，使用 AppKit 标准关于面板；Debug / Release 的 MARKETING_VERSION 均为 0.01，构建号为 1。Debug 无签名构建通过，产物 Info.plist 已确认 `CFBundleShortVersionString = 0.01`、`CFBundleVersion = 1` 和 `CFBundleIconFile = AppIcon`；`git diff --check` 通过。编译仅有未依赖 AppIntents 的元数据跳过提示。关于弹窗的实际显示及重复打开仍待人工确认。

UI 自动检查连接 Ben 两次均超时，无法获得可核验的界面状态。启动存活不代表菜单栏、浮窗和系统语言下载界面已经通过验收。没有通过工具操作用户的系统权限，也没有退出现有百度翻译。

## Debug 开发流程与清理（2026-11-12）

- 初期开发仅构建和运行 Debug，Release 分发包暂不生成；之前的 Release 构建记录仅作为历史验证结果。
- 已删除 `build/Build/Products/Release`（App、dSYM、Swift module）、两处 Release 中间目录、临时图标预览/检查文件和旧构建日志，约 13 MiB。Debug 产物及增量构建缓存保留。
- 新增 `./scripts/run-dev.sh`：使用本机 ad-hoc 签名构建 Debug，成功后重启本仓库构建目录里的 Debug 应用。
- 脚本语法检查及实际构建/启动通过，codesign 严格校验通过，产物版本为 0.01（1），进程路径确认指向 `build/Build/Products/Debug/Ben.app`。
- 本次未通过 UI 自动操作验证关于弹窗；实际显示仍需人工确认。

## Logo 与关于弹窗修正（2026-11-12）

- 用户确认起始版本应为 0.0.1；Debug / Release 构建配置已同步更正，构建号仍为 1。前面的 0.01 记录为历史值。
- 原 AppIcon 只有圆角透明，四边中点 alpha 为 1。现 AppIcon 和 BrandMark 四周增加透明边距，1024px 画布每边 100px，保留 SVG 白色圆角底板。
- 已逐像素检查 16–1024px AppIcon 和 1024px BrandMark 的全部外边界，alpha 均为 0；各尺寸透明留白符合比例。
- 关于面板显式使用 BrandMark 作为 applicationIcon，避免 App 图标的系统装饰；简介仅保留「轻量的 macOS 翻译工具」。
- 仅构建带本机签名的 Debug，构建及 codesign 严格校验通过，Bundle 版本 0.0.1，Logo 已打包；run-dev.sh 已重启本仓库 Debug 应用。
- 本次通过 CUA 连接 Ben 仍超时，未取得新版关于弹窗的可核验画面；需人工打开确认。

## App 图标白底修正（2026-11-12）

- AppIcon PNG 改为不透明白色背景；各尺寸无 alpha 通道，外边界 RGB 均为 255。关于弹窗与菜单栏资源维持各自的透明渲染方式。
- 实际通过 NSWorkspace 读取旧式 PNG 的系统图标后，发现仍有灰框；改为生成并接入 `BenIcon.icon` 原生 Icon Composer 文档，纯白 solid 背景、黑色 SVG 前景、glass=false、shadow=none。
- Debug 构建通过，产物 CFBundleIconFile / CFBundleIconName 均为 BenIcon，CFBundleShortVersionString 为 0.0.1；生成 BenIcon.icns，可供旧系统使用。
- 刷新应用目录时间后，NSWorkspace 对正式 Debug 应用路径返回的新图标已核对：白色底板与黑色符号，旧双层灰框消失。该检查是系统文件图标渲染验证；未通过 CUA 操作 Finder 窗口。
- run-dev.sh 已加入构建后 touch 应用目录，帮助刷新同路径旧图标缓存；本次只构建并重启 Debug。

## 辅助功能授权状态修复（2026-11-12）

- SettingsView 原先用独立 @State 保存权限快照；现在与 SelectedTextReader 共享 ObservableObject 状态，每次打开设置、视图出现、应用重新激活、窗口获得焦点及主动刷新时调用 AXIsProcessTrusted，取词前也再次检查，无后台轮询。
- 未授权时加入系统授权条目可能失效的恢复说明及「在 Finder 中显示当前 Ben」，定位当前 Bundle，不修改系统权限。
- 新增 `--check-accessibility` 诊断入口，只输出权限布尔状态，不启动快捷键/面板，不输出选中文字或译文。
- 当前 ad-hoc 签名的 designated requirement 包含 cdhash；本机没有有效代码签名证书，重建后旧授权身份可能不匹配。无法读取受保护 TCC 数据库，没有修改或重置权限数据库。
- 直接由终端启动诊断返回 authorized；通过 Launch Services (`open -n -W -g -a ... --args --check-accessibility`) 正常启动同一产物返回 not authorized。前者可能继承终端权限，不能当作 Ben 授权验收。本次确认应用正常启动确实未获信任；仍需用户在系统设置重新添加当前 Debug 应用并开启。
- Debug 构建、签名严格校验、diff 检查通过，已重启正常 Debug 实例。系统授权切换及跨应用取词仍待人工验证。

## Xcode 文件树整理（2026-11-12）

- 原工程将完整路径的文件引用直接放在一个 Ben 分组里，导航器显示扁平路径。现建立对应磁盘目录的 App、Models、Services、Views、Resources 分组，并改用相对父分组的文件路径。
- 根分组补充 specs、scripts、reference、README.md 和 AGENTS.md。图标素材留在原资源目录，文件引用 ID 和 target 的编译/资源成员保持一致。
- 用户在 Xcode 设置的 Apple Development 自动签名与 Team 配置已保留；所有非文件/分组工程对象与修改前一致。
- 逐项验证旧文件引用仍指向相同磁盘文件，工程 plist 检查通过；独立目录 Debug 无签名构建通过，检查后删除该独立构建缓存，没有替换日常运行产物。
- CUA 成功读取 Xcode，确认已显示新的分层目录；展开 App 后显示 AppDelegate.swift、BenApp.swift、PanelController.swift 正常文件名。

## 蓝色同步文件夹（2026-11-12）

- 按 One 工程方式，将 Ben、specs、scripts、reference 转为 PBXFileSystemSynchronizedRootGroup，工程格式更新为 objectVersion 77。
- 只有 Ben 同步目录关联应用 Target，10 个业务 Swift 源文件由文件系统自动发现；文档、生成脚本和原始素材不参与构建。
- Resources/Info.plist 设置 membership exception，继续作为 INFOPLIST_FILE 输入；内嵌于资产目录的 BenIcon.icon 保留显式资源引用，避免图标丢失。
- 签名、Team、版本、部署目标及其他构建配置逐项确认与修改前一致。
- 独立目录 Debug 无签名构建通过，核对源文件列表和 Bundle 的 BenIcon / 0.0.1；构建后清理独立缓存，未替换当前运行应用。
- CUA 截图已确认 Ben 和各目录显示蓝色文件夹，移除悬空引用产生的 Recovered References；图标显式引用在根导航器显示为 BenIcon.icon。

## 短词识别与紧凑浮窗（2026-11-12）

- 短 ASCII 文本（最多 3 个词、40 个字母）优先英语，其余交给 NLLanguageRecognizer；没有给非拉丁文字添加中英偏置。Ben、Debug、Xcode、API、英文短语、中文、日文、韩文、空文本及纯数字共 11 个样例检查通过（中文繁简归同一语言）。
- 添加面板原文语种纠正菜单；模型检查确认手动纠正替换请求 ID 和 sourceLanguage，新选区重置自动。系统 Session 仍显式接收源语言配置，保留迟到结果保护。
- 移除固定 380pt 面板高度和 85pt 状态占位。宽 400pt，输入及译文按文字测量设定高度上限；通过布局回调调整复用 NSPanel，保持顶部位置并限制屏幕边缘。
- 原生 NSHostingView 离屏渲染检查：空状态 166pt、短词加载 221pt、短译文 265pt、错误 206pt、长文本 537pt；已核对浅色、深色、加载、错误、短译文和长文本图片。样例结果仅为渲染夹具，不代表实际系统翻译输出。
- run-dev.sh 去掉强制 CODE_SIGN_IDENTITY=-，使用用户已配置的 Apple Development。Debug 构建和严格签名校验通过，designated requirement 已使用证书/应用 ID 而非构建 cdhash，当前 Debug 已重启。
- 本次 CUA 连接 Ben 仍超时；实际语言模型下载提示、真实翻译、滚动交互及屏幕边缘动态高度仍需真机人工确认。离屏渲染未发起翻译或语言模型下载。

## 恢复浮窗拖动（2026-11-12）

- 无标题面板的 isMovableByWindowBackground 未能让 SwiftUI 内容响应拖动；改为在顶部非交互标题区域添加 macOS 15 官方 WindowDragGesture，设置明确的矩形命中区域并启用窗口 isMovable。
- 拖动手势只作用于 Logo、标题及标题旁空白，设置/关闭按钮、语言菜单、文本编辑和结果选择位于手势范围外。
- Apple Development 签名 Debug 构建及严格签名校验通过，已重启最新版。
- CUA 连接正式应用与隔离验证窗口均超时，尚未通过真实鼠标拖动验证；需要人工确认加载期间拖动、结果后拖动及文本操作。
- 后续为同一标题拖动区域添加 macOS 15 PointerStyle：经过时 grabIdle，WindowDragGesture 激活时 grabActive；用 GestureState 在拖动结束/取消后自动复位。Debug 编译和签名校验通过并重启，实际鼠标指针切换仍待人工确认。
- 按用户后续反馈改为四向箭头 move 光标，使用 SF Symbol `arrow.up.and.down.and.arrow.left.and.right` 与 PointerStyle.image，热点居中；保留 WindowDragGesture，移除手形及其状态切换。Apple Development 签名 Debug 构建和严格签名校验通过，已重启；实际指针外观仍待人工确认。

## 语言模型加载提示修正（2026-11-12）

- 原加载 UI 始终显示「首次使用可能需下载语言模型」，与实际下载无关。现用 TranslationPhase 分别显示检查、准备、翻译，只在准备阶段显示模型下载说明。
- AppleTranslationProvider 根据 LanguageAvailability 状态处理：installed 直接翻译，supported 调用 prepareTranslation 后再翻译，unsupported 报错。阶段回调在 MainActor 更新，校验请求 ID 与取消状态，防止旧任务改写新请求的状态。
- 通过 Apple 官方 API 只读检查本机状态：en→zh-Hans 和 nl→zh-Hans 为 installed，tr→zh-Hans 为 supported / not installed。此次检查未发起翻译、模型下载或云请求。
- 已检查翻译/检查阶段不含下载提示、准备阶段含下载说明；Apple Development Debug 构建、签名严格校验和 diff 检查通过，已重启。
- 系统下载许可、取消准备、模型下载完成后翻译的真实 UI 仍待人工验收；未将准备阶段描述为正在下载或提供伪进度。

## 下一次人工验收步骤

1. 打开 Ben.xcodeproj，从 Xcode 运行 Ben；确认菜单栏品牌图标和菜单，不显示 Dock 图标。
   选择「关于 Ben…」，确认 Logo 四周透明留白、名称、版本 0.0.1（构建号 1）、单句简介「轻量的 macOS 翻译工具」和版权；关闭后再次打开，确认面板可复用。
2. 选择「翻译文本…」，输入 `Hello, how are you?` 后点击翻译。
3. 如果系统要求下载语言模型，分别测试取消、再次尝试、完成下载。安装完成后断网重试。
4. 在设置中检查 Option+C 注册状态；存在冲突时由用户关闭百度翻译的快捷键并点击「重试注册」。
5. 在 Ben 设置中请求辅助功能权限，由用户授权，点击「刷新状态」。
6. 分别在 Safari、Chrome、VS Code、Xcode 和预览中选中文本，按 Option+C，记录成功或取词错误。当前没有模拟复制兜底，不能把不支持的软件记为通过。
7. 测试无选区、超长选区、中文与英文、目标语言相同、混合和短文本。
8. 连续触发不同选词，确认新结果不被旧请求覆盖；测试取消、关闭和再次打开。
9. 测试复制译文、Esc、结果显示后点击外部关闭、多显示器边缘位置。加载中外部点击暂不关闭。
10. 关闭 Xcode 调试器后再测资源与耗时，不将一次 ps RSS 快照视为正式内存或性能验收。

第三方 API、大模型、Keychain、自定义快捷键、剪贴板兜底和正式签名分发未实现；属于 PRD 后续范围。
