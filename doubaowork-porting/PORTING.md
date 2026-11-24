# 豆包工作 DoubaoWork 2.37.19 → Linux（Wine 用户级安装）

把 Windows 版 **豆包工作（DoubaoWork）2.37.19** 装到 Linux 的 `$HOME` 下，
通过系统级 **Wine 11（winehq-stable）** 运行；桌面入口写 `~/.local/share/applications`。
**全程不碰 `/opt`、`/usr`，不需要 root，也不生成 deb。**

## 一、它是什么（决定了移植方式）

`win/DoubaoWork.zip` 里不是 Electron：

```
Application/app/
├── DoubaoWork.exe            自研 Chromium 147 外壳主程序
├── DoubaoWork.dll / DoubaoWork_elf.dll
├── resources.pak / icudtl.dat / locales/      Chromium 资源
├── local_webcontents/        内置网页应用（entry-main、doubao-office…）
├── liblark.dll / liblark_resource_encrypt.dll  飞书（Lark 8.8.0）内核
├── aha_doctor/ sbox/ vm_sdk/ terminal_conpty/  平台原生组件
└── *.dll                     100+ 个 Windows 原生库
```

没有 `app.asar`、没有 Linux ELF、没有 mac 可复用二进制。所以它不是“换 Electron 重打包”
的移植，而是 **用官方 Windows 安装器在 Wine 前缀里做 per-user 安装**，升级由本项目
自己的更新器完成。

## 二、安装位置（全部在 $HOME）

```
~/.local/share/doubaowork/
├── bin/
│   ├── doubaowork                启动器（环境清理 + wine exec）
│   └── doubaowork-update         更新器（检查/下载/校验/切换/回滚）
├── lib.sh                        公共函数（运行期也用到）
├── prefix/                       WINEPREFIX
│   └── drive_c/users/<用户>/AppData/Local/DoubaoWork/
│       ├── Application/          官方安装树（app/ 是 2.37.19 载荷）
│       └── User Data/            用户数据（登录态、缓存、日志）
├── share/icons/doubaowork.png
├── updates/                      下载缓存（*.tar.zst）
└── state.json                    安装/升级状态

~/.local/share/applications/doubaowork.desktop     # 唯一在安装根之外的写入
```

> 卸载只删上面这两处。

## 三、安装

### 前置：系统级 Wine 11

本项目要求 **Wine 11+**（`winehq-stable`）。Ubuntu 26.04（resolute）实测安装方式：

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key
printf 'Types: deb\nURIs: https://dl.winehq.org/wine-builds/ubuntu/\nSuites: resolute\nComponents: main\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/winehq-archive.key\n' \
  | sudo tee /etc/apt/sources.list.d/winehq.sources >/dev/null
sudo apt-get update
sudo apt-get install -y --install-recommends winehq-stable
wine --version      # 期望 wine-11.0
```

发行版自带的 `wine 10` 会占用 `/usr/bin/wine`（Ubuntu 把它设成 `wine.collection`
的从属 alternative，直接 `--set` 会被拒绝）。安装 `wine-stable` 后补一组
`/usr/local/bin` 前置链接即可（`/usr/local/bin` 在 PATH 中先于 `/usr/bin`）：

```bash
for b in wine wine64 wineserver wineboot winecfg; do
  sudo ln -sfn /opt/wine-stable/bin/$b /usr/local/bin/$b
done
hash -r; wine --version
```

### 安装豆包工作

```bash
# 方式 1：官方在线安装器（需要点一下“立即安装”，会下载约 805 MB）
./install.sh --installer win/DoubaoWork_online_installer_2.36.15.exe

# 方式 2：从已有安装树复制（离线、最快）
./install.sh --seed /path/to/DoubaoWork        # 目录里要有 Application/app/DoubaoWork.exe

# 方式 3：从 Windows 绿色包 zip
./install.sh --zip win/DoubaoWork.zip

# 体检
./install.sh --check
```

安装器跑在 `WINEPREFIX=~/.local/share/doubaowork/prefix` 里，程序落到
`%LOCALAPPDATA%\DoubaoWork`（即前缀内路径），并写入：

```
HKCU\Software\DoubaoWork
  InstallDir = C:\users\<用户>\AppData\Local\DoubaoWork\Application\
  Version    = <载荷版本>          # 本项目安装时同步为 app/manifest.json 的版本
  ExeFileName= DoubaoWork.exe
  DataDir    = C:\users\<用户>\AppData\Local\DoubaoWork\User Data
HKCU\...\CurrentVersion\Uninstall\DoubaoWork
```

`install.sh` 复制安装树优先 `cp -a --reflink=auto`（btrfs/xfs 秒级，且与源目录解耦）。

## 四、启动

```bash
~/.local/share/doubaowork/bin/doubaowork          # 或应用菜单「豆包工作」
```

启动器会清理宿主环境（`LD_LIBRARY_PATH` / `LD_PRELOAD` / `LD_AUDIT` /
`ELECTRON_RUN_AS_NODE` / `CHROME_DEVEL_SANDBOX`），固定 `TMPDIR=/tmp`，
默认追加 `--no-sandbox` 与 `--disable-gpu --disable-gpu-compositing`，
然后在 `Application/` 下执行 `wine DoubaoWork.exe`。

> Wine 11 下 Chromium 的 GPU 合成会得到**黑窗**（窗口存在、内容全黑）；
> 强制软件渲染后登录页正常。想试 GPU 路径可 `DOUBAOWORK_SOFTWARE_GL=0`，
> 当前实测仍为黑窗，不建议。

进程名注意：Wine 11 里 `DoubaoWork.exe` 的 `comm` 不再是 `DoubaoWork.exe`，
`pgrep -x` 会漏报；按 `/proc/<pid>/cmdline` 匹配 `DoubaoWork.exe` 更可靠。

## 五、应用内升级（自研更新器）

### 官方版本通道（实测匿名可用）

```
GET https://www.doubao.com/service/settings/v3/
    ?device_platform=pc&brand=doubaowork&aid=1044603
    &os=windows&update_type=downloader&version_code=<当前版本>&os_version=10.0.26300
→ data.settings.saman_update_address = {
    newest_version, force_version, enable_check_update, release_note,
    win_x64_url, win_x64_md5 }
```

当前返回：`newest_version=2.37.19`，
`win_x64_url=https://lf-flow-web-cdn.doubao.com/obj/flow-doubao/doubao_pc/2.37.19/DoubaoWork_win_X64_2.37.19-signed.tar.zst`，
`win_x64_md5=3a82d41d327eb979fb2c50c8904641a7`，包大小 **844,319,371 B**，
支持 Range。包内是完整应用树（解开约 1.8 GB），**不是增量补丁**。

### 命令

```bash
doubaowork --check-update        # 终端检查；有更新时退出码 10
doubaowork-update --apply        # 下载 → md5 → 解到暂存 → 停机 → 原子切换
doubaowork-update --rollback     # 回滚到上一个版本（保留一份 app.old-*）
doubaowork-update --gui          # zenity/kdialog 图形化（桌面右键「检查更新」）
doubaowork-update --apply --package ./pkg.tar.zst --version 2.40.0   # 离线包
```

更新流程：

1. 用本地 `Application/app/manifest.json` 的 `version` 作为 `version_code`；
2. 比较 `newest_version`（`sort -V`），不大于本地则直接返回；
3. 下载到 `updates/DoubaoWork_win_X64_<ver>.tar.zst`（支持断点续传），md5 校验；
4. `tar --zstd` 解到 `Application/app.new.<pid>`，校验 `manifest.json` 与 `DoubaoWork.exe`；
5. `wineserver -k` 停止应用 → 旧目录改名 `app.old-<旧版本>` → 新目录原子切换；
6. 同步注册表 `HKCU\Software\DoubaoWork\Version`，写 `state.json`；
7. 只保留最近一份旧版本，供 `--rollback` 使用；下载缓存成功后默认删除
   （`DOUBAOWORK_KEEP_PACKAGE=1` 可保留）。

> **为什么不用豆包自带的 updater**：安装后它仍然报
> `[vulcan_update] from_version empty, won't update`、`!CheckHasInstalledVersion`、
> `update/prefs/prefs.cc(323) error_code1003`——它读的是 `User Data/update_data` 下的
> 自维护 prefs，而不是注册表 `Version`，安装器没有生成该文件。补齐 prefs 需要逆向
> 文件名与格式；先用自研更新器保证“应用内可升级”这一能力成立。

## 六、实测记录（2026-11-23，Wine 11.0 / winehq-stable）

| 环节 | 结果（Wine 11.0） |
|---|---|
| 系统 Wine | `winehq-stable 11.0.0.0~resolute-1`；`wine --version` → `wine-11.0` |
| 安装器 GUI | 718×478「豆包工作 / 立即安装」正常渲染 |
| 安装方式 | per-user：`new install cur_user`、`skip become admin`、`AdminEnv:0` |
| 下载 | 805.2 MB，走 `lf-flow-web-cdn.doubao.com`，约 16 分钟（1.3 MB/s） |
| 安装结果 | `%LOCALAPPDATA%\DoubaoWork\Application` ≈ 1.8 GB |
| 注册表 | `HKCU\Software\DoubaoWork` + `Uninstall\DoubaoWork` 已写 |
| 系统目录 | 应用/数据未写 `/opt`、`/usr` |
| 启动（软件渲染） | 主窗口 1192×716，登录页完整渲染（飞书一键登录 / 手机号登录 / 扫码） |
| 稳定性 | 启动后 60 s 内 16–18 个进程常驻，无 `FATAL` / `aborting` |
| 版本 | `doubaowork --version` → `2.37.19` |
| 更新检查 | `--check`：当前 2.37.19 = 最新 2.37.19（rc=0） |
| 更新/回滚 | 离线包 apply 9.9.9 → `--rollback` 回 2.37.19，均通过 |
| 全新前缀 | `install.sh --seed` 新装（全新 WINEPREFIX）同样正常渲染 |

> 安装器交互、805 MB 下载、per-user 注册表写入这几行来自 2026-11-23 早些时候在
> `deepin-wine8-stable 8.16` 下的实测（`--seed` 安装复用了那份载荷）；Wine 11 下未重跑
> 官方在线安装器（`install.sh --installer`），首次用该路径时请预留 10–30 分钟。

## 七、已知问题

1. **GPU 合成黑窗**：Wine 11 下 Chromium 默认 GPU 合成时窗口存在但内容全黑。
   启动器默认加 `--disable-gpu --disable-gpu-compositing` 走软件渲染后正常；
   代价是动画/视频走 CPU。`DOUBAOWORK_SOFTWARE_GL=0` 可关掉这组开关（不推荐）。
2. **DComposition 只有 stub**：日志里 `DCompositionCreateDevice3 failed: 尚未实现
   (0x80004001)` 是 Wine 的 dcomp 占位实现，Chromium 会自动回退，不影响启动。
3. **应用内原生 updater 未激活**：见上，缺 update prefs；本项目用自研更新器替代。
4. **版本口径**：官方安装器写注册表 `Version=2.36.15`（安装器版本）而载荷是 2.37.19；
   `install.sh` 安装后会把注册表同步成载荷版本，`state.json` 也记录载荷版本。
5. **「修复」弹窗**：`User Data/repair/record.json` 会累计异常退出次数，达到阈值弹
   「当前版本启动发生异常」；删除 `User Data/repair/` 目录即可复位。
6. **首次启动慢**：初始化 Chromium 用户目录与组件缓存需要时间；日志里
   `cloud_config` / `DataTransmitter` 缺文件属于正常降级。
7. **Wine 托盘/通知**：依赖 StatusNotifierItem，无桌面环境时不可见。
8. **进程名**：Wine 11 下 `comm` 与 exe 名不一致，脚本/巡检按 cmdline 匹配。
9. **从 deepin-wine8 迁移必须重建前缀**：8.16 时代的前缀把 `drive_c/windows/system32/*.dll`
   软链到 `/opt/deepin-wine8-stable/lib/wine/...`，卸载该包后会留下大量断链，启动直接报
   `wine: could not load kernel32.dll, status c0000135`。处理：停应用 → 把 `Application`
   移出前缀 → 用 Wine 11 新建前缀（`install.sh --seed <载荷目录>`）→ 载荷随新装写回。
   本项目真机安装已按此重建（新前缀断链数 0）。

## 八、依赖

```
wine 11+（winehq-stable，系统级安装）
python3  curl  tar + zstd  unzip
ImageMagick（convert/identify，提取图标；缺省回落 Logo.png）
zenity 或 kdialog（可选，图形化检查更新）
```

`tar --zstd` 需要 tar ≥ 1.31 与 `zstd`。

## 九、卸载

```bash
./uninstall.sh                # 删除 ~/.local/share/doubaowork 与桌面入口
./uninstall.sh --keep-data    # 保留 WINEPREFIX 和 User Data
```

## 十、与 minimax-code 契约的差异

minimax 是 Electron，走 `/opt` + deb + dpkg；本项目是 Windows 原生 Chromium 外壳，
按用户要求改为 **$HOME 用户级安装 + 自研应用内升级**：

| 维度 | minimax-code | doubaowork |
|---|---|---|
| 安装位置 | `/opt/minimax-code` | `~/.local/share/doubaowork` |
| 安装/卸载 | `dpkg` / `apt` | `install.sh` / `uninstall.sh` |
| 升级 | 下载 Windows 包，重打 deb | 应用内 `doubaowork-update`（整包替换 + 回滚） |
| 版本号 | 等于 Windows 包 | 等于载荷 `manifest.json`（2.37.19） |
| 系统目录 | `/usr/share/applications` | `~/.local/share/applications` |

## 十一、本地运行时（pwsh）与 .NET 限制

应用的「本地运行时 / sandbox」会自带一个 PowerShell Base package，落在：

```
User Data/sandbox_runtime/bases/<checksum>/pwsh/
```

`base.json` 记录 checksum/version；`pwsh.runtimeconfig.json` 显示它是 **self-contained
.NET 10**（Microsoft.NETCore.App / WindowsDesktop 10.0.10）。在 Wine 11.0 下它起不来：

- 应用日志（`sdk_storage/log/agent_infra/*.log`）：
  `System.IO.FileNotFoundException: Could not load file or assembly '...\pwsh\System.Runtime.dll'`
  → `WineDbg attached` → 45 s 超时；
- 直接执行该 `pwsh.exe`：无输出、进程不驻留；`WINEDEBUG=+seh` 可见 CLR 异常
  `0xe0434352` 与 `fixme:unwind:call_user_apc_dispatcher flags 0x3 are not supported`；
- 换成 PowerShell 7.4（.NET 8）、7.2（.NET 6）同样无输出退出；
- 换 `wine-devel 11.22` 直接挂起。

可疑点曾被归到「缺 .NET 运行时」，实测排除：

- 系统 winetricks（20250102）只有 `dotnet48` 等 .NET Framework verb；上游最新源码
  （`20260125-next`）新增了 `dotnet10` / `dotnetdesktop10`，在 Wine 11.0 前缀里
  **都能安装成功**（`Program Files/dotnet/shared` 出现 `Microsoft.NETCore.App` 与
  `Microsoft.WindowsDesktop.App` 10.0.0）；
- PowerShell 版本对应关系：7.4 = .NET 8、7.5 = .NET 9、**7.6 LTS = .NET 10**
  （应用自带的就是 7.6，`includedFrameworks` 10.0.10；官方 7.6.0 为 10.0.5）；
- 装完两个运行时、再换官方 7.6 后，行为不变。

真正的原因不是「运行时缺失」，而是 **Wine 下 .NET 控制台程序在重定向/管道 stdio 时
不执行**：

- `COREHOST_TRACE=1` 显示 hostfxr 正常加载 coreclr、托管程序执行并以 0 退出；
- 但管道下 pwsh 什么都不做（既不写文件也无输出）；`-Version` 抛
  `Process terminated. Object reference not set to an instance`；
- 用 `script -qec ...` 给它一个 PTY，同一个 `pwsh.exe` 立刻正常（能写出文件、能出版本号）。

结论：**本机 Wine 11.x 的 .NET ConsoleHost 在非终端 stdio 下不可用**；应用正是用管道
调用 pwsh，所以装运行时、换 7.6 都不能解决。把 PowerShell 复制进前缀同样无效。

「转给宿主机 terminal」也不可行：应用是以 Windows 子进程 + 管道/ConPTY 调用
`pwsh.exe`，Linux shell 无法直接替换（除非写一个 Windows PE 协议代理）。

脚本侧提供两个入口：

```bash
./install.sh --check            # 体检新增「本地 pwsh: 可用/不可用/未准备」
./install.sh --provision-pwsh PowerShell-7.4.6-win-x64.zip
                                # 把指定 win-x64 zip 装进 bases/*/pwsh（先备份旧目录）
```

`--provision-pwsh` 已实测（PowerShell 7.6.0-win-x64）：能正确替换
`bases/*/pwsh`（旧目录备份为 `pwsh.bak-<ts>`），但应用探针仍失败
（`environment_probe_failed stage=probe_shell code=5`，45 s）。因此它只在换到
「.NET ConsoleHost 在管道 stdio 下能正常工作」的 Wine（或后续 Wine 修复）后才有意义；
测试完应把备份目录还原回 `pwsh`。宿主机的 Linux `pwsh` 与此无关，不会被应用使用。

### ConPTY 包装器实验（失败）

`tools/pwshwrap/` 保留了一个实验：把 `pwsh.exe` 换成 PE 包装器，用
`CreatePseudoConsole` 给真正的 `pwsh-real.exe` 分配伪控制台，并在应用管道与伪控制台
之间双向转发。

Wine 11.0 实测（2026-11-23）：

- ConPTY 本身可用：`cmd /c echo hi` 经包装器能正常回传；
- `CreatePseudoConsole` 返回 `S_OK`，`PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` 生效；
- 但 pwsh 仍然报 `System.IO.FileNotFoundException: ...System.Runtime.dll`，与管道直连时相同；
- 同一二进制在真实 Unix PTY（`script -qec`）下曾成功，但不同前缀/时次无法稳定复现。

结论：Wine 的 ConPTY 不能替代真实终端，该路径不可行；需要 Wine 侧修复 .NET 的程序集
加载/控制台处理。

### 关闭 pwsh 探测（消除启动报错）

应用把本地运行时的开关缓存在 `User Data/Default/Remote_State` 的
`saman_sandbox_switch_config` 里，其中 `enable_pwsh` 默认为 `true`。置为 `false` 后，
应用启动时不再做 pwsh 探测，也就不会再弹 pwsh 报错。

该文件在启动过程中会被应用按服务端配置重写回 `true`，因此启动器的
`quiet_pwsh_errors()` 会在每次启动前把它压回 `false`（幂等，首次备份为
`Remote_State.bak-pwshoff`）；设 `DOUBAOWORK_KEEP_PWSH=1` 可跳过。

实测（2026-11-23）：连续两次启动，`agent_infra` 日志中
`local_runtime:env:probe` 记录均为 0，应用正常出窗口。
