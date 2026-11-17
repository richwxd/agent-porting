# 商汤小浣熊 Windows → Linux 移植（deb 分发，dpkg 升级）

把商汤小浣熊（office-raccoon / Raccoon Work）的 Windows NSIS 安装包
`商汤小浣熊-<版本>-x64.exe` 移植为 Linux deb，安装到 `/opt/office-raccoon`，
通过 `dpkg`/`apt` 安装与升级。版本号与 Windows 包一致（当前 1.2.1），
**应用/Electron/官方 deb 三个版本号默认全部随 Windows 包动态匹配**（见「脚本做了什么」）。

**升级检测始终按 Windows 版本**——见下面「升级检测」一节。

## 项目结构

```
raccoon-porting/
├── win/                      # 放入 商汤小浣熊-<版本>-x64.exe（NSIS 安装包）
├── scripts/
│   ├── migrate.sh            # 一键迁移：构建 → 校验 → 安装（--no-install / --smoke）
│   ├── build-deb.sh          # 一键构建入口（仅构建）
│   ├── lib.sh                # 公共函数（解包/迁移/注入/打包）
│   ├── patch-update-check.sh # 升级检测 4 补丁（始终按 Windows 版本）
│   ├── patch-window-linux.sh # 窗口/任务栏图标/菜单栏 3 补丁
│   ├── patch-tray-linux.sh   # Linux 系统托盘 4 补丁（关窗隐藏到托盘，托盘可显示/退出）
│   ├── patch-dialog-parent.sh # 原生文件对话框去 parent window 9 补丁（Wayland 挂死）
│   ├── patch-workspace-open-linux.sh # "打开当前目录"卡死 4 补丁（4 处 shell.openPath → fire-and-forget）
│   ├── patch-quit-timeout-linux.sh # 托盘/窗口"退出"挂起 1 补丁（清理超时强制退出）
│   ├── verify-deb.sh         # 产物校验（关键文件、平台替换、4+3+4+2+1 补丁、无残留 .node）
│   └── smoke-test.sh         # 安装 + 启动 + 升级检测日志检查
├── dist/                     # 产物 deb
├── .cache/                   # 下载缓存（Electron/官方 deb/pandoc，可删）
├── .migrate/                 # 中间产物（解包源、stage，可删）
└── PORTING.md
```

## 快速开始（升级流程）

1. 放入输入文件：

   ```
   win/商汤小浣熊-<版本>-x64.exe      必须，例如 win/商汤小浣熊-1.2.2-x64.exe
   electron-v<版本>-linux-x64.zip     可选，放项目根目录或 .cache/（放了就用、
                                       不会被删除；缺失时自动下载并按 SHASUMS256 校验）
   ```

2. 一条命令迁移（构建 → 28 项校验 → dpkg 安装/覆盖升级）：

   ```bash
   ./scripts/migrate.sh               # 完整一键
   ./scripts/migrate.sh --no-install  # 只构建 + 校验
   ./scripts/migrate.sh --smoke       # 追加冒烟（启动 + 升级检测日志）
   ```

   包名与官方 Linux 包一致（`raccoon-ai`），覆盖升级自动进行；用户配置在
   `~/.config/` 下，升级不丢。分步等价于：

   ```bash
   ./scripts/build-deb.sh    # 构建（三个版本号全部动态匹配，无需手填）
   ./scripts/verify-deb.sh   # 29 项断言：关键文件、平台替换、4+3+4+2+1 补丁、无残留 .node
   sudo dpkg -i dist/raccoon-ai_<版本>_amd64.deb
   ./scripts/smoke-test.sh   # 安装 → 启动 → 等升级检测 → 汇报 raccoon.log
   ```

> 版本号全部自动跟随 Windows 包，无需手填：应用版本 ← `app.asar` 的 `package.json`；
> Electron ← `app.asar` 内 pnpm 依赖路径 `..._electron@<版本>`（本工程识别为 **41.0.1**，
> 与内置严格一致，下载时按官方 `SHASUMS256.txt` 校验）；官方 deb ← 精确同名 →
> `latest-linux.yml` 最新 → 1.0.38 兜底。换 exe 后版本戳变化会自动重新解包。
> 只有识别失败时才需显式覆盖：`ELECTRON_VERSION=x.y.z ./scripts/build-deb.sh`。

## 升级检测：始终按 Windows 版本

原版代码按 `process.platform` 走 Linux 分支，有四个问题，补丁全部改回 Windows 路径（脚本按序号执行，逐处断言唯一出现）：

| # | 原样行为（Linux） | 补丁后 | 补丁脚本 |
|---|---|---|---|
| ① | 版本策略接口带 `platform=linux` | 固定 `platform: "win32"` → 服务端按 Windows 口径回答 | `patch-update-check.sh` |
| ② | electron-updater 选 `AppImageUpdater`：非 AppImage 环境 `isUpdaterActive()=false`，检查被**静默跳过** | Linux 也用 `NsisUpdater`（Windows 更新器） | 同上 |
| ③ | `autoDownload` 默认开 → 自动下载 Windows `.exe`（Linux 装不了，白下 400MB+） | 默认关（用户手动点下载仍可） | 同上 |
| ④ | provider 的 `platform=linux` → 通道名变成 `latest-linux.yml`，Windows feed 上没有 → **404，检查必失败** | provider `platform` 固定 `win32` → 读 `latest.yml` | 同上 |

feed 本身**原样复用 Windows 的 `resources/app-update.yml`**：

```
provider: generic
url: https://sta-volc.xiaohuanxiong.com/office-agent/win
updaterCacheDirName: '@raccoonoffice-desktop-updater'
```

实测（2026-11-15）：

| 请求 | 返回 | 说明 |
|------|------|------|
| `POST /api/web/client/v1/version_policy` `platform=windows` | `v1.0.37` | 补丁①后客户端拿到的口径 |
| 同上 `platform=linux` | `v1.0.28` | 原样行为：明显落后（且历史上该口径会报「请求参数错误」） |
| `GET .../office-agent/win/latest.yml?noCache=…` | **`1.2.1`**，条目 `商汤小浣熊-1.2.1-x64.exe` | 补丁④后 electron-updater 实际读到的真值 |
| 同上、**不带** `noCache` | `1.0.38` | CDN 边缘缓存的旧值——裸 `curl` 会看到它，别误判 feed 没更新 |

> electron-updater 每次请求通道文件都会带 `?noCache=<时间戳>`（`isAddNoCacheQuery`），
> 因此**应用拿到的永远是源站真值**；手工 curl 不带参数时看到的是边缘缓存。

冒烟日志（`scripts/smoke-test.sh`，1.2.1 实测）：

```
Checking for update
Update for version 1.2.1 is not available (latest version: 1.2.1, downgrade is disallowed).
```

→ 按 Windows 口径正确判定「已是最新」：无 404、无 `latest-linux.yml`、无历史「请求参数错误」。

**限制**：升级*检测*按 Windows 版本；检测到的新版本其下载包是 Windows `.exe`，
在 Linux 上无法安装（`autoInstallOnAppQuit` 本来就是 `false`，点「下载」会取到
exe、安装步骤不适用）。Linux 原生升级请以官方 `linux/x64` feed 为准，本工程不切换。

## 脚本做了什么

| 步骤 | 说明 |
|------|------|
| 解包 win/*.exe | NSIS 两段式：`$PLUGINSDIR/app-64.7z` → `.migrate/winapp/`（保留作输入） |
| 版本号 | 从 `app.asar` 内 `package.json` 读取（兜底：exe 文件名）；按版本戳缓存解包，换 exe 自动重解 |
| Electron | 版本从 `app.asar` **动态识别**（pnpm 路径 `_electron@x.y.z`，当前 41.0.1）→ `.cache/` 缺则下载 + SHASUMS256 校验 |
| 官方 Linux deb | 版本**动态匹配**：精确同名 `商汤小浣熊-<winver>-amd64.deb` → `latest-linux.yml` 最新（当前 1.2.0）→ 1.0.38 兜底；作 **Linux 原生依赖唯一来源** |
| 重命名 electron→raccoon-ai | 让 `app.isPackaged=true`，避免 dev 分支走错误入口 |
| 迁移 resources | 跨平台目录原样拷；平台专属换 Linux 版（见下表） |
| 重打包 app.asar | 打补丁①②③④ + A/B/C + D → 注入 `@esbuild/linux-x64` → `.node`/esbuild 解到 `app.asar.unpacked` |
| 图标/.desktop/DEBIAN | 官方 hicolor 全尺寸图标、启动包装器、以官方 .desktop 为底改 Exec、postinst/prerm |
| 打包 deb | `dpkg-deb --build --root-owner-group` → `dist/`，清除 stage |

### 平台依赖矩阵（Windows 包缺的/多的，怎么处理）

| 组件 | 处理 | 说明 |
|------|------|------|
| Electron | 自动下载 | 版本从 Windows 包动态识别，必须与内置一致（当前 41.0.1） |
| `box-agent-runtime/` | **换官方 Linux 版** | Windows 是冻结 Python（`.exe/.pyd/.dll` 7614 个文件）；官方 deb 提供 0.9.8 linux 构建 |
| `rg/` | 换官方 Linux 版 | Windows 只有 `rg.exe` |
| `pandoc/` | 换 Linux 静态版 | `pandoc.exe` → `pandoc`（3.7.0.2，自动下载） |
| `@napi-rs/canvas` | 换官方 linux-x64-gnu | `render-node-deps` 里两处（根 + `pdfjs-dist` 内），另有 `skia.*.node` |
| `@esbuild/linux-x64` | 注入官方 deb 的 | Windows 包只有 win32-x64；`tsx` 跑 TS 脚本要用 |
| `assets/icon.png` | 取官方 deb 的 256px | 窗口/任务栏图标（Wayland 不吃 `.ico`） |
| `7za/`、`elevate.exe` | 跳过 | Windows 专属（UAC 提权、SFX 解压），Linux 无对应流程 |
| `.node` 原生模块 | 解到 `app.asar.unpacked` | asar 内无法 dlopen |
| `app.asar.unpacked`（Windows 的） | 不拷 | 由 `asar pack` 按 Linux 内容重新生成 |

## 窗口与标题栏（`patch-window-linux.sh`）

- **图标**：`resolveTrayIconPath()` 原本只有 win32/darwin 分支，Linux 返回 `null`
  → 任务栏/Alt-Tab 显示 Electron 默认图标。补 linux 分支读
  `resources/assets/icon.png`，并把主窗口 `icon` 的解析条件改成 `win32 || linux`。
- **标题栏不动**：官方 Linux 构建 `getWindowsTitleBarWindowOptions()` 对非 win32
  一律返回 `{}`，即**保留系统原生标题栏**（KDE 下按钮/拖动正常），本工程同样不改。
  （曾试过无边框+自绘三按钮，需要 preload 桥注入，维护成本高、跨版本易碎。）
- **中文菜单栏（补丁C）**：本应用从不 `setApplicationMenu`，Linux 上会露出 **Electron 41
  自带的英文默认菜单** File/Edit/View/Window/Help（裸 Electron 实测即如此）。Windows 分支
  靠 `window.setMenu(null)` 隐藏；Linux 补丁改为注入**官方同款中文菜单**（内容照抄官方 Linux 版
  `setupMenu()` 模板，**布局紧简化**：去掉官方顶栏三空格边距与 `(&X)` 助记符）：文件(退出)/
  编辑(撤销…全选)/查看(重新加载…全屏)/窗口(最小化、关闭)/帮助(关于)。role 自带加速键
  （Ctrl+C/V/A、Ctrl+R、F11、Ctrl+Shift+I，Electron 41 实测）；关于 = `dialog.showMessageBox`
  （商汤小浣熊 v<版本>，detail 沿用官方 "A powerful AI-assisted editor"）。
  - Xvfb 实测确认时序安全：**先建窗、后 `setApplicationMenu` 对已存在窗口立即生效**
    （同一窗口 id：前=英文默认、后=中文），故注入点留在主窗口初始化处即可。
  - 注：官方模板本身没有「帮助」菜单（关于在「文件」下），此处按需求单列「帮助」、
    「关于」放其下；本包 `raccoonSignedRelease=true` → devtools 策略运行时会剥掉
    「开发者工具」项，属预期。
- **托盘（补丁E，`patch-tray-linux.sh`）**：原代码 `setupWindowsTray()` 是 win32-only
  （`process.platform !== "win32"` 直接 return），`close` 事件也只对 win32/darwin 有托盘时
  隐藏到托盘，`window-all-closed` 无条件 `app.quit()` → Linux 上**关窗即整个退出**、
  无托盘、无后台进程。本工程把门控放宽为 `win32 || linux`，并让 `close` 事件在 Linux 有
  托盘时也 `hideWindowToTray()`（而非 `app.quit()`）；`window-all-closed` 仅在**无托盘**
  时退出（托盘创建失败兜底，避免无头僵尸进程）。行为：点窗口 X → 隐藏到托盘继续后台
  运行，托盘单击显示主界面，右键菜单「显示主界面 / 退出」。图标走 `resolveTrayIconPath`
  的 linux 分支（`resources/assets/icon.png`，patch-window-linux 已迁入）。
  - `setupMenuBarShortcut`（darwin 菜单栏专用）**不改**，macOS 行为不受影响。
  - 注：Linux 托盘图标用 `icon.png`（1024×1024，Tray 自动缩放）；KDE 托盘单击/右键
    行为由 Electron 的 `tray.on("click")` + `setContextMenu` 提供。

## 原生文件对话框（`patch-dialog-parent.sh`）

- **问题**：Electron 在 Linux 的 `dialog.showOpenDialog(win, ...)` / `showSaveDialog(win, ...)`
  传 parent window 时，把窗口的 Wayland surface 句柄传给 XDG portal 作为
  `parent_window`（`file_dialog_linux_portal.cc`）；在 Wayland 下该句柄解析失败/为空，
  portal 后端报 "Unhandled parent window type" / "Failed to associate portal window with
  parent window"，**对话框不显示、Promise 永不 resolve** → 主界面被模态禁用，
  表现为「点『选择项目目录』后无法关闭/返回主界面」。
- **复现**（Electron 41.0.1，KDE Wayland **和** Xvfb X11 都复现）：
  - 带 parent：`OPENING_DIALOG...` → 45s 超时，never resolved（挂死）
  - 不带 parent：`OPENING_DIALOG_NO_PARENT...` → 4.8s 后 `DIALOG_RESOLVED {canceled:true}`
    （锁屏自动取消；未锁屏时用户正常点选返回路径）
  - `showMessageBox(win, ...)` 带不带 parent 都正常（~1s），不改。
- **修复（补丁D）**：去掉第一参数 parent window → `showOpenDialog({...})`。
  共 9 处（5 处 `showOpenDialog` + 4 处 `showSaveDialog`，含 `import_electron5` 的
  export-logs）。代价是对话框不再严格模态（不锁主窗口），但 KDE portal 对话框默认浮层
  置顶，可见性不受影响；挂死比非模态严重得多。
- **验证**：`showOpenDialog(window2,` / `showSaveDialog(window2,` 在产物中必须为 **0 次**；
  `showOpenDialog( {`=5、`showSaveDialog( {`=4。已加进 `verify-deb.sh` 补丁D 断言。

## "打开当前目录"卡死（`patch-workspace-open-linux.sh`）

- **症状**：任务工作区选择器里点「打开当前目录」/「在资源管理器中打开」（openerId=system），
  文件管理器弹出后**程序界面无法操作**，关闭文件管理器也收不回状态。
- **根因**：主进程 **4 处 IPC handler / dispatch 内 `await electron.shell.openPath(path)`**。
  **实测（Electron 41.0.1 / KDE Wayland）：`shell.openPath()` 的 Promise 永不 resolve（挂起）**
  ——内部经 xdg-open/gio 启动文件管理器后，resolve 依赖的内部回调在 Wayland 下不触发。
  对照 `shell.openExternal()` 正常。
- **链路**（以「打开当前目录」按钮为例）：
  - 前端按钮 `onClick` → `S(() => desktopClient.openTaskWorkspace({workspaceId}))`
    —— `S` 是 busy 控制函数：`j.busy=!0; u(!0)`（进入"禁止输入"）→ `await t()` → `finally{ j.busy=!1; u(!1) }`。
  - 主进程 `desktop-client:open-task-workspace` handler（`registerWorkspaceHandlers.js`）内
    `await shell.openPath(directory)` **挂起** → IPC `ipc.invoke` 永不返回。
  - 前端 `S` 的 `await t()` 永不完成 → `finally` 永不执行 → `u(!1)` 永不调用 →
    **界面永久"禁止输入"**（文件管理器已弹出，但界面收不回状态）。
  - 同理 `render-runtime:open-runtime-directory`（`registerRuntimeHandlers.js`）、
    浏览器"在资源管理器中打开"（`embeddedBrowser.js`）的 `await shell.openPath` 也会锁界面。
- **修复（补丁F，4 处）**：全部改为 **fire-and-forget**：`shell.openPath(path).catch(() => {})`
  不 await，dispatch 成功即立即返回（文件管理器在后台打开），IPC 立即返回，前端 `finally`
  执行、`u(!1)` 恢复，界面立即恢复。仅 Linux 生效（`process.platform !== "linux"` 时原样返回），
  Windows/macOS 行为不变。
  1. `build/electron/main/workspace/directoryOpeners.js` — `openDirectoryWithOpener` system 分支
     （"在资源管理器中打开"/文件动作菜单）
  2. `build/electron/main/client/workspace/registerWorkspaceHandlers.js` — **「打开当前目录」按钮**
     （`desktop-client:open-task-workspace`）
  3. `build/electron/main/client/bootstrap/registerRuntimeHandlers.js` — 渲染组件"打开目录"
     （`render-runtime:open-runtime-directory`）
  4. `build/electron/main/client/browser/embeddedBrowser.js` — 浏览器"在资源管理器中打开"
     （`BROWSER_EXTERNAL`）
- **验证**：`shell.openPath(...).catch(() => {})` 各 1 次（4 处）+ 否定断言 IPC handler 内
  无残留 `await ... openPath`；已加进 `verify-deb.sh` 补丁F 断言（正向 4 + 否定 3）。
  实测构建后 verify 全绿，冒烟启动正常。

## 托盘/窗口"退出"挂起（`patch-quit-timeout-linux.sh`）

- **症状**：系统托盘右键菜单点「退出」（或窗口关闭触发 quit）后，**应用未真正退出**，
  主进程与后台进程（box-agent 等）仍存活，界面无反应。
- **根因**：托盘「退出」项 `click: () => app.quit()` → `before-quit` 被 `shutdown.beforeQuit`
  拦截（`event.preventDefault()`）→ 走 `shutdown.quit()` → `await close()`。
  **Linux 下 `createClientShutdown` 的 `close()` 走 `!bounded` 分支（无超时）**——`SHUTDOWN_TIMEOUT_MS`
  只用于 win32/darwin。`options.close()` 串行清理资源，实测**卡在 `agent-host` 的
  `host.close()`（永不 resolve）**，日志停在 `cleanup started { resource: 'agent-host' }`，
  进程仍存活（实测 PID 50 分钟后仍 `Sl` 状态）。
- **链路**：`app.quit()` 被 beforeQuit 拦截 → `quit()` → `await close()`（Linux 无超时）→
  `options.close()` 清理挂起 → `close()` 永不完成 → `quit().then` 永不执行 → `options.quit()`
  （真正的 `app.quit()`）永不调用 → 进程不退出。
- **修复（补丁G）**：`quit()` 启动清理后设 **8 秒强制退出兜底** `quitForceTimer`：
  若清理挂起（`quitAllowed` 未置位）→ `options.forceQuit()`（`app.exit(0)`）强制退出。
  正常路径不受影响：`close()` 完成后 `clearTimeout`，`catch` 里也 `clearTimeout`（允许重试）。
- **验证**：`const quitForceTimer = setTimeout(() => {` 定义 1 次 + `clearTimeout(quitForceTimer)` 2 次
  （then+catch）；已加进 `verify-deb.sh` 补丁G 断言。实测日志证明 `agent-host` 清理挂起为根因。

## 安装后布局

```
/opt/office-raccoon/             自包含主程序
├── raccoon-ai                   Linux Electron（= electron 重命名）
├── chrome-sandbox               postinst 设为 4755（无 userns 时）
├── resources/
│   ├── app.asar                 官方业务逻辑 + 本工程补丁
│   ├── app.asar.unpacked/       .node 原生模块 + @esbuild/linux-x64
│   ├── app-update.yml           **Windows feed**（升级检测按 Windows 版本）
│   ├── box-agent-runtime/       官方 Linux 版 agent 运行时
│   ├── rg/rg、pandoc/pandoc     Linux 版检索/转换工具
│   ├── render-node-deps/        含 linux-x64-gnu canvas
│   ├── assets/                  icon.ico + icon.png + menu-bar-raccoon.png
│   └── browser-tools/ connectors/ conversation-skills/ ...   跨平台业务资源
/usr/bin/raccoon-ai              启动包装器（排除有害 env）
/usr/share/applications/raccoon-ai.desktop
/usr/share/icons/hicolor/*/apps/raccoon-ai.png
```

## 启动包装器排除的环境变量（防启动失败）

`/usr/bin/raccoon-ai` 在 exec 前排除宿主环境里会导致启动失败的变量：

| 变量 | 危害 |
|------|------|
| `LD_LIBRARY_PATH` / `LD_PRELOAD` / `LD_AUDIT` | 注入的错误 libstdc++ → GPU LAUNCH_FAILED |
| `ELECTRON_RUN_AS_NODE` | 让 Electron 当 node 跑，窗口起不来 |
| `ELECTRON_ENABLE_LOGGING` / `ELECTRON_DEBUG_NOTIFICATIONS` | 干扰启动 |
| `CHROME_DEVEL_SANDBOX` / `CHROMIUM_FLAGS` / `SANDBOX_LD_AUDIT` | 污染 Chromium 沙箱 |
| `TMPDIR`（强制 `/tmp`） | 深路径 → SingletonSocket FATAL |

## 构建依赖

```
7z(p7zip-full)  unzip  dpkg-deb  file  curl  asar  python3  tar  sha256sum
```

asar: `npm i -g @electron/asar`。

> 构建机上 Hermes Agent 会注入 `LD_LIBRARY_PATH` 干扰 `dpkg-deb`/`xz`/`curl`/`7z`，
> 脚本已用 `env -u LD_LIBRARY_PATH -u LD_PRELOAD` 包裹系统命令，无需手动处理。

## 环境变量覆盖

均为**可选的显式指定**——不设置时版本号全部按 Windows 包动态匹配
（`lib.sh: resolve_versions`）：

```bash
ELECTRON_VERSION=41.0.1 \      # 强制 Electron 版本（默认从 app.asar 识别）
OFFICIAL_DEB_VERSION=1.2.0 \   # 强制官方 Linux deb（默认 精确同名→feed 最新→1.0.38）
PANDOC_VERSION=3.7.0.2 \
./scripts/build-deb.sh
```

## 卸载

```bash
sudo apt remove raccoon-ai
```
