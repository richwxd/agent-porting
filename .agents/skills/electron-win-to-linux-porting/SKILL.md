---
name: electron-win-to-linux-porting
description: Windows 版 Electron 桌面应用移植成 Linux 自包含 .deb 的完整工作流与踩坑手册。当需要把 win 版应用打成 Linux deb、对齐多个 *-porting 移植项目的一键升级契约、排查移植后运行时报错（原生模块缺失、二进制不存在、启动无反应、打包体积异常）、或重打包 asar 时使用。涉及 Electron 重命名、node-pty/原生模块 unpack、OpenCode/uv/agent-browser 等平台二进制替换、dpkg 绿色布局、chrome-sandbox setuid。
---

# Electron Windows→Linux 移植（.deb 自包含打包）

参考项目：~/Workspace/Projects/Node/agent-porting/{raccoon,loomy,scnet}-porting。
三者共享同一契约，新项目照抄布局。

## 一键升级契约（对齐标准）

    <app>-porting/
    ├── PORTING.md          # 唯一文档（构建、布局、排障、验证记录）
    ├── win/                # Windows 版输入（exe 或绿色版目录/zip），不入库
    ├── scripts/
    │   ├── lib.sh          # 共享 helper：log/warn/die/need/fetch/run_clean
    │   └── build-deb.sh    # 唯一入口：win/ → dist/<pkg>_<ver>_amd64.deb
    ├── .cache/             # 下载与注入素材（electron zip/解包、平台二进制、npm 注入集）
    ├── .migrate/           # 中间产物（解包树、stage），可随时删
    └── dist/               # 交付物 *.deb

版本从 app.asar 的 package.json 自动读取，不要硬编码。
打包环境要 run_clean（env -u LD_LIBRARY_PATH -u LD_PRELOAD）包住系统命令——宿主/打包器注入的
libstdc++/liblzma 会污染 dpkg-deb、curl、xz。

## 关键机制（决定成败的细节）

1. **Electron 二进制必须重命名**（electron→应用名）。Electron 用 execPath 文件名判断
   app.isPackaged：不改名会走 dev 分支 → ERR_INVALID_URL、各种 storage 报错。
2. **原生模块必须落在 app.asar.unpacked/**。Electron 不能从 asar 里 dlopen .node/.so。
   重打包时用 unpack glob *.{node,so,dll,exe}（basename 形式）+ unpack-dir 指定目录。
3. **asar unpack glob 切勿用 **/*.x 形式**：只要被打包树的绝对路径里有点前缀段
   （如 .migrate/），minimatch 的 globstar 就拒绝穿越，unpack 静默匹配 0 个文件，
   原生模块被塞进 asar，体积暴涨且运行时崩。basename 形式（matchBase）免疫此问题。
4. **win 专属二进制（.exe/dll）不代表能跳过整个目录**。先查运行时是不是硬校验：
   若 app 里是 existsSync 即报「XX 二进制文件不存在」的 hard error（如 opencode），
   必须补 Linux 版；只有真降级路径的目录才跳过。
5. **平台二进制来源**：Electron 用官方 zip；CLI 工具优先找 npm 平台包
   （如 opencode-linux-x64@<与 sdk 同版本>、@napi-rs/canvas-linux-x64-gnu），
   其次 GitHub release（uv）。验证三件套：体积 ≥ 应用要求的最小值、ELF magic、--version。
6. **node-pty prebuilds 的 spawn-helper 在 Linux 是必需品**，不是可选项。
7. **chrome-sandbox 必须 postinst 设 setuid 4755**（root:root）。
8. **启动包装器清理环境**：unset LD_LIBRARY_PATH/LD_PRELOAD、TMPDIR 强制 /tmp
   （深路径 → SingletonSocket FATAL）；保留 DBUS_SESSION_BUS_ADDRESS、XDG_RUNTIME_DIR。
   Deb 用绿色布局 /opt/<app> 自包含，只在 /usr/share/applications 写 .desktop。

## 首次启动行为（opencode 系）

首启会 npm install 插件依赖到 ~/.config/<app>-opencode*/，opencode 的
waitForDependencies 让**所有 API 请求排队等安装完**——慢网络下几分钟「不报错但没反应」
属正常，装完自动恢复。日志里的 ReleaseError: token mismatch 是释放锁报错，安装已落盘，无害。

## 验证方法

- 与参考 stage 逐文件 md5 对比（scripts/tree-md5-diff.py），只允许预期差异：
  control 的 Installed-Size、有意改动的 launcher、asar 头部字节序。
- dpkg-deb -x 解包再对一遍；dpkg-deb -I 查 control。
- 冒烟：--version、CLI status/doctor、原生模块加载、窗口起来。
- 大树（350MB+）dpkg-deb 很慢，命令超时给足（≥10 分钟）。

## 本机环境备忘

sudo 免密；/tmp 重启即清（检查树放 .migrate/）；网络慢且有劫持，
下载要走镜像链并校验 SHA256；harness 的管道 grep 偶发静默空结果，重要检查逐文件跑。