# Loomy Windows → Linux 移植（deb 分发，dpkg 升级）

把讯飞 Loomy 桌面客户端从 Windows 绿色版移植为 Linux deb，安装到 `/opt/xunfei/loomy`，
通过 `dpkg`/`apt` 安装与升级。版本号与 Windows 包一致。

## 项目结构

```
loomy-porting/
├── win/                  # 放入 Loomy-<版本>-win.zip（脚本自动解压并删除）
├── scripts/
│   ├── build-deb.sh      # 一键构建入口
│   └── lib.sh            # 公共函数（解压/迁移/打包）
├── dist/                 # 产物 deb
└── .cache/               # Electron 解压缓存（可删，重建时自动生成）
```

## 快速开始（升级流程）

1. 下载新版 Windows 绿色版，重命名/放入：

   ```
   win/Loomy-<版本>-win.zip          例如 win/Loomy-0.9.40-win.zip
   ```

2. 下载对应版本的 Linux Electron，放入项目根：

   ```
   electron-v<版本>-linux-x64.zip    例如 electron-v45.3.2-linux-x64.zip
   ```

   Electron 版本需与 Windows 包内置 Electron 一致（在 Loomy.exe 里看，或看官方 Windows
   包 resources 里的 `LICENSE.electron.txt`）。

3. 一键构建：

   ```bash
   ./scripts/build-deb.sh
   ```

   脚本会：解压两个 zip（用后删除）→ 迁移文件 → 注入 Linux 原生依赖 → 打包 deb →
   清除中间目录。产物输出到 `dist/loomy_<版本>_amd64.deb`。

4. 安装/升级：

   ```bash
   sudo apt install ./dist/loomy_<版本>_amd64.deb
   ```

   覆盖升级自动进行；用户配置在 `~/.config/loomy*`，升级不丢。

## 脚本做了什么

| 步骤 | 说明 |
|------|------|
| 解压 win.zip | 到 `win/Loomy-<版本>-win/`，从目录名识别版本号 |
| 解压 electron.zip | 到 `.cache/electron-v<版本>-linux-x64/`（平铺结构已适配） |
| 重命名 electron→loomy | 让 `app.isPackaged=true`，避免 dev 分支加载错误 |
| 迁移业务资源 | `app.asar` + `app.asar.unpacked` + `.env.prod` 等，跨平台复用 |
| 迁移纯 JS 目录 | 跳过 win/darwin 专属二进制目录（见下表） |
| 下载 OpenCode CLI | npm `opencode-linux-x64`（默认 1.14.22）→ `resources/opencode/linux-x64/opencode` |
| 下载 Node | 独立 node-runtime（默认 v26.13.0）→ `resources/node-runtime/bin/node` |
| 下载 ffmpeg | 静态 linux-x64 → `resources/ffmpeg-static/ffmpeg` |
| 重打包 asar | 注入 `@napi-rs/keyring-linux-x64-gnu`，替换 unpacked 里的 ffmpeg 为 Linux ELF |
| 图标/.desktop/DEBIAN | hicolor 各尺寸图标、启动包装器、`Categories=Development`、postinst/prerm |
| 打包 deb | `dpkg-deb --build` → `dist/` |

## 安装后布局

```
/opt/xunfei/loomy/               自包含主程序
├── loomy                        Linux Electron（= electron 重命名）
├── chrome-sandbox               postinst 设为 4755
├── resources/
│   ├── app.asar                 官方业务逻辑（跨平台）
│   ├── app.asar.unpacked/       原生 .node（含注入的 keyring-linux）
│   ├── node-runtime/bin/node    独立 Node v26.13.0（MCP/脚本用）
│   ├── ffmpeg-static/ffmpeg     Linux 静态 ffmpeg
│   ├── opencode/linux-x64/opencode  OpenCode CLI v1.14.22（AI 运行时）
│   └── ...纯 JS 运行时目录
/usr/bin/loomy                   启动包装器（排除有害 env）
/usr/share/applications/loomy.desktop
/usr/share/icons/hicolor/*/apps/loomy.png
```

## 启动包装器排除的环境变量（防启动失败）

`/usr/bin/loomy` 在 exec 前排除宿主环境里会导致启动失败的变量：

| 变量 | 危害 |
|------|------|
| `LD_LIBRARY_PATH` / `LD_PRELOAD` / `LD_AUDIT` | 注入的错误 libstdc++ → GPU LAUNCH_FAILED |
| `ELECTRON_RUN_AS_NODE` | 让 Electron 当 node 跑，窗口起不来 |
| `ELECTRON_ENABLE_LOGGING` / `ELECTRON_DEBUG_NOTIFICATIONS` | 干扰启动 |
| `CHROME_DEVEL_SANDBOX` / `CHROMIUM_FLAGS` / `SANDBOX_LD_AUDIT` | 污染 Chromium 沙箱 |
| `TMPDIR`（强制 `/tmp`） | 深路径 → SingletonSocket FATAL |

实测：注入坏的 `LD_LIBRARY_PATH` + `ELECTRON_RUN_AS_NODE=1` + 深层 `TMPDIR` 后，
仍能正常启动。

## 平台依赖矩阵（Windows 包缺的，脚本补 Linux 版）

| 组件 | 处理 | 说明 |
|------|------|------|
| Electron | 必须放 zip | 主运行时 |
| node-runtime | 自动下载 | MCP/脚本用 |
| ffmpeg-static | 自动下载 | 音频转码 |
| OpenCode CLI | 自动下载 | AI 运行时（`opencode serve`），npm `opencode-linux-x64` 1.14.22；缺了报「OpenCode 二进制文件不存在」 |
| @napi-rs/keyring | 自动注入 | 钥匙串，降级可用 |
| msgpackr-extract | 跳过 | 纯 JS 回退 |
| @napi-rs/canvas | 跳过 | app 代码未 import |
| local-model/uv/python-archive | 跳过 | 降级系统 Python/uv |
| wecom/dingtalk/lark CLI | 跳过 | 无 Linux 版，降级 |

## 首次启动行为（几分钟「无反应」属正常）

首次启动（或配置目录依赖缺失时），`opencode serve` 后台执行
`npm install @opencode-ai/plugin` 到 `~/.config/loomy-opencode[/opencode]`，
期间**所有 API 请求排队等待**（实测约 4 分钟，视网络而定），UI 表现为「不报错但没反应」。
日志（`~/.local/share/loomy/opencode/log/`）可能出现
`background dependency install failed … ReleaseError: token mismatch`——
安装结果已落盘，只是释放文件锁时报错，无害。

依赖装好后（`~/.config/loomy-opencode*/node_modules` 与 package-lock 一致），
之后每次启动秒级就绪，不再触发安装。若某次启动又卡住，等它跑完即可，无需重装。

## 构建依赖

```
unzip  dpkg-deb  file  curl  asar  magick
```

asar: `npm i -g @electron/asar`；magick: ImageMagick 6+。

> 构建机上 Hermes Agent 会注入 `LD_LIBRARY_PATH` 干扰 `dpkg-deb`/`xz`/`curl`，
> 脚本已用 `env -u LD_LIBRARY_PATH -u LD_PRELOAD` 包裹系统命令，无需手动处理。

## 卸载

```bash
sudo apt remove loomy
```

## 调整内置 Node 版本

默认独立 Node 为 v26.13.0，可覆盖：

```bash
NODE_VER=24.22.2 ./scripts/build-deb.sh
```
