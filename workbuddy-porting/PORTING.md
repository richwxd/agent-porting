# WorkBuddy Windows → Linux 移植（deb 分发，dpkg 升级）

把 WorkBuddy 的 Windows NSIS 安装包 `WorkBuddy-win32-x64-user-<版本>-*.exe` 移植为
Linux deb，安装到 `/opt/WorkBuddy`，通过 `dpkg`/`apt` 安装与升级。**deb 版本号与 Windows
安装包全版本-哈希对齐**（取自 exe 文件名，当前 `5.11.3.43806934-ecace0f7`——Debian 把最后一个
`-` 后当 revision，版本比较仍正确：`5.11.3.43806934-ecace0f7 > 5.11.3`），Electron 与
Windows 包内置严格一致（**37.10.3**，读 `winapp/version`）。

**升级检测始终按 Windows 版本通道**（win32-x64-user），点击更新触发**下载**；
版本诚实上报（5.11.3 → feed 204「已是最新」，不误弹）——见「升级检测」一节（3 处补丁）。

## 项目结构

```
workbuddy-porting/
├── win/                      # 放入 WorkBuddy-win32-x64-user-<版本>-*.exe（NSIS 安装包）
├── scripts/
│   ├── migrate.sh            # 一键迁移：构建 → 校验 → 安装（--no-install / --smoke）
│   ├── build-deb.sh          # 一键构建入口（仅构建，8 步）
│   ├── lib.sh                # 公共函数（解包/版本识别/迁移/注入/打包）
│   ├── patch-update-check.sh # 升级检测 3 补丁（A 通道/B url/C 下载）
│   ├── verify-deb.sh         # 产物校验（关键文件、Linux 原生件、3 补丁字节断言）
│   └── smoke-test.sh         # 安装 + 启动 + 升级检测日志检查
├── dist/                     # 产物 deb
├── .cache/                   # 下载缓存（Electron/官方 deb，可删）
├── .migrate/                 # 中间产物（解包源 winapp、stage，可删）
└── PORTING.md
```

## 快速开始（升级流程）

1. 放入输入文件：

   ```
   win/WorkBuddy-win32-x64-user-<版本>-*.exe   必须
   electron-v37.10.3-linux-x64.zip             可选，放项目根或 .cache/
                                                （缺失时自动下载 + SHASUMS256 校验）
   ```

2. 一条命令迁移（构建 → 校验 → dpkg 安装/覆盖升级）：

   ```bash
   ./scripts/migrate.sh               # 完整一键
   ./scripts/migrate.sh --no-install  # 只构建 + 校验
   ./scripts/migrate.sh --smoke       # 追加冒烟（启动 + 升级检测日志）
   ```

   包名与官方 Linux 包一致（`workbuddy`），覆盖升级自动进行；用户配置不丢。
   分步等价于：

   ```bash
   ./scripts/build-deb.sh    # 构建（版本号全部动态匹配，无需手填）
   ./scripts/verify-deb.sh   # 关键文件 + ELF + 3 补丁字节断言
   sudo dpkg -i dist/workbuddy_<版本>_amd64.deb
   ./scripts/smoke-test.sh   # 安装 → 启动 → 等升级检测（约 30s 首查）→ 汇报日志
   ```

> 版本号全部自动跟随 Windows 包：**deb Version ← exe 文件名全版本-哈希**
> （`WorkBuddy-win32-x64-user-5.11.3.43806934-ecace0f7.exe` → `5.11.3.43806934-ecace0f7`，
> 兜底 `app.asar` 内 `package.json` 的 3 段版本）；Electron ← `winapp/version` 首段
> （`37.10.3-43` → **37.10.3**）；官方 deb ← linux feed
> 动态解析（版本/下载地址/sha256 一次取回，缓存按 sha 校验）。换 exe 后版本戳变化自动重解包。

## 升级检测：按 Windows 版本通道，点击触发下载

原版 `UpdateServiceLinux` 走 `linux-x64-deb` 通道（实测只到 **5.6.2**，比 Windows 落后
5 个大版本），且 `updateInfo` 不带下载地址、点击更新只会打开官网首页。
`patch-update-check.sh` 按序号定点替换，每处断言唯一出现（可重跑，幂等）：

| # | 原样行为（Linux） | 补丁后 | 效果 |
|---|---|---|---|
| A | `getPlatformAssetId()` 返回 `linux-x64-deb` | 固定返回 `win32-x64-user` | feed 拼出 `platform=workbuddy-win32-x64-user`，拿 Windows 侧最新版 |
| B | `available` 的 updateInfo 不带 `url` | 插入 `url:l.url` | 点击时能拿到下载地址 |
| C | `openUpdateDestination()` 打开官网首页 `https://www.codebuddy.cn/work/` | 打开前把 `officialDownloadUrl` 覆盖为 feed 的 `url` | **点击更新 → 浏览器下载 Windows 安装包** |

（原补丁 D「`this.version` 固定 5.11.2 使 feed 恒 200」**已移除**：它导致每次检查都
弹「发现新版本 V5.11.3」——而本包本就是 5.11.3，误报。现走诚实检查。）

补丁链路（字节级确认）：
renderer `update-toast` 按钮发 `quit-and-install` → `handler-registry updateQuitAndInstall` →
`UpdateServiceLinux.quitAndInstall()` → `openUpdateDestination()` →
`LinuxExternalUpdateOpener.open()`（`official-website` 分支）→ `shell.openExternal(url)` →
浏览器下载 `WorkBuddy-win32-x64-user-*.exe`。

feed 实测（`GET https://copilot.tencent.com/v2/update`，2026-11）：

| platform + version | 返回 | 说明 |
|---|---|---|
| `workbuddy-win32-x64-user` + `5.11.3` | **204** | 已是最新（服务端 3 段比较） |
| 同上 + `5.11.2` | **200** → `5.11.3.43806934`，`url=...WorkBuddy-win32-x64-user-5.11.3.43806934-ecace0f7.exe`，`sha256hash=2fd40059...` | 官方发 5.11.4 时的同形响应（客户端报更低版本才触发） |
| `workbuddy-linux-x64-deb` + `0.0.1` | **200** → `5.6.2.40046327` deb | 官方 Linux deb 来源（构建用，落后于 win） |
| `workbuddy-linux-x64-deb` + `5.11.3` | 200 → 5.6.2（低于请求值也返回） | 原样行为为何不能用 |

**更新检查语义**：客户端报 `app.getVersion()`（=5.11.3），feed 对当前版本回 204
「No update available (HTTP 204)」→ 窗口显示已是最新、不弹提示；官方发布 5.11.4 win
包后 feed 回 200 → 弹「发现新版本」，点击走 A/B/C 直接下载安装包。

**未打的补丁**（与 raccoon 移植不同）：本包 win asar 已内置 Linux 分支
（`update-service.linux.js`、`tray-linux*.png`、`linuxPackaged` runtime 软链），无窗口/
托盘/对话框/退出挂起问题的证据 → 不加对应补丁，冒烟验证。

## 脚本做了什么

| 步骤 | 说明 |
|------|------|
| 解包 win/*.exe | NSIS 两段式：`$PLUGINSDIR/app-64.7z` → `.migrate/winapp/`（版本戳缓存，换 exe 自动重解） |
| 版本号 | 应用 ← `app.asar/package.json`（兜底 exe 文件名 3 段）；Electron ← `winapp/version` 首段 |
| 官方 Linux deb | linux feed 动态解析（`version=0.0.1` 探测拿最新 + url + sha256）→ 缓存 `.cache/workbuddy-linux-<ver>.deb` 按 sha 校验 |
| 重命名 electron→workbuddy + 覆盖官方定制主程序 | 让 `app.isPackaged=true`；主程序/`resources.pak`/`libGLESv2.so` 用官方 deb 件（原版 Electron 缺 `electron.workbuddyStorage` → 弹窗+401，见平台依赖矩阵） |
| 迁移 resources | SKIP 剔除 win 专属（见下表）+ 从官方 deb 补 `runtime/`、托盘图、AppArmor profile |
| 重打包 app.asar | 补缺失占位 → 解包 → 叠加 winapp unpacked 真文件 → 注入 7 项 Linux 原生件 → 3 补丁 → `asar pack --unpack-dir '**'`（全量 unpacked） |
| 图标/.desktop/DEBIAN | 官方 hicolor 全尺寸图标、启动包装器、官方 .desktop 改 Exec、postinst/prerm |
| 打包 deb | `dpkg-deb --build --root-owner-group` → `dist/` |

### 平台依赖矩阵

| 组件 | 处理 | 说明 |
|------|------|------|
| Electron | 自动下载 | `winapp/version` = `37.10.3-43` → **37.10.3**（根目录 electron-v45.3.3 zip 版本不符，不用） |
| `workbuddy` 主程序 + `resources.pak` + `libGLESv2.so` | **换官方 deb 的** | 官方定制 Electron 才注入 `electron.workbuddyStorage`（native binding `electron_browser_workbuddy_storage`，凭据 bootstrap 依赖）；原版 Electron 缺失 → main 抛 TypeError → 弹窗「关键组件加载失败」+ 凭据 invalid-key → 全站 401（皮肤/登录名不显示）。与原版仅这 3 个公共文件不同 |
| `resources/runtime/` | **换官方 deb 的** | `linuxPackaged` 布局：`runtime/node`（203M）+ `runtime/python`（393M），VendorAssetEnsure 软链到 binaries |
| `tray-linux*.png` | 取官方 deb 的 | main-bootstrap 托盘引用 |
| `apparmor-profile` | 取官方 deb 的 | 官方 Linux 包独有 |
| `cli/node_modules/@lydell/node-pty-linux-x64` | 官方整包 | winapp 只有 win32 变体；loader 按包名 require（含 package.json） |
| `cli/vendor/ripgrep/x64-linux/{rg,ripgrep.node}` | 官方 | winapp 只有 `x64-win32` |
| `node_modules/node-pty/build/Release/pty.node` | 官方 | node-gyp-build 回退目标，winapp 无 |
| `node_modules/koffi/...` 与 `cli/...` `linux_x64/koffi.node` | 官方（2.16.2 三方一致） | winapp 的 linux_x64 目录为空（win 构建剔除）；cli 侧用官方根 koffi 交叉拷 |
| `@tencent/qimei-node .../qimei.node` | 官方（1.2.2 一致） | winapp 是 `qimei.dll` 版 |
| `node_modules/@lydell/node-pty-linux-x64`（根） | **不拷** | winapp 已有且同版本（75,976 B），避免被官方 5.6.2 旧版覆盖 |
| better-sqlite3 | **不补** | win 5.11.3 的 asar 里没有（官方 5.6.2 才有）→ winapp 不用 |
| `vendor/` `qm/` `scripts/` `elevate.exe` `qimei.dll` `workbuddy-editor-sdk-supervisor.exe` | 剔除 | 全是 win 运行时/更新流专属（grep 证据：仅 `update-service.win32.js` 等引用；官方 Linux deb 也不带） |
| `file-icons/` `wb-guest-sdk/` | 保留 | 跨平台资源（file-icons 被 office-file-association-repair 引用） |
| `.node` 等原生件 | 全量解到 `app.asar.unpacked` | 原包 4000+ 非二进制文件也 unpacked → `--unpack-dir '**'` 超集安全 |

## app.asar 重打包机制（`lib.sh: repack_asar`）

1. **占位**：asar 头枚举「unpacked 且 winapp 磁盘缺失」的文件（61 个，如 2 个 media
   mp4、darwin prebuilds），写 0 字节 stub + 清单 `.migrate/stub-list.txt`，否则 `asar extract` 中断。
2. **解包**：`asar extract`（旁边需 winapp `app.asar.unpacked` 供 unpacked 文件读取）。
3. **删占位**：两侧同删（空文件不进新包；winapp 侧下次构建重新枚举）。
4. **叠加**：`cp -an winapp/app.asar.unpacked/. tree/` —— asar header 没有的 325 个真文件
   （`main/preload/background-worker.cjs`、`fork-preload.cjs`、im-channels lib、`ImSDK.dll` 等）。
5. **注入 Linux 原生件**：7 项白名单（见平台依赖矩阵），`die` 校验源存在。
6. **补丁**：`patch-update-check.sh`（A/B/C）。
7. **重打包**：`asar pack tree app.asar --unpack-dir '**'` —— 全部 unpacked（含 `package.json`），
   app.asar 只剩 header，内容在 `app.asar.unpacked/`。**verify 的字节断言因此读
   `app.asar.unpacked/main/*.js`，不读 app.asar。**

## 安装后布局

```
/opt/WorkBuddy/                自包含主程序
├── workbuddy                  定制 Linux Electron（官方主程序，含 workbuddyStorage 绑定）
├── chrome-sandbox             postinst 设为 4755（无 userns 时）
├── version                    37.10.3（原版 Electron 运行时）
├── resources/
│   ├── app.asar               业务逻辑（header，内容全 unpacked）
│   ├── app.asar.unpacked/     全部真实文件 + 3 补丁 + Linux 原生件
│   ├── runtime/               node + python（VendorAssetEnsure 软链目标）
│   ├── tray-linux*.png  apparmor-profile   官方 Linux 资源
│   ├── file-icons/ wb-guest-sdk/ licenses/ ...  跨平台业务资源
│   └── （无 vendor/qm/scripts/elevate.exe —— win 专属已剔除）
/usr/bin/workbuddy             启动包装器（排除有害 env）
/usr/share/applications/workbuddy.desktop
/usr/share/icons/hicolor/*/apps/workbuddy.png
```

## 启动包装器排除的环境变量（防启动失败）

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

asar: `npm i -g asar` 或 `npx @electron/asar`（`lib.sh` 用 PATH 上的 `asar`）。

> 构建机宿主会注入 `LD_LIBRARY_PATH` 干扰 `dpkg-deb`/`xz`/`curl`/`7z`，脚本入口统一
`unset` + `run_clean env -u` 双保险，无需手动处理。

## 环境变量覆盖

均为可选显式指定，不设置时全部动态匹配：

```bash
ELECTRON_VERSION=37.10.3       # 强制 Electron 版本（默认读 winapp/version）
./scripts/build-deb.sh
```

## 卸载

```bash
sudo apt remove workbuddy
```
