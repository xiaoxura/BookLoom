# 平台、应用 ID 与发布

## 1. 域名与 App ID：不需要买新域名

你已经有 `xiaoxura.com`，直接用它的子域名即可。**应用 ID 不要求域名真实可访问，只要求反向域名唯一、稳定、由你控制。**

推荐：

| 用途 | 值 |
| --- | --- |
| 应用 ID（Android / iOS / macOS / Linux / Windows） | `com.xiaoxura.bookloom` |
| 官网 / 下载页 / 文档 | `https://bookloom.xiaoxura.com` |
| 短链 / 分享 | `https://bl.xiaoxura.com`（302 到 `bookloom.xiaoxura.com`） |
| 仓库 | `https://github.com/xiaoxura/bookloom` |
| 深链 scheme | `bookloom://` |
| App Links host | `bookloom.xiaoxura.com` |
| 项目文件扩展名 | `.bookloom`（ZIP 容器） |

### 为什么是 `com.xiaoxura.bookloom`

反向域名规则：

```text
bookloom.xiaoxura.com  →  com.xiaoxura.bookloom
```

这正是你已有的域名体系，不需要购买 `bookloom.app` / `bookloom.com`。

`bl.xiaoxura.com` 更适合做短链，不建议拿它做 App ID：

```text
bl.xiaoxura.com  →  com.xiaoxura.bl
```

也能用，但 `bl` 太短、含义会随时间变化，而 **Android applicationId 一旦上架就不能改**，iOS Bundle ID 同理。App ID 应该用完整品牌名。

### 域名需要做什么

1. 在 DNS 给 `bookloom` 加一条 A / CNAME，指向你的静态托管（EdgeOne Pages 或其它）。
2. 配 HTTPS 证书。
3. `bl` 配 302 跳转到 `bookloom.xiaoxura.com`。
4. 如果以后做 Android App Links，`https://bookloom.xiaoxura.com/.well-known/assetlinks.json` 必须直接返回 JSON；**不能用 302 的 `bl` 域名做 App Links host**。
5. Apple Universal Links 同理，用 `bookloom.xiaoxura.com`。

没有网站也可以先只保留 App ID；等有下载页时再配 DNS。

## 2. 各平台标识

### Android

```kotlin
android {
    namespace = "com.xiaoxura.bookloom"
    defaultConfig {
        applicationId = "com.xiaoxura.bookloom"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }
}
```

- `applicationId` 上架后不可改。
- 签名密钥单独保管，不提交仓库。
- 需要 `READ_MEDIA_*` 吗？优先 SAF，不申请宽泛存储权限。
- 分享用 `share_plus`；文件保存用 SAF。

### Linux

- GTK application id：`com.xiaoxura.bookloom`
- D-Bus 名：`com.xiaoxura.bookloom`
- Flatpak id：`com.xiaoxura.bookloom`
- 桌面文件名：`com.xiaoxura.bookloom.desktop`
- 图标按 Freedesktop 规范安装。

### Windows

- 可执行文件：`bookloom.exe`
- MSIX `Identity Name`：`com.xiaoxura.bookloom`
- 文件关联 / 协议注册在安装器或 MSIX manifest 中声明。
- 未签名安装包会触发 SmartScreen，早期可接受，正式发布建议签名。

### macOS / iOS（后续）

- Bundle Identifier：`com.xiaoxura.bookloom`
- iOS 需要 macOS + Xcode + Apple Developer Program。
- macOS 分发需要签名 + 公证（notarization）。
- 代码层不提前引入 Apple 专用依赖；用平台接口隔离。

## 3. 版本号

统一使用语义化版本：

```yaml
# pubspec.yaml
version: 0.1.0+1
```

- `0.1.0`：M0–M1，文本核心。
- `0.2.0`：M2，格式与成书。
- `0.3.0`：M3，书架与备份。
- `1.0.0`：M4，三端正式版。
- `+1` 是 build number；Android `versionCode`、iOS `CFBundleVersion` 由 Flutter 读取。
- 每次发布更新 `CHANGELOG.md`，打 git tag `v0.1.0`。
- 不在同一天连续发多个 minor；功能和版本节奏解耦。

## 4. 构建与打包

### Linux

```bash
flutter build linux --release
# 产物：build/linux/x64/release/bundle/
```

分发方式：

| 格式 | 用途 | 说明 |
| --- | --- | --- |
| AppImage | 免安装、单文件 | 适合早期分发；需处理 GTK 依赖 |
| Flatpak | 桌面商店 / 沙箱 | Flathub 上架流程较长 |
| deb | Debian / Ubuntu | 依赖声明清楚，适合企业内分发 |

建议先 AppImage + deb，Flatpak 随后。测试 Ubuntu 22.04 / 24.04、Fedora 最新版。

### Windows

```bash
flutter build windows --release
```

分发方式：

- MSIX：现代安装、可签名、支持自动更新基础设施；用 `msix` 包生成。
- Inno Setup / WiX：传统安装包，文件关联方便。
- 便携 ZIP：早期测试用。

### Android

```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

- 内部测试用 APK；上架用 AAB。
- 签名配置放 `android/key.properties`（不提交），keystore 备份好。
- 先在一台低端 Android 机测 100 万字书的滚动和输入。

### Apple（后续）

```bash
flutter build macos --release
flutter build ios --release --no-codesign   # 仅验证编译
```

真正分发需要 Xcode archive、签名、公证 / App Store Connect。

## 5. 发布流程

1. 更新 `pubspec.yaml` 版本和 `CHANGELOG.md`。
2. `flutter analyze`、`flutter test`、三端构建。
3. 手工验收：导入、编辑、导出、备份恢复、Android SAF。
4. 打 tag：`git tag v0.1.0 && git push origin main --tags`。
5. 上传构建产物，生成 SHA-256 校验和。
6. 在官网/仓库 Release 写更新说明和已知问题。
7. Android 先内测轨道，桌面先小范围分发。

## 6. 自动更新

- **Android**：走 Google Play / 国内应用商店；不要在应用内下载 APK 绕过商店。
- **Linux**：Flatpak 走仓库更新；AppImage 首版做“检查新版本 → 打开下载页”。
- **Windows**：MSIX 可接 App Installer；Inno 版首版同样做手动检查。
- 桌面静默自动更新涉及签名、回滚、差分包，**1.0 前不做**；先保证手动更新可靠。
- 更新检查必须可关闭，且默认不发送书稿/使用数据。

## 7. 签名与密钥

- Android keystore：离线备份两份，密码放密码管理器；丢失后无法更新已上架应用。
- Windows 代码签名证书：正式分发再买；早期 SmartScreen 警告在 README 说明。
- Apple Developer：$99/年；iOS 必需，macOS 公证也需要。
- Linux 包签名：deb 仓库需要 GPG；AppImage 可提供校验和。

## 8. 商店与合规

- 隐私政策：明确“文件只在本机处理、不上传、不收集正文”。
- 权限说明：Android 只申请 SAF 所需权限；不申请通讯录、定位、后台定位。
- 内容政策：工具不提供书源、不破解 DRM；用户需对导入内容拥有权利。
- 第三方许可：OpenCC、字体、Dart 包在 `THIRD_PARTY_NOTICES.md` 列出。
- 年龄分级：工具类，无用户生成内容分发。

## 9. 发布检查清单

- [ ] 版本号、CHANGELOG、tag 一致
- [ ] Android applicationId 仍为 `com.xiaoxura.bookloom`
- [ ] iOS/macOS Bundle ID 一致（后续）
- [ ] 三端安装包在干净机器/模拟器可启动
- [ ] 导入 TXT / EPUB / DOCX 各一本
- [ ] 导出 EPUB 3 / EPUB 2 并用 Calibre 打开
- [ ] 导出 DOCX 并用 Word 打开
- [ ] 备份 → 清数据 → 恢复
- [ ] Android SAF 选目录、分享
- [ ] 无网络环境完整跑一遍
- [ ] 隐私政策、许可证、校验和已更新
