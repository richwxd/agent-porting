# MiniMax Code Windows → Linux 移植（.deb，自包含）

把 **MiniMax Code 3.1.16** 的 Windows NSIS 安装包移植为 Linux x64 deb，
安装到 `/opt/minimax-code`，版本号与 Windows 包完全一致（3.1.16），
检查更新也走 Windows 版本流（`latest.yml` + Windows NSIS 安装包）。

## 项目结构

```
minimax-code-porting/
├── win/                                  # Windows 安装包输入（不入库）
│   └── MiniMax Code Setup 3.1.16-x64.exe
├── scripts/
│   ├── build-deb.sh                      # 唯一入口：win/ → dist/minimax-code_<ver>_amd64.deb
│   ├── lib.sh                            # 解包/版本读取/Electron/npm/原生模块辅助
│   ├── patch-update-check.cjs            # 更新检测固定走 Windows 版本流（幂等）
│   ├── minimax-code-launcher             # /opt/minimax-code/bin/minimax-code
│   ├── minimax-code.desktop
│   ├── minimax-code-postinst             # chrome-sandbox 4755
│   └── minimax-code-postrm
├── .cache/                               # Electron zip/解包、npm 包、编译好的原生模块
├── .migrate/                             # 解包树、app 树、stage（可随时删）
└── dist/                                 # 交付物 *.deb
```

## 持续移植（换 Windows 包即可）

新版发布后只需要：

```bash
cp "MiniMax Code Setup <新版本>-x64.exe" win/
scripts/build-deb.sh
```

脚本自动完成：

1. 取 `win/` 下**最新**的 `*.exe`，NSIS 两段式解包
   （exe → `$PLUGINSDIR/app-64.7z` → 应用目录）；用 `.source-stamp` 判断是否需要重解。
2. 从 `app.asar/package.json` 读取版本号（不硬编码）。
3. 从 `MiniMax Code.exe` 内嵌的 `Chrome/... Electron/<ver>` 字符串读取 Electron 版本，
   下载同版本 Linux 运行时；可用 `ELECTRON_VERSION=42.11.16` 覆盖。
4. 迁移 `resources/`、重打包 asar、注入 Linux 原生模块、生成 deb。

旧 exe 不需要手动删除；脚本按文件 + 时间戳选择最新包。产物名始终是
`dist/minimax-code_<win版本>_amd64.deb`。

## 构建依赖

```
7z unzip dpkg-deb file curl strings convert rsync python3 node npm
g++ make            # 首次编译 node-pty
```

- `asar` 由脚本安装 **@electron/asar@4** 到 `.cache/tools`，不依赖宿主全局版本。
- 构建机若注入 `LD_LIBRARY_PATH`，脚本已用 `run_clean` 清掉再执行 dpkg-deb/curl/xz。
- 首次构建需要网络：Electron zip、better-sqlite3 Electron prebuild、npm 平台包。

## Linux 原生依赖矩阵

| 组件 | 处理 | 说明 |
|------|------|------|
| Electron | 下载 42.11.16 linux-x64 | 二进制改名 `minimax-code`，保证 `app.isPackaged=true` |
| better-sqlite3 12.11.1 | Electron ABI prebuild | 从官方 release 下载 `electron-v<ABI>-linux-x64`，替换 win32 `.node` |
| node-pty 1.1.0 | 源码编译（N-API） | npm 包只有 darwin/win32 prebuilds；编译后放 `prebuilds/linux-x64/pty.node` |
| @vscode/ripgrep | `@vscode/ripgrep-linux-x64` | `rg` 是独立可执行文件，必须 unpack 出 asar 才能执行 |
| @napi-rs/keyring | `keyring-linux-x64-gnu` | 钥匙串（libsecret） |
| @mariozechner/clipboard | `clipboard-linux-x64-gnu` | 剪贴板 |
| node-screenshots | `node-screenshots-linux-x64-gnu` | 截图 |
| @ubjs/node | `node-linux-x64-gnu` | 本地运行时原生依赖 |
| Computer Use (cua-driver) | Linux x64 组件（0.34.1）+ 外置 SDK | 组件、`@trycua/cua-driver` 与 `@ubjs` 放在 `resources/computer-use-sdk`，避免 Electron 从 asar 内加载 `.node`/`.so` |
| abe-broker / session-transfer | **不提供** | 仅 Windows 链路，代码里 `process.platform !== 'win32'` 直接跳过 |
| mcode-tools native/registry | 保留 Windows manifest 原样 | 校验要求资源与 manifest 完全一致；Linux 不加载 registry.node |

原生模块在打包前用 Electron 自身的 Node 运行时做一次加载测试
（`node-pty.spawn` + better-sqlite3 建表），失败即停，避免产出“能装不能跑”的 deb。

## app.asar 重打包的两个坑

1. **必须用 @electron/asar 4.x**。系统自带 asar 3.2.0 打包时会把名为
   `constructor` 的目录整个丢掉，导致 `@sinclair/typebox/build/esm/type/constructor/`
   缺失，本地运行时初始化报
   `Cannot find module .../type/constructor/index.mjs`。
2. Windows 包里部分 **非本平台** 的 unpacked 条目（darwin-arm64 / win32-arm64）
   在 asar 头里标记为 unpacked，但安装包没有携带对应文件，`asar extract` 会整体失败。
   `lib.sh: stub_missing_unpacked` 给这 37 个条目补 0 字节占位，随后随平台目录裁掉。

打包参数：`--unpack '{rg,*.node,*.so,*.dll,*.exe}'`。
`rg` 必须显式加入，否则 ripgrep 可执行文件留在 asar 内无法 spawn。

## 检查更新 = Windows 版本流

`scripts/patch-update-check.cjs`（幂等）在重打包前打 5 处补丁：

| 文件 | 改动 | 目的 |
|------|------|------|
| `electron-updater/out/main.js` | Linux 也实例化 `NsisUpdater` | 不再走 AppImage/DebUpdater |
| `electron-updater/out/AppUpdater.js` | provider `platform=win32` | 请求 `latest.yml` 而非不存在的 `latest-linux.yml` |
| `updater/config.js` | Linux 关闭差量下载 | Windows blockmap 不能跨平台合并 |
| `updater/test-branch.js` | Linux → `win` 目录 | test 分支 feed 对齐 |
| `updater/test-branch-switch.js` | Linux → `test.yml` | 同上 |

效果：版本号取 Windows 的 `latest.yml`；发现新版本时下载的也是
Windows NSIS 安装包（`MiniMax-Code-Setup-<ver>-x64.exe`）。
Linux 上不能就地运行该安装包（electron-updater 的 `autoInstallOnAppQuit=false`，
应用本身也不会在 Linux 上执行 NSIS），升级方式是用下载到的 exe 重跑本脚本。

## Computer Use（Linux）

应用原本只接受 darwin/win32 组件。移植时补了三层：

1. `scripts/patch-computer-use-linux.cjs` 放开平台判断，注入 Linux 组件清单摘要，
   并把 Linux 权限视为 `not-required`。
2. `scripts/build-deb.sh` 使用上游 `cua-driver` 0.34.1 Linux 二进制生成
   `resources/resources/computer-use/0.34.1/linux-x64/` 组件。
3. SDK 复制到 `resources/computer-use-sdk/node_modules/`（`@trycua/cua-driver`、
   `@ubjs/*`、linux-x64 原生包），客户端从真实文件系统导入。否则 Electron 会从
   `app.asar` 内解析 `cua_driver_node_runtime.node` / `libcua_driver_sdk.so` 失败。

验证结果：`getStatus()` 返回 `supported/ready/granted = true`，`app_list` 能返回
本机应用列表。

## 系统托盘（Linux）

Electron 的 Linux 托盘由 StatusNotifierItem/AppIndicator 承载，`click` /
`right-click` 事件不会送达应用，只有 `Tray.setContextMenu()` 设置的菜单会被
桌面环境显示。`scripts/patch-linux-tray.cjs`（幂等）在 `applyTrayBehavior()` 中
对 Linux 直接调用 `setContextMenu(createContextMenu())`，菜单项保持与
Windows/macOS 一致：

- 打开小窗
- 退出

Windows/macOS 仍保留“左键唤起主窗口、右键弹菜单”的原生行为。

## 安装后布局

```
/opt/minimax-code/
├── minimax-code                 Linux Electron（= electron 重命名）
├── minimax-code.png             应用图标
├── chrome-sandbox               postinst 设为 4755 root:root
├── bin/minimax-code             启动包装器（环境清理 + sandbox 回退）
└── resources/
    ├── app.asar                 业务逻辑（Linux 原生模块已换）
    ├── app.asar.unpacked/       pty.node / better_sqlite3.node / rg / 平台 .node
    └── resources/               mcode-tools、pptx-core、model-access-host、图标等
/usr/share/applications/minimax-code.desktop   # 唯一安装在 /opt 之外的文件
```

启动包装器清理 `LD_LIBRARY_PATH/LD_PRELOAD/LD_AUDIT/ELECTRON_RUN_AS_NODE`，
强制 `TMPDIR=/tmp`（避免 SingletonSocket 路径过长），保留
`DBUS_SESSION_BUS_ADDRESS`/`XDG_RUNTIME_DIR`；`chrome-sandbox` 未 setuid 时自动
`--no-sandbox`。

## 验证记录（3.1.16）

```bash
sudo dpkg -i dist/minimax-code_3.1.16_amd64.deb
xvfb-run -a /opt/minimax-code/bin/minimax-code
```

- `dpkg -s minimax-code` → Version: 3.1.16，Installed-Size ≈ 848 MB
- 启动日志：`[Lifecycle] Startup timings {"outcome":"ready","failed_count":0}`
- `[mcode-tools] shared-broker launcher ready ... version=0.0.6`
- 原生模块：`native-ok pty=function sqlite=1`（打包门禁）
- 界面：Xvfb 1440×900 截图正常渲染（首次启动为引导页）
- 登录/OAuth、设备注册、配置拉取均返回 200
- 托盘：KDE StatusNotifier 菜单可读取到「打开小窗 / 退出」，触发「退出」后进程正常结束
- Computer Use：Electron 主进程加载外置 SDK，`app_list` 返回 816 个应用

## 已知降级

- Computer Use：需要可用的 X11/Wayland 桌面会话；若初始化失败，查看 `~/.config/MiniMax/logs/main-computer-use.log`。
- 浏览器配置导入（abe-broker）与会话迁移（session-transfer）：Windows 专属，Linux 静默跳过。
- 检查更新下载的 Windows exe 不能自动安装；需回到 Windows 或在本机重跑移植脚本。
- 用户配置在 `~/.config/MiniMax`，升级 deb 不丢。
