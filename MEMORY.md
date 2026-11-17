# MEMORY — agent-porting 项目记忆

> 本文件是三个移植项目的长期记忆。经验手册在 .agents/skills/electron-win-to-linux-porting/，
> 体检脚本在 scripts/。新的坑和决策追加到对应小节，不要删旧记录（标日期）。

## 项目地图

- raccoon-porting：商汤小浣熊 1.2.1（NSIS exe 输入）。契约范本，结构最完整。
- loomy-porting：讯飞 Loomy 0.9.39（win zip 输入）。注意 win/ 会被 build-deb.sh 用后即删，
  完整重打包需重新提供 Loomy-*-win.zip。
- scnet-porting：SCNet 计算服务 4.1.0（win 绿色版目录输入）。唯一 git 仓库。
- 三者契约：win/ 输入 → ./scripts/build-deb.sh → dist/*.deb；共享 lib.sh；单文档 PORTING.md；
  .cache/ 素材、.migrate/ 中间产物、dist/ 交付物。

## 关键决策与根因（按时间倒序）

### 2026-11-16 loomy「不报错但没反应」（m00498）
- 根因：首启 opencode 在 ~/.config/loomy-opencode[/opencode] npm install @opencode-ai/plugin，
  Config.waitForDependencies 让所有 API 请求排队等安装完（实测 ~4 分钟），UI 表现为无反应。
- 日志告警 `background dependency install failed … ReleaseError: token mismatch` 无害：
  安装结果已落盘，只是释放文件锁报错。
- 依赖一致后（node_modules + package-lock 与 package.json 对齐）后续启动秒级就绪。
- 处置：文档化到 loomy-porting/PORTING.md「首次启动行为」；无代码改动、无需重打 deb。

### 2026-11-16 loomy「OpenCode 二进制文件不存在」（m00360）
- 根因：build-deb.sh 步骤5 SKIP_DIRS 含 opencode（错误假设「无 Linux 版会降级」）；
  实际 binary-runtime-coordinator.js:37 是 existsSync 即 hard error。
- 修复：build-deb.sh 自动下载 npm opencode-linux-x64@1.14.22 → resources/opencode/linux-x64/opencode；
  PORTING.md 补 3 行；dist/loomy_0.9.39_amd64.deb 打补丁重打（347,444,860 → 386,388,512 B）；
  在装系统 sudo install 补二进制（未 dpkg -i，避免 prerm pkill -x loomy 杀掉用户会话）。
- 二进制验证：ELF x86-64, 145,721,664 B, --version → 1.14.22。

### 2026-11-16 scnet asar 重打包 unpack 静默失败（首建 291MB 异常包）
- 根因：asar CLI 的 minimatch globstar 不穿越点前缀路径段——打包树绝对路径含 .migrate/ 时
  `--unpack **/*.{node,so,dll,exe}` 匹配 0 个文件，原生模块全进 asar，包从 183MB 涨到 291MB。
- 修复：unpack glob 改 basename 形式 `*.{node,so,dll,exe}`（matchBase 免疫）。
  同树在非点路径下两种 glob 都正常——纯路径触发的坑。
- 验证：149,933,569 B / 32 unpacked，与参考 deb-build/ 逐文件 md5 一致（仅 control 尺寸、
  launcher 有意改动、asar 头部 880B 字节序差异）。

### 2026-11-16 scnet-porting 对齐（m00001 起）
- 完成：lib.sh（fetch/prepare_electron/run_clean）、build-deb.sh 一键化、PORTING.md 折叠
  README+DELIVERY、.gitignore 改 win/ 整目录忽略、删 out-linux/+deb-build/（627M×2）。
- 产物：dist/scnet-client_4.1.0_amd64.deb 191,030,728 B 已交付。
- git 状态：改动未提交（3 M + PORTING.md/lib.sh 未跟踪 + lin/ 944 D）。

## 跨项目教训

- 重打包 asar 一律用 basename unpack glob，别用 **/*.x（点前缀路径段静默失效）。
- Windows 包里被跳过的目录，先查运行时是 hard error 还是真降级，再决定跳不跳。
- 打补丁优先就地补系统安装 + 重打 deb，别在用户会话活跃时 dpkg -i（prerm 可能 pkill）。
- dpkg-deb 打 300MB+ 树要 10 分钟级超时；阶段目录可复用，超时重试不必重新解包。
- /tmp 重启即清；检查树放项目 .migrate/ 下。
- 本机网络慢且有劫持：下载走镜像链 + SHA256 校验；models.dev/api.json 实测 10s。

## 未决/待办

- scnet-porting 的 git 改动尚未 commit（用户未答是否提交）。
- loomy 重打包需重新提供 win zip（build-deb.sh 用后即删，属设计行为）。