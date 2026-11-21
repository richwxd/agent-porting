#!/usr/bin/env bash
# scripts/lib.sh — minimax-code-porting 构建辅助函数。
# 与其他 *-porting 项目共享同一套约定（log/warn/die/need/fetch/run_clean），
# 额外提供 Windows 安装包解包、app.asar 版本读取、Linux 原生依赖准备。
# 仅供 source，不单独执行。

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

need() { # need <cmd...> — 缺任一命令即退出
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "缺少命令：$c（见 PORTING.md「构建依赖」）"
  done
}

run_clean() { # run_clean <cmd...> — 清掉打包器注入的环境变量再执行
  # LD_LIBRARY_PATH 里的 libstdc++ 缺 GPU 符号，且会污染 dpkg-deb（liblzma）
  env -u LD_LIBRARY_PATH -u LIBGL_DRIVERS_PATH -u TMPDIR "$@"
}

fetch() { # fetch <url> <out>
  curl -fSL --retry 3 -o "$2" "$1" || die "下载失败：$1"
}

# prepare_asar — 固定使用 @electron/asar 4.x
# 系统自带的 asar 3.x 在打包时会把名为 `constructor` 的目录整个丢掉
# （@sinclair/typebox/build/*/type/constructor 因此缺失，运行时 ESM 导入失败）。
# 4.x 已修复；装到 .cache/tools，避免依赖宿主全局版本。
prepare_asar() {
  local dir="$ROOT/.cache/tools" bin="$ROOT/.cache/tools/node_modules/.bin/asar"
  if [ ! -x "$bin" ]; then
    log "安装 @electron/asar@4 到 .cache/tools" >&2
    mkdir -p "$dir"
    [ -f "$dir/package.json" ] || ( cd "$dir" && npm init -y >/dev/null 2>&1 )
    ( cd "$dir" && run_clean npm install @electron/asar@4 --no-audit --no-fund >/dev/null 2>&1 ) \
      || die "安装 @electron/asar@4 失败"
  fi
  printf '%s' "$bin"
}

# --- Windows 安装包 → 绿色版目录 -------------------------------------------
# NSIS 两段式：exe 外层 → $PLUGINSDIR/app-64.7z → 应用目录。
# 解到 .migrate/win-app：换 exe 重跑时整体重建，避免旧 resources 残留。
prepare_win() {
  local win="$ROOT/win"
  local exe
  exe="$(ls -t "$win"/*.exe 2>/dev/null | head -1 || true)"
  [ -n "$exe" ] || die "win/ 下未找到 Windows 安装包 (*.exe)"

  local nsis="$ROOT/.migrate/nsis"
  local app="$ROOT/.migrate/win-app"
  if [ -f "$app/resources/app.asar" ] && [ "$app/.source-exe" = "$exe" ] \
     && [ "$(cat "$app/.source-stamp" 2>/dev/null)" = "$(stat -c '%s-%Y' "$exe")" ]; then
    printf '%s' "$app"
    return 0
  fi

  log "解包 Windows 安装包：$(basename "$exe")" >&2
  rm -rf "$nsis" "$app"
  mkdir -p "$nsis"
  run_clean 7z x -y "-o$nsis" "$exe" >/dev/null || die "7z 解包安装包外层失败"
  local app7z="$nsis/\$PLUGINSDIR/app-64.7z"
  [ -f "$app7z" ] || die "未找到 \$PLUGINSDIR/app-64.7z（安装包结构可能已变化）"
  run_clean 7z x -y "-o$app" "$app7z" >/dev/null || die "7z 解包应用层失败"
  [ -f "$app/resources/app.asar" ] || die "解包后未找到 resources/app.asar"
  printf '%s' "$exe" > "$app/.source-exe"
  stat -c '%s-%Y' "$exe" > "$app/.source-stamp"
  printf '%s' "$app"
}

# win_version <app 目录> — 从 app.asar 的 package.json 读版本，不硬编码
win_version() {
  local src="$1"
  local tmp="$ROOT/.migrate/ver"
  mkdir -p "$tmp"
  ( cd "$tmp" && run_clean "${ASAR_BIN:-asar}" extract-file "$src/resources/app.asar" package.json >/dev/null ) \
    || die "无法从 app.asar 读取 package.json"
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$tmp/package.json"
}

# win_electron_version <app 目录> — 从 Windows 主程序里读内嵌 Electron 版本
win_electron_version() {
  local src="$1"
  local exe ver
  exe="$(ls "$src"/*.exe 2>/dev/null | head -1 || true)"
  [ -n "$exe" ] || die "未找到 Windows 主程序 exe"
  ver="$(strings -a "$exe" | grep -oE 'Chrome/[0-9.]+ Electron/[0-9]+\.[0-9]+\.[0-9]+' \
        | head -1 | sed 's|.*Electron/||')"
  [ -n "$ver" ] || ver="$(strings -a "$exe" | grep -oE 'Electron v[0-9]+\.[0-9]+\.[0-9]+' \
        | head -1 | sed 's|Electron v||')"
  [ -n "$ver" ] || die "无法从 exe 识别 Electron 版本（可在 build-deb.sh 顶部固定 ELECTRON_VERSION）"
  printf '%s' "$ver"
}

# fetch_electron_zip <version> — 下载 electron-v<ver>-linux-x64.zip 到 .cache/
# 镜像：npmmirror → github；zip 一律用 github 官方 SHASUMS256.txt 校验。
fetch_electron_zip() {
  local ver="$1" name="electron-v${ver}-linux-x64"
  local zip="$ROOT/.cache/electron/$name.zip"
  local sums="$ROOT/.cache/electron/SHASUMS256-$ver.txt"
  local base
  mkdir -p "$ROOT/.cache/electron"
  for base in \
    "https://npmmirror.com/mirrors/electron/$ver" \
    "https://github.com/electron/electron/releases/download/v$ver"; do
    log "下载 $name.zip ← $base"
    if fetch "$base/$name.zip" "$zip" 2>/dev/null; then
      if fetch "https://github.com/electron/electron/releases/download/v$ver/SHASUMS256.txt" "$sums" 2>/dev/null; then
        (cd "$ROOT/.cache/electron" && grep " $name\\.zip\$" "$sums" | sha256sum -c -) \
          || die "SHASUMS256 校验失败：$name.zip"
      else
        warn "无法获取官方 SHASUMS256.txt，跳过校验"
      fi
      return 0
    fi
    warn "镜像不可用：$base"
  done
  die "无法下载 $name.zip；可手动放置到 $zip 后重试"
}

# prepare_electron <version> <dest> — Electron Linux 运行时就位（stock 布局，二进制名 electron）
prepare_electron() {
  local ver="$1" dest="$2"
  local name="electron-v${ver}-linux-x64"
  local cachedir="$ROOT/.cache/$name"
  local zip="$ROOT/.cache/electron/$name.zip"
  mkdir -p "$dest"
  if [ -x "$cachedir/electron" ]; then
    log "Electron $ver：使用已解包缓存 $cachedir"
    cp -a "$cachedir/." "$dest/"
    return 0
  fi
  [ -f "$zip" ] || fetch_electron_zip "$ver"
  log "Electron $ver：解包 $zip"
  rm -rf "$cachedir" && mkdir -p "$cachedir"
  unzip -qo "$zip" -d "$cachedir"
  [ -x "$cachedir/electron" ] || die "解包后缺少 electron 二进制"
  cp -a "$cachedir/." "$dest/"
}

# --- npm 包缓存 -------------------------------------------------------------
# fetch_npm <spec> <slug>：.cache/pkgs/<slug>.tgz，解到 .cache/npm/<slug>/package
fetch_npm() {
  local spec="$1" slug="$2"
  local tgz="$ROOT/.cache/pkgs/$slug.tgz"
  local dir="$ROOT/.cache/npm/$slug"
  if [ -d "$dir/package" ]; then
    return 0
  fi
  mkdir -p "$ROOT/.cache/pkgs" "$ROOT/.cache/npm"
  if [ ! -f "$tgz" ]; then
    local out
    out="$( cd "$ROOT/.cache/pkgs" && run_clean npm pack "$spec" --silent 2>/dev/null | tail -1 )"
    [ -n "$out" ] && [ -f "$ROOT/.cache/pkgs/$out" ] || die "npm pack 失败：$spec"
    mv "$ROOT/.cache/pkgs/$out" "$tgz"
  fi
  mkdir -p "$dir"
  tar xzf "$tgz" -C "$dir" || die "解包 npm 包失败：$tgz"
}

# install_npm_pkg <spec> <slug> <app-tree>/node_modules — 把平台包安装进 app 树
# 用法：install_npm_pkg "@napi-rs/keyring-linux-x64-gnu@2.1.1" keyring-linux "$WORK/node_modules"
install_npm_pkg() {
  local spec="$1" slug="$2" dest="$3"
  local pkgdir="$ROOT/.cache/npm/$slug/package"
  fetch_npm "$spec" "$slug"
  local name
  name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$pkgdir/package.json")"
  local target="$dest/$name"
  mkdir -p "$(dirname "$target")"
  rm -rf "$target"
  cp -a "$pkgdir" "$target"
}

# --- 原生模块 ---------------------------------------------------------------
# node-pty 1.1.0 的 npm 包只有 darwin/win32 prebuilds，Linux 必须源码编译。
# node-addon-api → N-API，ABI 与 Electron 版本无关，编译一次即可复用。
prepare_node_pty() {
  local out="$ROOT/.cache/native/node-pty/pty.node"
  [ -f "$out" ] && return 0
  log "编译 node-pty (linux-x64, N-API)"
  fetch_npm "node-pty@1.1.0" "node-pty-1.1.0"
  local src="$ROOT/.cache/build-nodepty"
  rm -rf "$src"
  mkdir -p "$src"
  cp -a "$ROOT/.cache/npm/node-pty-1.1.0/package/." "$src/"
  ( cd "$src" \
    && run_clean npm install node-addon-api@^7 --no-audit --no-fund >/dev/null 2>&1 \
    && run_clean npx --yes node-gyp@11 rebuild >/dev/null 2>&1 ) \
    || die "node-pty 编译失败（需要 g++/make/python3 与 node-gyp）"
  [ -f "$src/build/Release/pty.node" ] || die "node-pty 编译后缺少 pty.node"
  mkdir -p "$(dirname "$out")"
  cp "$src/build/Release/pty.node" "$out"
  file "$out" | grep -q ELF || die "node-pty 产物不是 Linux ELF"
}

# better-sqlite3 是 Electron 主进程/运行时的硬依赖，必须匹配 Electron ABI。
# 用官方 prebuild（electron-v<ABI>-linux-x64）下载，避免本机 node-gyp 编译整棵 SQLite。
prepare_better_sqlite3() {
  local out="$ROOT/.cache/native/better-sqlite3/better_sqlite3.node"
  [ -f "$out" ] && return 0
  log "准备 better-sqlite3 12.11.1 (electron $ELECTRON_VERSION, linux-x64)"
  local src="$ROOT/.cache/build-bs3"
  rm -rf "$src"
  mkdir -p "$src"
  ( cd "$src" \
    && npm init -y >/dev/null 2>&1 \
    && run_clean npm install better-sqlite3@12.11.1 --ignore-scripts --no-audit --no-fund >/dev/null 2>&1 ) \
    || die "better-sqlite3 依赖安装失败"
  ( cd "$src/node_modules/better-sqlite3" \
    && run_clean npx --yes prebuild-install --runtime electron --target "$ELECTRON_VERSION" \
         --tag-prefix v --force >/dev/null 2>&1 ) \
    || die "better-sqlite3 Electron prebuild 下载失败（检查 GitHub 网络）"
  [ -f "$src/node_modules/better-sqlite3/build/Release/better_sqlite3.node" ] \
    || die "better-sqlite3 prebuild 后缺少 .node"
  mkdir -p "$(dirname "$out")"
  cp "$src/node_modules/better-sqlite3/build/Release/better_sqlite3.node" "$out"
  file "$out" | grep -q ELF || die "better-sqlite3 产物不是 Linux ELF"
}

# 用 Electron 自身的 Node 运行时验证原生模块 ABI 可加载（打包前快速门禁）。
verify_native_with_electron() {
  local electron="$ROOT/.cache/electron-v${ELECTRON_VERSION}-linux-x64/electron"
  [ -x "$electron" ] || electron="$1"
  [ -x "$electron" ] || die "缺少 Electron 运行时，无法校验原生模块"
  local script="$ROOT/.migrate/verify-native.cjs"
  cat > "$script" <<'EOF'
const path = require('path');
const base = process.argv[2];
const pty = require(path.join(base, 'node_modules/node-pty'));
const Database = require(path.join(base, 'node_modules/better-sqlite3'));
const db = new Database(':memory:');
db.exec('create table t(a)');
db.prepare('insert into t values (1)').run();
console.log('native-ok pty=' + typeof pty.spawn + ' sqlite=' + db.prepare('select count(*) c from t').get().c);
EOF
  ELECTRON_RUN_AS_NODE=1 "$electron" "$script" "$2" || die "原生模块无法在 Electron 中加载"
}

# stub_missing_unpacked <app.asar> <app.asar.unpacked>
# Windows 安装包里部分「非本平台」的 unpacked 条目（darwin-arm64/win32-arm64）
# 在 app.asar 头里标记了 unpacked，但安装包并未携带对应文件；asar extract 会整体失败。
# 为这些不存在的条目补 0 字节占位（随后会随平台目录一起被裁掉）。
stub_missing_unpacked() {
  python3 - "$1" "$2" <<'PY'
import json, os, struct, sys
asar, unpacked = sys.argv[1], sys.argv[2]
with open(asar, 'rb') as f:
    head = f.read(16)
    jsize = struct.unpack('<I', head[12:16])[0]
    header = json.loads(f.read(jsize).decode('utf-8'))
missing = []
def walk(node, path):
    for name, value in node.get('files', {}).items():
        cur = path + '/' + name
        if 'files' in value:
            walk(value, cur)
        elif value.get('unpacked'):
            rel = cur.lstrip('/')
            if not os.path.exists(os.path.join(unpacked, rel)):
                missing.append(rel)
walk(header, '')
for rel in missing:
    target = os.path.join(unpacked, rel)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    open(target, 'wb').close()
print(f'[stub] {len(missing)} 个缺失的 unpacked 条目已补占位', file=sys.stderr)
PY
}

# --- Computer Use（Linux） ---------------------------------------------------
# 上游 cua-driver 0.34.1 与 MiniMax Windows 组件同协议；下载官方 linux-x86_64
# 二进制作为 linux-x64 组件。GitHub 直连不稳，按镜像链重试并校验 SHA256。
CUA_TARBALL_SHA="a41fe2bdcbeea4501dc594c074f16b0975728e0cc7b08b90acea8564d48fafee"
CUA_URL_PATH="trycua/cua/releases/download/cua-driver-rs-v0.34.1/cua-driver-rs-0.34.1-linux-x86_64-binary.tar.gz"

prepare_cua_linux() {
  local dir="$ROOT/.cache/cua/linux" tgz="$ROOT/.cache/cua/cua-linux.tar.gz"
  [ -x "$dir/cua-driver" ] && return 0
  mkdir -p "$ROOT/.cache/cua"
  if [ ! -f "$tgz" ]; then
    local base
    for base in \
      "https://ghfast.top/https://github.com/$CUA_URL_PATH" \
      "https://gh-proxy.com/https://github.com/$CUA_URL_PATH" \
      "https://github.com/$CUA_URL_PATH"; do
      log "下载 cua-driver linux-x64 ← ${base%%/https:*}"
      if /usr/bin/curl -fSL --retry 2 --max-time 240 -o "$tgz" "$base" 2>/dev/null; then
        break
      fi
      warn "下载失败：$base"
    done
  fi
  [ -f "$tgz" ] || die "无法下载 cua-driver linux-x64 组件"
  echo "$CUA_TARBALL_SHA  $tgz" | sha256sum -c - >/dev/null || die "cua-driver 压缩包 SHA256 校验失败"
  mkdir -p "$dir"
  tar xzf "$tgz" -C "$dir" || die "解包 cua-driver 失败"
  file "$dir/cua-driver" | grep -q ELF || die "cua-driver 不是 Linux ELF"
  "$dir/cua-driver" --help >/dev/null 2>&1 || die "cua-driver 无法运行"
}

# build_cua_component <dest> — 生成 linux-x64 组件目录 + component.json
build_cua_component() {
  local dest="$1"
  prepare_cua_linux
  local src="$ROOT/.cache/cua/linux"
  mkdir -p "$dest"
  install -m755 "$src/cua-driver" "$dest/minimax-computer-use"
  install -m755 "$src/cua-cursor-theme" "$dest/cua-cursor-theme"
  install -m755 "$src/libcua_driver_sdk.so" "$dest/libcua_driver_sdk.so"
  install -m755 "$src/cua_driver_node_runtime.node" "$dest/cua_driver_node_runtime.node"
  install -m644 "$src/cua_driver_abi.h" "$dest/cua_driver_abi.h"
  ( cd "$dest" && python3 - <<'PY'
import hashlib, json, os
files = {}
for name in sorted(os.listdir('.')):
    if name == 'component.json' or not os.path.isfile(name):
        continue
    files[name] = hashlib.sha256(open(name, 'rb').read()).hexdigest()
manifest = {
    'schemaVersion': 1,
    'version': '0.34.1',
    'brandRevision': 1,
    'platform': 'linux',
    'arch': 'x64',
    'bundleId': 'com.minimax.computer-use',
    'executablePath': 'minimax-computer-use',
    'sha256': files['minimax-computer-use'],
    'files': files,
    'updateSource': 'minimax-managed',
    'sourceCommit': '0c69d9a2c8abbb5051a2df4a23f0fa166d5385dc',
}
open('component.json', 'w').write(json.dumps(manifest, indent=2) + '\n')
PY
  ) || die "生成 Computer Use component.json 失败"
}
