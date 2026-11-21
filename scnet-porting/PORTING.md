# SCNet 计算服务客户端 Windows → Linux 移植（deb 分发，dpkg 升级）

把 `win/` 里的 Windows 绿色版（Electron 壳 + `resources/`，或直接放 NSIS 安装包 `SCNet-4.1.0-x64.exe`，构建时自动解包）重打包为自包含 `/opt/scnet-client` 的 Linux deb。应用本体是预构建产物（asar 内无 TS 源码，`package.json` 的 `main` 指向编译好的 `dist-electron/main/index.js`），移植不需要源码。Windows 侧更新 = 换 `win/` 重跑一条命令，dpkg 直接覆盖升级。

## 项目结构

```
scnet-porting/
├── win/                        # 输入：Windows 绿色版（计算服务.exe + resources/）或 NSIS 安装包 exe，整体替换，不入库
├── scripts/
│   ├── build-deb.sh            # 一键构建：win/ → dist/scnet-client_<ver>_amd64.deb
│   ├── lib.sh                  # 构建辅助函数（与 raccoon/loomy 共享约定）
│   ├── scnet-client-launcher   # 启动包装器（装到 /opt/scnet-client/bin/scnet-client）
│   ├── scnet-client.desktop
│   ├── scnet-client-postinst / scnet-client-postrm
│   └── icons/scnet-client-{16..512}.png
├── .cache/                     # 注入集 / linux 平台二进制 / Electron 运行时（可重建，不入库）
├── .migrate/                   # 构建中间产物（app 树、deb stage），不入库
└── dist/                       # 输出 deb，不入库
```

## 快速开始（升级流程）

1. 用新版 Windows 绿色版**整体替换** `win/`（保持 `win/resources/app.asar` 就位）；直接放 `SCNet-<ver>-x64.exe` 安装包也行——检测到缺 `resources/` 时 `build-deb.sh` 自动 7z 两段式解包到 `.migrate/win-app`（每次重建，换 exe 不残留旧 `resources/`）
2. `./scripts/build-deb.sh`
3. `sudo dpkg -i dist/scnet-client_<ver>_amd64.deb`

版本号自动从 `app.asar` 的 `package.json` 读取，deb 文件名与 control 一致。

## 脚本做了什么

0. **输入解包**：`win/resources/app.asar` 缺失且 `win/` 下有 exe 时，`7z x` 解 NSIS 外层 → 插件目录里的 `app-64.7z` → 应用目录（每次重建 `.migrate/win-app`）。
1. **Electron Linux 运行时**：`prepare_electron`（lib.sh）→ 优先 `.cache/electron-v45.2.3-linux-x64/` 已解包缓存，其次 `.cache/*.zip`，否则镜像下载（npmmirror → huaweicloud → github），并始终用 github 官方 `SHASUMS256.txt` 做 sha256 校验。解包后**二进制改名 `electron` → `scnet-client`**。
2. **resources/ 迁移**：rsync 复制 `win/resources/`，剔除 Windows 平台件（`elevate.exe`、`bin/uv.exe`、`agent-browser/agent-browser.exe` 及原 asar），换入 linux 版 `bin/uv`、`agent-browser/agent-browser`（见平台依赖矩阵）。
3. **app.asar 重打包**：`asar extract` 解出 win 树（自动合并 `app.asar.unpacked`）→ 确定性叠加 `.cache/inject/` 注入集 → 追加 `scripts/linux-window-controls.js` 到 `dist-electron/preload/index.js`（Linux 主窗口右上角最小化/最大化/关闭三按钮；Windows 靠原生 titleBarOverlay，Linux 无 overlay 且 frameless，渲染层自带 WindowTools 只在登录页渲染）→ 追加 `scripts/linux-auto-login.js` 到 preload、`scripts/linux-auto-login-store.js` 到 `dist-electron/main/index.js`（服务端会话约一天失效、401 清 accessToken 后启动逻辑直接 skipped ⇒ 每天要手工登录；注入的 preload 拦截 `auth.login` 存下入参、监听 `auth.session-expired` 并在启动时用 `auth.refresh-snapshot` 探针兜底重登；**safeStorage 是主进程专属模块、preload 取不到**，故加解密放在主进程侧新通道 `scnet-porting:auto-login`，凭据写 `<userData>/auto-login.json` 0600，手工退出后抑制直到下次手工登录；两处都各自 `node --check`）→ `scripts/patch-compaction-summary-budget.cjs` 打 `dist-electron/main/b.js`：自动压缩的摘要输出预算被硬顶 8192 tokens（`tK` 里 `Math.min(t.summaryBudgetTokens??1/0,8192,…)`），长会话摘要必撞 cap（`stopReason=length` → "generation hit the token cap and the summary is incomplete"）→ 压缩失败 → 抛 "Context remains above the safe request budget after compaction"；补丁把硬顶提到 32768（全树仅此 1 处，count≠1 即拒绝改写；`node --check` 复核）→ `asar pack --unpack '**/*.{node,so,dll,exe}' --unpack-dir '**/node-pty/prebuilds'`。产出的 asar 树（路径 + 逐文件 md5）与旧手工流程一致，已验证。
4. **deb 装配**：`/opt/scnet-client` 绿色布局 + desktop + 图标 + DEBIAN（postinst 设 chrome-sandbox setuid 4755 并刷新菜单），`dpkg-deb --root-owner-group` 出包到 `dist/`。

> 历史决策更正：早期方案（DELIVERY.md）用 Node `createPackageWithOptions` 重打包，理由是「CLI --unpack glob 不可靠」。实测 asar CLI v3.2.0 支持 glob 且产出一致，现行流水线用 CLI；Node 打包脚本（pack_linux.js）作废，不再需要。

## 平台依赖矩阵（Windows 包缺的/多的，怎么处理）

| 组件 | Windows（win/ 里的） | Linux 处理 |
| --- | --- | --- |
| uv | `resources/bin/uv.exe` | 换 `.cache/linux-bin/bin/uv`（uv 0.9.1 linux x86_64） |
| agent-browser | `resources/agent-browser/agent-browser.exe` | 换 `.cache/linux-bin/agent-browser/agent-browser`（0.41.2 linux x64） |
| elevate.exe | `resources/elevate.exe` | 删除（提权仅 Windows 需要） |
| 原生模块 | win32-x64-gnu 包 | 注入集放入 linux-x64-gnu 包（canvas/cua-driver/ubjs） |
| node-pty | 无 prebuild | 注入集放入 `prebuilds/linux-x64`（pty.node + spawn-helper；node-pty v1.1.0 × Electron 24.21.0 ABI） |
| Windows 运行库 | d3dcompiler/dxcompiler/vulkan-1 等 dll | 不迁移（Linux 运行时自带 libvk_swiftshader 等） |

## app.asar 注入集（.cache/inject）

win 的 `app.asar` 只带 win32 原生件，且部分 npm 包被裁剪过。构建时确定性叠加 139 个文件：

- `node_modules/@napi-rs/canvas-linux-x64-gnu`（skia.linux-x64-gnu.node）
- `node_modules/@trycua/cua-driver-linux-x64-gnu`（cua_driver_node_runtime.node、libcua_driver_sdk.so）
- `node_modules/@ubjs/node-linux-x64-gnu`（uniffi-runtime-napi.linux-x64-gnu.node）
- `node_modules/node-pty/prebuilds/linux-x64`（pty.node、spawn-helper）
- 12 个被裁剪 npm 包的修复内容（mammoth、minimist、fstream、js-yaml、xml-js、uuid、semver、rimraf、qrcode、nanoid 等的 test/README/package.json，及 `.bin/`、`.package-lock.json`）

**升级客户端时注意**：注入集按 4.1.0 的依赖树固化。若新版 `app.asar` 依赖树变化（原生件版本更新、新增原生依赖），需重建注入集：解包新旧两版 asar 对比，替换对应 linux 包目录；否则原生模块加载失败（常见症状：`Cannot find module ... .node`）。

## 关键移植要点（勿回退）

1. **二进制名 ≠ electron**：`app.isPackaged` 按 `execPath` 文件名判定，不改名会走 dev 分支 → `ERR_INVALID_URL`、skill-storage 报错。
2. **原生模块必须进 `app.asar.unpacked`**：Electron 不能从 asar 内 `dlopen`；`--unpack` glob 必须覆盖 `.node/.so`。
3. **node-pty 的 `spawn-helper` 必须一并放**（linux 上 node-pty 靠它 spawn）。
4. **CLI 入口必须是 `resources/cli/index.js`**（`ELECTRON_RUN_AS_NODE` 无法从 asar 加载入口）。
5. **chrome-sandbox 必须 setuid 4755 root:root**（postinst 设置）。

## 安装后布局

```
/opt/scnet-client/                # 自包含绿色布局（deb 唯一写 /usr 的是下面那行）
├── scnet-client                  # Electron 可执行（原 electron 改名）
├── scnet-client.png              # 图标（512）
├── chrome-sandbox                # postinst 设 4755 root:root
├── bin/scnet-client              # 启动包装器（desktop Exec 指向它）
└── resources/                    # app.asar(+.unpacked) + agent-skills/ cli/ cua/ bin/uv ...
/usr/share/applications/scnet-client.desktop
```

手动启动（等价于点图标）：`/opt/scnet-client/bin/scnet-client`；需要图形会话（DISPLAY 或 Wayland）。
CLI 验证：`ELECTRON_RUN_AS_NODE=1 /opt/scnet-client/resources/cli/index.js status`（预期 `packaged:true`、`state:ready`）。

## 启动包装器排除的环境变量（防启动失败）

- 清 `LD_LIBRARY_PATH`、`LIBGL_DRIVERS_PATH`（打包器注入的 libstdc++ 缺 GPU 驱动符号 → GPU 进程 LAUNCH_FAILED）
- `TMPDIR=/tmp`（SingletonSocket 路径过长 → FATAL: Socket path too long）
- 保留 `DBUS_SESSION_BUS_ADDRESS`（keyring/kwallet）与 `XDG_RUNTIME_DIR`（Wayland socket）；缺省值按当前用户推导（`getent` / `id -u`），不硬编码 uid
- chrome-sandbox 未 setuid 时自动回退 `--no-sandbox`

## 调整 Electron 版本

Electron 版本与 win 包内置版本对应（当前 v45.2.3）。升级客户端后：改 `scripts/build-deb.sh` 顶部 `ELECTRON_VERSION`，删掉 `.cache/electron-v<旧>-linux-x64/` 让脚本重新获取/解包即可。

## 已知限制（预期行为）

- 启动日志出现 `[app.updater] APPIMAGE env is not defined` 与 `startup: update preparation failed`：无害（绿色布局无 AppImage 自更新），可忽略
- 登录前预置资源不可用（服务端下发）
- Windows 绿色版根目录的 `计算服务.exe` 与 Windows 运行库 dll 不迁移

## 构建依赖

- asar CLI v3.2.0、python3、rsync、curl、unzip、dpkg-deb（支持 `--root-owner-group`）
- 重建注入集时才需要 Node.js ≥ 24.18.1（bun ≥ 1.4.0）
- 磁盘：win/ 约 600M + .cache 约 600M + 中间产物约 1.5G

## 已验证清单（KDE Plasma 6 Wayland，4.1.0）

- `app.isPackaged` = true；CLI `status`：`packaged:true`、`state:ready`、`providerId:scnet`、`modelId:SCNet-Max`
- skill-storage 正常；safeStorage（kwallet）正常；BrowserWindow 1200×768，renderer 从 app.asar 的 dist 加载
- 进程树 40+s 稳定；node-pty spawn /bin/bash 正常；uv 0.9.1、agent-browser 0.41.2、原生模块加载正常
- 新流水线产出的 app.asar（路径 + 逐文件 md5）与旧手工流程一致

## 卸载

`sudo dpkg -r scnet-client`（postrm 刷新菜单；用户数据在 `~/.config` 下，不随包删除）
