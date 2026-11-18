const e=require("./rolldown-runtime.js"),t=require("./auth-loss-observer.js"),n=require("./workbuddy-product-config.js"),r=require("./workbuddy-paths2.js"),i=require("./app-instance.js"),a=require("./mac-dmg-launch.js"),o=require("./report-install-update-outcome.js"),s=require("./update-timing-writer.js"),c=require("./update-service.js");let l=require("electron"),u=require("fs");u=e.a(u);let d=require("os");d=e.a(d);let f=require("path");f=e.a(f);let p=require("util"),m=require("child_process"),h=require("crypto"),g=require("fs/promises");g=e.a(g);let _=require("original-fs");_=e.a(_),t.c(),n.j(),n.f();var v=(0,p.promisify)(m.execFile),y=8,b=4,x=104857600;async function validateMacAsarIntegrity(e){let t=f.join(e,`Contents`,`Info.plist`),n=f.join(e,`Contents`,`Resources`,`app.asar`),r=await readExpectedMacAsarHeaderHash(t),i=await computeAsarHeaderHash(n);if(i!==r)throw Error(`ASAR integrity hash mismatch: expected ${r}, actual ${i}`);return{appPath:e,asarPath:n,infoPlistPath:t,expectedHash:r,actualHash:i}}async function computeAsarHeaderHash(e){let t=await readAsarHeaderString(e);return(0,h.createHash)(`sha256`).update(t).digest(`hex`)}async function readExpectedMacAsarHeaderHash(e){let t=[`Print :ElectronAsarIntegrity:Resources/app.asar:hash`,`Print :ElectronAsarIntegrity:Resources\\/app.asar:hash`],n;for(let r of t)try{let t=(await v(`/usr/libexec/PlistBuddy`,[`-c`,r,e])).stdout?.trim();if(t)return t}catch(e){n=e}let r=n instanceof Error?n.message:String(n??`empty hash`);throw Error(`Failed to read ElectronAsarIntegrity hash from ${e}: ${r}`)}async function readAsarHeaderString(e){let t=await openRealFile(e);try{let e=Buffer.alloc(y);if(await readRealFile(t,e,0)!==e.length)throw Error(`Unable to read ASAR header size`);let n=e.readUInt32LE(b);if(n<=b||n>x)throw Error(`Invalid ASAR header size: ${n}`);let r=Buffer.alloc(n);if(await readRealFile(t,r,y)!==r.length)throw Error(`Unable to read ASAR header`);let i=r.readInt32LE(b),a=8+i;if(i<=0||a>r.length)throw Error(`Invalid ASAR header string length: ${i}`);let o=r.subarray(8,a).toString(`utf8`);return JSON.parse(o),o}finally{await closeRealFile(t)}}function openRealFile(e){return new Promise((t,n)=>{_.open(e,`r`,(e,r)=>{if(e){n(e);return}t(r)})})}function readRealFile(e,t,n){return new Promise((r,i)=>{_.read(e,t,0,t.length,n,(e,t)=>{if(e){i(e);return}r(t)})})}function closeRealFile(e){return new Promise((t,n)=>{_.close(e,e=>{if(e){n(e);return}t()})})}i.n();var S=`com.workbuddy.workbuddy`,C=`com.tencent.workbuddy.mac`,w=`FN2V63AD2J`,T=new Set([S,C]),E=(0,p.promisify)(m.execFile),MacBundleUpdateInstaller=class{async prepare(e){this.validateInstallPath(e.currentAppPath,`currentAppPath`),this.validateInstallPath(e.extractedAppPath,`extractedAppPath`);let t=this.resolveStagedAppPath(e.currentAppPath,e.version);await this.forceRemoveDir(t),await g.mkdir(f.dirname(t),{recursive:!0});try{await E(`/usr/bin/ditto`,[e.extractedAppPath,t])}catch(e){throw await this.forceRemoveDir(t).catch(()=>void 0),e}return await E(`/usr/bin/xattr`,[`-dr`,`com.apple.quarantine`,t]).catch(()=>void 0),{...e,stagedAppPath:t}}async discardStagedApp(e){this.validateInstallPath(e,`stagedAppPath`),await this.forceRemoveDir(e)}async removeStagedApps(e,t){this.validateInstallPath(e,`currentAppPath`);let n=f.dirname(e),r=this.stagedAppPrefix(e),i=new Set(t.filter(e=>!!e).map(e=>f.resolve(e))),a={removed:[],failed:[]},o=await g.readdir(n,{withFileTypes:!0}).catch(()=>[]);for(let e of o){if(!e.isDirectory()||!e.name.startsWith(r))continue;let t=f.join(n,e.name);if(!i.has(t))try{await this.forceRemoveDir(t),a.removed.push(t)}catch(e){a.failed.push({path:t,message:e instanceof Error?e.message:String(e)})}}return a}async install(e,t,n){this.validateInstallPath(e.currentAppPath,`currentAppPath`),this.validateInstallPath(e.stagedAppPath,`stagedAppPath`),this.validateInstallPath(e.backupAppPath,`backupAppPath`),this.validateInstallPath(e.installResultPath,`installResultPath`),n&&this.validateInstallPath(n,`installLockPath`);let i=f.join(f.dirname(e.backupAppPath),`install-mac-bundle-update.sh`),a=f.join(r.u(),`update`),o=f.join(a,`install-mac-bundle-update.log`);await g.mkdir(a,{recursive:!0}),await g.mkdir(f.dirname(i),{recursive:!0}),await g.writeFile(i,this.buildInstallScript(),{mode:448}),await g.chmod(i,448);let s=await this.computeBundleFileHashes(e.stagedAppPath),c=r.d();(0,m.spawn)(`/bin/bash`,[i],{detached:!0,stdio:`ignore`,env:{PATH:`/usr/bin:/bin:/usr/sbin:/sbin`,HOME:d.homedir(),TMPDIR:d.tmpdir(),LANG:`en_US.UTF-8`,CURRENT_PID:String(t),CURRENT_APP_PATH:e.currentAppPath,STAGING_APP_PATH:e.stagedAppPath,BACKUP_APP_PATH:e.backupAppPath,INSTALL_LOG_PATH:o,INSTALL_RESULT_PATH:e.installResultPath,INSTALL_LOCK_PATH:n??``,TARGET_BUNDLE_ID:e.targetBundleId,UPDATE_VERSION:e.version,PENDING_TELEMETRY_DIR:c,SOURCE_INFO_PLIST_SHA256:s.infoPlist,SOURCE_APP_ASAR_SHA256:s.appAsar}}).unref()}async forceRemoveDir(e){try{await g.rm(e,{recursive:!0,force:!0});return}catch{}await new Promise(e=>setTimeout(e,500));try{await g.rm(e,{recursive:!0,force:!0});return}catch{}await E(`/bin/rm`,[`-rf`,e])}resolveStagedAppPath(e,t){return f.join(f.dirname(e),`${this.stagedAppPrefix(e)}${this.toSafePathPart(t)}`)}stagedAppPrefix(e){return`.${f.basename(e)}.installing.`}toSafePathPart(e){return e.replace(/[^a-zA-Z0-9._-]/g,`_`)}async computeBundleFileHashes(e){let t=f.join(e,`Contents`,`Info.plist`),n=f.join(e,`Contents`,`Resources`,`app.asar`),[r,i]=await Promise.all([this.computeFileSha256(t),this.computeFileSha256(n)]);return{infoPlist:r,appAsar:i}}async computeFileSha256(e){return new Promise((t,n)=>{let r=(0,h.createHash)(`sha256`),i=_.createReadStream(e);i.on(`error`,n),i.on(`data`,e=>r.update(e)),i.on(`end`,()=>t(r.digest(`hex`)))})}validateInstallPath(e,t){if(!f.isAbsolute(e))throw Error(`${t} must be an absolute path`);if(e.includes(`\0`))throw Error(`${t} contains invalid NUL byte`)}buildInstallScript(){return`#!/bin/bash
set -u

# \u2500\u2500\u2500 Timing infrastructure \u2500\u2500\u2500
# Uses perl for millisecond timestamps (macOS date doesn't support %N).
# All values are epoch milliseconds.
_ts_ms() {
  /usr/bin/perl -MTime::HiRes=gettimeofday -e 'my($s,$us)=gettimeofday;printf "%d\n",$s*1000+int($us/1000)' 2>/dev/null || /bin/date +%s000
}
IT_S0=0; IT_S1=0; IT_S2=0; IT_S3=0; IT_S4=0; IT_S5=0; IT_S6=0; IT_S7=0
SWAP_STARTED=0
SWAP_DONE=0
# Issue #164560: set by the softened TERM handler (on_term_soft). When 1, the
# main loop knows the OS is tearing down the main process and must confirm its
# full exit before swapping, instead of aborting on the signal.
GOT_TERM=0
# \u9996\u542F\u63A2\u6D4B\u53C2\u6570\uFF08Issue #109958\uFF09\uFF1A\u5D29\u6E83\u53D1\u751F\u5728 exec \u540E ~230ms\uFF0C4s \u8DB3\u591F\u533A\u5206
# "\u5DF2\u5D29\u6E83\u9000\u51FA" \u4E0E "\u6B63\u5E38\u542F\u52A8\u4E2D"\uFF1B\u603B\u91CD\u8BD5 3 \u6B21\uFF0C\u6700\u574F\u591A\u82B1 ~15s\u3002
LAUNCH_MAX_ATTEMPTS=3
LAUNCH_PROBE_DELAY_SEC=4
LAUNCH_ATTEMPTS_USED=0
# open \u547D\u4EE4\u672C\u8EAB\u5931\u8D25\u7684\u72EC\u7ACB\u91CD\u8BD5\uFF08Issue #109958 \u540E\u7EED\uFF09\uFF1A\u533A\u522B\u4E8E"\u8FDB\u7A0B\u5D29\u6E83"\uFF0C
# open \u8FD4\u56DE\u975E\u96F6\u591A\u4E3A\u6362\u5305\u540E LaunchServices \u6CE8\u518C\u7ADE\u6001\uFF08swap \u7528 mv \u6362\u4E86 inode\uFF0C
# lsregister -f \u5C1A\u672A\u5728 LS \u6570\u636E\u5E93\u843D\u7A33\uFF09\u3002\u6B64\u65F6 app \u7269\u7406\u5B8C\u597D\u3001\u51E0\u79D2\u540E\u5373\u53EF\u62C9\u8D77\uFF0C
# \u4E0D\u80FD\u5F53\u5D29\u6E83\u5904\u7406\u3002\u7B56\u7565\uFF1A\u6BCF\u6B21\u91CD\u8BD5\u524D\u91CD\u8DD1 lsregister -f \u4E3B\u52A8\u5237\u65B0\u6CE8\u518C\uFF0C\u5E76\u7528
# \u6307\u6570\u9000\u907F 2/4/8s \u62C9\u957F\u7A97\u53E3\uFF08\u7D2F\u8BA1 ~14s\uFF09\uFF0C\u625B\u8FC7\u7ADE\u6001\u800C\u4E0D\u8BEF\u56DE\u6EDA\u3002
OPEN_MAX_ATTEMPTS=4
OPEN_BACKOFF_BASE_SEC=2
# launch_with_probe \u7684\u5931\u8D25\u5F52\u56E0\uFF1A\u7531\u4E3B\u6D41\u7A0B\u636E\u6B64\u51B3\u5B9A\u662F\u5426\u56DE\u6EDA\u3002
# "open-race"=open \u547D\u4EE4\u6301\u7EED\u5931\u8D25(\u7591\u4F3C LS \u7ADE\u6001,bundle \u5B8C\u597D,\u4E0D\u56DE\u6EDA)\uFF1B
# "process-crash"=open \u6210\u529F\u4F46\u8FDB\u7A0B\u59CB\u7EC8\u672A\u5B58\u6D3B(\u7591\u4F3C\u9996\u542F\u5D29\u6E83,\u56DE\u6EDA\u65E7\u7248)\u3002
LAUNCH_FAILURE_KIND=""

log() {
  local message="$1"
  /bin/mkdir -p "$(/usr/bin/dirname "$INSTALL_LOG_PATH")" 2>/dev/null || true
  /bin/echo "[$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)] $message" >> "$INSTALL_LOG_PATH" 2>/dev/null || true
}

json_escape() {
  /usr/bin/printf '%s' "$1" | /usr/bin/perl -pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g'
}

# Write install timing JSON to pending-telemetry directory.
# Called at the end of a successful install, before write_result.
write_install_timing() {
  local telemetry_dir="\${PENDING_TELEMETRY_DIR:-}"
  if [ -z "$telemetry_dir" ]; then
    return
  fi
  /bin/mkdir -p "$telemetry_dir" 2>/dev/null || return

  local total_ms=0
  if [ "$IT_S0" -gt 0 ] && [ "$IT_S7" -gt 0 ]; then
    total_ms=$((IT_S7 - IT_S0))
  fi
  local wait_exit_ms=0
  if [ "$IT_S1" -gt 0 ] && [ "$IT_S2" -gt 0 ]; then wait_exit_ms=$((IT_S2 - IT_S1)); fi
  local ditto_ms=0
  local backup_ms=0
  if [ "$IT_S3" -gt 0 ] && [ "$IT_S4" -gt 0 ]; then backup_ms=$((IT_S4 - IT_S3)); fi
  local post_install_ms=0
  if [ "$IT_S4" -gt 0 ] && [ "$IT_S7" -gt 0 ]; then post_install_ms=$((IT_S7 - IT_S4)); fi

  local out_path="$telemetry_dir/update-shell-$IT_S0.json"
  /usr/bin/printf '{"source":"update-shell","platform":"darwin","version":"%s","targetBundleId":"%s","timestamp":"%s","launchAttempts":%d,"checkpoints":{"script_start":%d,"wait_exit_done":%d,"writable_check_done":%d,"staging_ditto_done":%d,"swap_done":%d,"lsregister_done":%d,"quarantine_cleared":%d,"install_complete":%d},"durations":{"wait_exit":%d,"backup":%d,"ditto":%d,"post_install":%d,"total":%d}}' \
    "\${UPDATE_VERSION:-unknown}" \
    "\${TARGET_BUNDLE_ID:-unknown}" \
    "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "\${LAUNCH_ATTEMPTS_USED:-0}" \
    0 \
    $((IT_S2 - IT_S0)) \
    $((IT_S3 - IT_S0)) \
    $((IT_S1 - IT_S0)) \
    $((IT_S4 - IT_S0)) \
    $((IT_S5 - IT_S0)) \
    $((IT_S6 - IT_S0)) \
    $((IT_S7 - IT_S0)) \
    "$wait_exit_ms" \
    "$backup_ms" \
    "$ditto_ms" \
    "$post_install_ms" \
    "$total_ms" \
    > "$out_path" 2>/dev/null || true
  log "install timing written to $out_path (total=\${total_ms}ms, wait_exit=\${wait_exit_ms}ms, backup=\${backup_ms}ms, launchAttempts=\${LAUNCH_ATTEMPTS_USED:-0})"
}

clear_install_lock() {
  if [ -n "\${INSTALL_LOCK_PATH:-}" ]; then
    /bin/rm -f "$INSTALL_LOCK_PATH" 2>/dev/null || true
  fi
}

write_result() {
  local success="$1"
  local code="$2"
  local tmp_path="\${INSTALL_RESULT_PATH}.tmp"
  local escaped_code
  local escaped_version
  local escaped_bundle_id
  escaped_code="$(json_escape "$code")"
  escaped_version="$(json_escape "\${UPDATE_VERSION:-unknown}")"
  escaped_bundle_id="$(json_escape "\${TARGET_BUNDLE_ID:-unknown}")"
  /bin/mkdir -p "$(/usr/bin/dirname "$INSTALL_RESULT_PATH")" 2>/dev/null || true
  /usr/bin/printf '{"success":%s,"code":"%s","version":"%s","targetBundleId":"%s","timestamp":"%s"}\n' \
    "$success" \
    "$escaped_code" \
    "$escaped_version" \
    "$escaped_bundle_id" \
    "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp_path" 2>/dev/null || true
  /bin/mv "$tmp_path" "$INSTALL_RESULT_PATH" 2>/dev/null || true
  clear_install_lock
}

fail_install() {
  local code="$1"
  local message="$2"
  log "$message"
  write_result false "$code"
  exit 1
}

fail_after_swap_restore() {
  local code="$1"
  local message="$2"
  log "$message"
  log "attempting backup restore after final bundle validation failure"
  if ! restore_backup; then
    write_result false "RESTORE_FAILED_AFTER_$code"
    exit 1
  fi
  write_result false "$code"
  exit 1
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" 2>> "$INSTALL_LOG_PATH" | /usr/bin/cut -d ' ' -f 1
}

verify_file_hash() {
  local file_path="$1"
  local expected_hash="$2"
  local label="$3"
  if [ -z "$expected_hash" ]; then
    log "$label expected hash is empty"
    return 1
  fi
  if [ ! -f "$file_path" ]; then
    log "$label missing: $file_path"
    return 1
  fi
  # Issue #164560: only the hash COMPUTATION is retried, never a genuine
  # mismatch. A softened TERM (on_term_soft) can interrupt shasum mid-read and
  # yield an empty result; retrying after the signal is consumed recomputes it
  # cleanly. A non-empty-but-different hash means the staged file is actually
  # wrong, so we fail immediately without retry.
  local actual_hash=""
  local attempt=1
  while [ "$attempt" -le 3 ]; do
    actual_hash="$(sha256_file "$file_path")"
    if [ -n "$actual_hash" ]; then
      break
    fi
    log "$label hash computation produced empty result (attempt $attempt/3, got_term=$GOT_TERM)"
    attempt=$((attempt + 1))
    /bin/sleep 0.3
  done
  if [ -z "$actual_hash" ]; then
    log "$label hash calculation failed: $file_path"
    return 1
  fi
  if [ "$actual_hash" != "$expected_hash" ]; then
    log "$label hash mismatch: expected=$expected_hash actual=$actual_hash path=$file_path"
    return 1
  fi
  log "$label hash verified"
  return 0
}

verify_staging_bundle_hashes() {
  verify_file_hash "$STAGING_APP_PATH/Contents/Info.plist" "$SOURCE_INFO_PLIST_SHA256" "staged Info.plist" \
    || fail_install "STAGING_INFO_PLIST_HASH_MISMATCH" "staged Info.plist hash mismatch"
  verify_file_hash "$STAGING_APP_PATH/Contents/Resources/app.asar" "$SOURCE_APP_ASAR_SHA256" "staged app.asar" \
    || fail_install "STAGING_APP_ASAR_HASH_MISMATCH" "staged app.asar hash mismatch"
}

verify_final_bundle_hashes() {
  verify_file_hash "$CURRENT_APP_PATH/Contents/Info.plist" "$SOURCE_INFO_PLIST_SHA256" "final Info.plist" \
    || fail_after_swap_restore "FINAL_INFO_PLIST_HASH_MISMATCH" "final Info.plist hash mismatch"
  verify_file_hash "$CURRENT_APP_PATH/Contents/Resources/app.asar" "$SOURCE_APP_ASAR_SHA256" "final app.asar" \
    || fail_after_swap_restore "FINAL_APP_ASAR_HASH_MISMATCH" "final app.asar hash mismatch"
}

wait_for_exit() {
  local pid="$1"
  local waited=0
  while /bin/kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge 60 ]; then
      log "current process still alive after 60s, aborting replacement"
      return 1
    fi
    # Issue #164560: a softened TERM (see on_term_soft) means the OS is already
    # tearing down the main process, so there is no point polling at the slow
    # 1s cadence \u2014 tighten to 100ms once GOT_TERM is set so we confirm exit and
    # proceed to swap promptly, instead of lingering in the window where a
    # follow-up SIGKILL could hit us.
    if [ "$GOT_TERM" -eq 1 ]; then
      /bin/sleep 0.1
    else
      /bin/sleep 1
      waited=$((waited + 1))
    fi
  done
  return 0
}

# Issue #164560: confirm the main process is FULLY gone before we touch
# /Applications. wait_for_exit returning only means "kill -0" saw ESRCH once;
# to be conservative against a late reap / brief zombie window we re-probe a few
# times with a short grace, and re-verify the target dir is writable (the main
# process holding files open would otherwise make the swap racy). Returns 0 when
# the process is confirmed gone, 1 if it is somehow still alive.
confirm_main_process_fully_exited() {
  local pid="$1"
  local attempt=0
  while [ "$attempt" -lt 5 ]; do
    if /bin/kill -0 "$pid" 2>/dev/null; then
      log "main process pid=$pid still alive during post-exit confirmation (attempt $((attempt + 1))/5)"
      /bin/sleep 0.2
      attempt=$((attempt + 1))
      continue
    fi
    # pid is gone; give the OS a brief moment to finish reaping/flushing, then
    # confirm once more so we do not race a process in its final exit frame.
    /bin/sleep 0.2
    if /bin/kill -0 "$pid" 2>/dev/null; then
      log "main process pid=$pid reappeared after grace (unexpected), re-waiting"
      attempt=$((attempt + 1))
      continue
    fi
    log "main process pid=$pid confirmed fully exited (got_term=$GOT_TERM)"
    return 0
  done
  log "main process pid=$pid could not be confirmed exited after retries"
  return 1
}

ensure_parent_writable() {
  local parent_dir
  parent_dir="$(/usr/bin/dirname "$CURRENT_APP_PATH")"
  local probe_path="$parent_dir/.workbuddy-update-write-test.$$"
  if ! /usr/bin/touch "$probe_path" 2>/dev/null; then
    fail_install "TARGET_NOT_WRITABLE" "target app directory is not writable: $parent_dir"
  fi
  /bin/rm -f "$probe_path" 2>/dev/null || true
}

restore_backup() {
  local failed_path="\${CURRENT_APP_PATH}.failed.$(/bin/date +%s)"
  if [ ! -d "$BACKUP_APP_PATH" ]; then
    log "backup app missing, cannot restore"
    return 1
  fi

  if [ -d "$CURRENT_APP_PATH" ]; then
    if ! /bin/mv "$CURRENT_APP_PATH" "$failed_path" 2>/dev/null; then
      log "failed to move broken app aside before restore"
      return 1
    fi
  fi

  if ! /bin/mv "$BACKUP_APP_PATH" "$CURRENT_APP_PATH" 2>/dev/null; then
    log "failed to restore backup app"
    if [ -d "$failed_path" ]; then
      /bin/mv "$failed_path" "$CURRENT_APP_PATH" 2>/dev/null || true
    fi
    return 1
  fi

  /usr/bin/open "$CURRENT_APP_PATH" 2>/dev/null || true
  return 0
}

restore_backup_if_swap_incomplete() {
  if [ "$SWAP_STARTED" -ne 1 ] || [ "$SWAP_DONE" -eq 1 ] || [ -d "$CURRENT_APP_PATH" ]; then
    return 0
  fi

  if [ ! -d "$BACKUP_APP_PATH" ]; then
    log "swap incomplete but backup is missing, cannot restore"
    return 1
  fi

  if /bin/mv "$BACKUP_APP_PATH" "$CURRENT_APP_PATH" 2>/dev/null; then
    log "backup restored after incomplete swap"
    return 0
  fi

  log "failed to restore backup after incomplete swap"
  return 1
}

on_exit() {
  local exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    return 0
  fi
  log "installer exiting with code $exit_code, running cleanup"
  restore_backup_if_swap_incomplete || true
  # Issue #164560: clear the lock on EVERY non-zero exit path, not only in
  # on_signal. The softened-TERM flow (see on_term_soft) deliberately does NOT
  # exit from the trap, so a later failure (e.g. wait_for_exit timeout, swap
  # failure) would otherwise leave the lock behind and re-arm the #149174
  # relaunch loop. clear_install_lock is idempotent, so calling it here as well
  # as in on_signal is safe.
  clear_install_lock
  return "$exit_code"
}

# Issue #164560: emit the signal scene used to identify who sent the signal and
# whether it is safe to keep installing. A shell signal trap cannot read the
# sender's si_pid directly, so we record strong circumstantial evidence:
#   - self_now: our pid/ppid/pgid/sess/stat at signal time. If ppid is now 1
#     (reparented to launchd) the original parent app has already exited, which
#     points to a parent-exit / process-group / launchd-domain signal rather
#     than an explicit kill from a live sibling.
#   - main_alive: whether the main app process (CURRENT_PID) is still alive.
#     Failures observed so far arrive ~0.5s AFTER the main process exits, so
#     "main gone at signal time" strongly implicates parent-exit cleanup.
#   - stage: which install step we were in (via IT_S* markers) when hit.
log_signal_diagnostics() {
  local signal_name="$1"
  local self_now
  self_now=$(/bin/ps -o pid=,ppid=,pgid=,sess=,stat= -p $$ 2>/dev/null | /usr/bin/tr -s ' ')
  local main_alive="unknown"
  if [ -n "$CURRENT_PID" ]; then
    if /bin/kill -0 "$CURRENT_PID" 2>/dev/null; then
      main_alive="alive ($(/bin/ps -o pid=,stat=,comm= -p "$CURRENT_PID" 2>/dev/null | /usr/bin/tr -s ' '))"
    else
      main_alive="gone"
    fi
  fi
  local stage="pre-verify"
  if [ "\${IT_S2:-0}" -gt 0 ]; then stage="post-wait_for_exit"
  elif [ "\${IT_S1:-0}" -gt 0 ]; then stage="post-verify/in-wait_for_exit"
  fi
  log "signal diagnostics: signal=$signal_name self_now=[$self_now] current_pid=$CURRENT_PID main_alive=$main_alive stage=$stage got_term=$GOT_TERM swap_started=$SWAP_STARTED swap_done=$SWAP_DONE"
}

# Hard-abort path for INT / HUP: these are "really stop now" signals (Ctrl-C /
# terminal hangup), so we roll back a half-done swap, clear the lock (keeps the
# #149174 relaunch-loop fix), and exit immediately.
on_signal() {
  local signal_name="$1"
  local exit_code="$2"
  log "installer received $signal_name"
  log_signal_diagnostics "$signal_name"
  restore_backup_if_swap_incomplete || true
  clear_install_lock
  exit "$exit_code"
}

# Issue #164560: softened TERM handler. The real-world failure is that the OS
# delivers SIGTERM to this detached installer ~0.5s after the main app process
# exits (parent-exit / launchd-domain cleanup), killing a perfectly valid
# upgrade mid-flight. Unlike INT/HUP, a TERM here is almost always just the
# collateral of the main process going away \u2014 which is exactly the condition we
# were WAITING for. So instead of aborting, we record the flag and keep going;
# the main loop (wait_for_exit) consults GOT_TERM to stop waiting early and then
# proceeds to swap, but ONLY after re-confirming the main process is fully gone.
# We never swap while the main process is still alive. All exit paths still
# clear the lock via on_exit, so the #149174 relaunch-loop fix is preserved even
# if a later step fails.
on_term_soft() {
  if [ "$GOT_TERM" -eq 1 ]; then
    # Already softened once; ignore repeats so a TERM storm cannot spin us.
    return 0
  fi
  GOT_TERM=1
  log "installer received TERM (softened): continuing install, will re-confirm main process exit before swap"
  log_signal_diagnostics "TERM-soft"
}

# Issue #164560: run the staging codesign check with a small retry. A softened
# TERM (on_term_soft) interrupts whatever foreground command is running and, on
# return, that command reports a signal-killed non-zero status. Without a retry
# the interrupted codesign would be misread as "signature invalid" and abort a
# perfectly good upgrade (this is exactly the staging-stage failure seen in the
# field). codesign --verify is a read-only, idempotent check, so re-running it
# after the signal has been consumed is safe and succeeds. Retries also absorb
# transient FS hiccups right after the ditto/sync.
verify_staging_codesign() {
  local attempt=1
  local max_attempts=3
  while [ "$attempt" -le "$max_attempts" ]; do
    if /usr/bin/codesign --verify --deep --strict --verbose=2 -R='anchor apple generic and certificate leaf[subject.OU] = "${w}"' "$STAGING_APP_PATH" >> "$INSTALL_LOG_PATH" 2>&1; then
      return 0
    fi
    local rc=$?
    log "staged codesign check failed (attempt $attempt/$max_attempts, rc=$rc, got_term=$GOT_TERM)"
    attempt=$((attempt + 1))
    if [ "$attempt" -le "$max_attempts" ]; then
      /bin/sleep 0.3
    fi
  done
  return 1
}

validate_staged_app() {
  if [ ! -f "$STAGING_APP_PATH/Contents/Info.plist" ]; then
    fail_install "STAGING_APP_INVALID" "staged app missing Contents/Info.plist"
  fi
  if [ ! -x "$STAGING_APP_PATH/Contents/MacOS/Electron" ]; then
    fail_install "STAGING_APP_INVALID" "staged app missing executable"
  fi
  if ! verify_staging_codesign; then
    fail_install "STAGING_CODESIGN_FAILED" "staged app code signature verification failed"
  fi
}

# \u2500\u2500\u2500 \u9996\u542F\u5B58\u6D3B\u63A2\u6D4B + \u91CD\u8BD5\uFF08Issue #109958\uFF09 \u2500\u2500\u2500
#
# \u73B0\u573A\uFF1A\u6362\u5305\u540E**\u7D27\u63A5\u7740\u7684\u90A3\u4E00\u6B21**\u542F\u52A8\u4F1A\u786E\u5B9A\u6027\u539F\u751F\u5D29\u6E83\uFF08EXC_BREAKPOINT/SIGTRAP\uFF0C
# \u6B7B\u5728 node::LoadEnvironment \u81EA\u4E3E\u9636\u6BB5\uFF0Capp JS \u4E00\u884C\u672A\u6267\u884C\uFF09\uFF0C\u51E0\u79D2\u540E\u518D\u542F\u52A8\u5C31\u6B63\u5E38\u3002
# \u8DE8 5.4.5 / 5.5.1 / 5.5.3 \u4E09\u4E2A\u7248\u672C\u5D29\u6E83\u6808 47 \u5E27 imageOffset \u9010\u5B57\u8282\u76F8\u540C\uFF0C\u8BF4\u660E\u4E0E
# \u5E94\u7528\u5C42\u4EE3\u7801\u65E0\u5173\uFF0C\u662F"\u521A\u843D\u76D8\u7684 bundle \u5728\u9996\u6B21 exec \u65F6\u72B6\u6001\u672A\u7A33\u5B9A"\u3002
#
# \u8FD9\u91CC\u4E0D\u8D4C\u6839\u56E0\uFF0C\u76F4\u63A5\u628A\u7528\u6237\u53EF\u611F\u77E5\u7684\u73B0\u8C61\u6D88\u6389\uFF1Aopen \u4E4B\u540E\u63A2\u6D4B\u4E3B\u8FDB\u7A0B\u662F\u5426\u5B58\u6D3B\uFF0C
# \u672A\u5B58\u6D3B\u5C31\u91CD\u8BD5\u3002\u91CD\u8BD5\u524D\u505A\u4E00\u6B21 sync\uFF0C\u5C3D\u91CF\u628A ditto \u5199\u5165\u7684\u5143\u6570\u636E\u63A8\u4E0B\u53BB\u3002
probe_app_alive() {
  # \u53EA\u5339\u914D\u4E3B\u8FDB\u7A0B exec path\uFF1AElectron \u7684 helper/renderer \u547D\u4EE4\u884C\u8D70
  # Contents/Frameworks/<...>Helper.app/<...>\uFF0Ccrashpad \u8D70 chrome_crashpad_handler\uFF0C
  # \u90FD\u4E0D\u542B Contents/MacOS/Electron\uFF0C\u4E0D\u4F1A\u9020\u6210\u5047\u9633\u6027\u3002
  /usr/bin/pgrep -f "$CURRENT_APP_PATH/Contents/MacOS/Electron" >/dev/null 2>&1
}

diagnose_launch_failure() {
  log "first-launch probe failed, collecting diagnostics"
  if /usr/bin/codesign --verify --strict --verbose=2 -R='anchor apple generic and certificate leaf[subject.OU] = "${w}"' "$CURRENT_APP_PATH" >> "$INSTALL_LOG_PATH" 2>&1; then
    log "diagnostics: installed app codesign OK (crash is not a signature problem)"
  else
    log "diagnostics: installed app codesign FAILED at final path"
  fi
  if [ -f "$CURRENT_APP_PATH/Contents/Resources/app.asar" ]; then
    log "diagnostics: app.asar size=$(/usr/bin/stat -f%z "$CURRENT_APP_PATH/Contents/Resources/app.asar" 2>/dev/null || echo unknown)"
  else
    log "diagnostics: app.asar MISSING at $CURRENT_APP_PATH/Contents/Resources/app.asar"
  fi
}

# open \u547D\u4EE4\u5931\u8D25\u7684\u53D6\u8BC1\uFF08Issue #109958 \u540E\u7EED\uFF09\uFF1Aopen \u7684 stderr/exit code \u6B64\u524D\u88AB
# \u541E\u6389\uFF0C\u5BFC\u81F4\u6362\u5305\u7A97\u53E3\u5185 open \u4E3A\u4F55\u5931\u8D25\u5B8C\u5168\u4E0D\u53EF\u8BCA\u65AD\u3002\u8FD9\u91CC\u628A LaunchServices \u4FA7\u7684
# \u72B6\u6001\u4E00\u5E76\u843D\u76D8\u5230 install log\uFF08\u5728\u5F52\u6863 roots \u5185\uFF0C\u7528\u6237"\u6253\u5305\u65E5\u5FD7"\u5373\u53EF\u5E26\u51FA\uFF09\u3002
# \u5168\u90E8 best-effort\uFF0C\u4EFB\u4F55\u4E00\u6B65\u5931\u8D25\u90FD\u4E0D\u5F97\u4E2D\u65AD\u5B89\u88C5\u6D41\u7A0B\u3002
diagnose_open_failure() {
  local rc="$1"
  local err_text="$2"
  log "diagnostics(open): rc=$rc stderr=$(json_escape "$err_text")"
  # \u76EE\u6807 bundle \u7684\u7269\u7406\u72B6\u6001\uFF1Ainode \u7528\u4E8E\u5370\u8BC1 swap \u662F\u5426\u6362\u4E86\u76EE\u5F55\u3001\u662F\u5426\u4E0E LS \u7F13\u5B58\u4E0D\u4E00\u81F4\u3002
  log "diagnostics(open): app inode=$(/usr/bin/stat -f%i "$CURRENT_APP_PATH" 2>/dev/null || echo unknown)"
  log "diagnostics(open): app mtime=$(/usr/bin/stat -f%m "$CURRENT_APP_PATH" 2>/dev/null || echo unknown)"
  if [ -x "$CURRENT_APP_PATH/Contents/MacOS/Electron" ]; then
    log "diagnostics(open): main executable present and executable"
  else
    log "diagnostics(open): main executable MISSING or not executable at Contents/MacOS/Electron"
  fi
  log "diagnostics(open): quarantine xattr=$(/usr/bin/xattr -p com.apple.quarantine "$CURRENT_APP_PATH" 2>/dev/null || echo none)"
  # LaunchServices \u5BF9\u8BE5\u8DEF\u5F84\u7684\u6CE8\u518C\u8BB0\u5F55\uFF1A\u7ADE\u6001\u65F6\u901A\u5E38\u7F3A\u5931/\u6307\u5411\u65E7 inode/\u91CD\u590D\u3002
  if [ -x "$LSREGISTER" ]; then
    log "diagnostics(open): dumping lsregister entries for target bundle"
    "$LSREGISTER" -dump 2>/dev/null | /usr/bin/grep -F "$CURRENT_APP_PATH" >> "$INSTALL_LOG_PATH" 2>&1 || \
      log "diagnostics(open): no lsregister entry found for target path"
  fi
  # \u7CFB\u7EDF LaunchServices/launchd \u65E5\u5FD7\uFF1Aopen \u62D2\u7EDD\u7684\u5185\u6838\u7EA7\u539F\u56E0\u5F80\u5F80\u53EA\u5728\u8FD9\u91CC\u3002
  /usr/bin/log show --last 2m --style compact \
    --predicate 'subsystem == "com.apple.launchservices" OR process == "launchd" OR process == "lsd"' \
    >> "$INSTALL_LOG_PATH" 2>&1 || log "diagnostics(open): log show unavailable"
}

# \u9996\u542F\u5B58\u6D3B\u63A2\u6D4B + \u91CD\u8BD5\u3002\u4E24\u7C7B\u5931\u8D25\u4E25\u683C\u5206\u6D41\uFF0C\u4F9B\u4E3B\u6D41\u7A0B\u51B3\u5B9A\u662F\u5426\u56DE\u6EDA\uFF1A
#   1) open \u547D\u4EE4\u8FD4\u56DE\u975E\u96F6\uFF1A\u7591\u4F3C LaunchServices \u6CE8\u518C\u7ADE\u6001\uFF08bundle \u5B8C\u597D\uFF09\u3002
#      \u91CD\u8DD1 lsregister -f \u4E3B\u52A8\u5237\u65B0\u6CE8\u518C + \u6307\u6570\u9000\u907F\u62C9\u957F\u7A97\u53E3\uFF0C\u7EDD\u4E0D\u5F53\u5D29\u6E83\u56DE\u6EDA\u3002
#   2) open \u6210\u529F\u4F46\u8FDB\u7A0B\u59CB\u7EC8\u672A\u5B58\u6D3B\uFF1A\u7591\u4F3C #109958 \u9996\u542F native \u5D29\u6E83\uFF0C\u6CBF\u7528\u65E7\u7B56\u7565\u3002
# \u5168\u6D41\u7A0B\u6210\u529F\u8FD4\u56DE 0\uFF1B\u5931\u8D25\u65F6\u7F6E LAUNCH_FAILURE_KIND \u5E76\u8FD4\u56DE 1\u3002
launch_with_probe() {
  LAUNCH_FAILURE_KIND=""

  # \u8DEF\u5F84 1\uFF1A\u5148\u4E13\u95E8\u625B open \u547D\u4EE4\u5931\u8D25\uFF08LaunchServices \u7ADE\u6001\uFF09\u3002open \u4E00\u65E6\u6210\u529F\u5373\u8DF3\u51FA\uFF0C
  # \u4EA4\u7ED9\u4E0B\u9762\u7684\u8FDB\u7A0B\u5B58\u6D3B\u63A2\u6D4B\u3002open \u6301\u7EED\u5931\u8D25\u5230\u4E0A\u9650\u624D\u5F52\u56E0\u4E3A open-race\u3002
  local open_attempt=1
  local open_ok=0
  while [ "$open_attempt" -le "$OPEN_MAX_ATTEMPTS" ]; do
    local open_err
    open_err=$(/usr/bin/open "$CURRENT_APP_PATH" 2>&1)
    local open_rc=$?
    if [ "$open_rc" -eq 0 ]; then
      open_ok=1
      break
    fi
    log "open failed on launch attempt $open_attempt rc=$open_rc"
    if [ "$open_attempt" -eq 1 ]; then
      diagnose_open_failure "$open_rc" "$open_err"
    fi
    open_attempt=$((open_attempt + 1))
    if [ "$open_attempt" -le "$OPEN_MAX_ATTEMPTS" ]; then
      # \u4E3B\u52A8\u91CD\u5237\u6CE8\u518C\uFF0C\u800C\u4E0D\u662F\u5E72\u7B49\u7CFB\u7EDF\u540E\u53F0\u91CD\u65B0\u7D22\u5F15\u3002
      if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -f "$CURRENT_APP_PATH" >> "$INSTALL_LOG_PATH" 2>&1 || true
      fi
      /bin/sync 2>/dev/null || true
      # \u6307\u6570\u9000\u907F 2/4/8s\uFF1Abase * 2^(n-1)\u3002
      local backoff=$((OPEN_BACKOFF_BASE_SEC * (1 << (open_attempt - 2))))
      log "retrying open after re-registering (attempt $open_attempt of $OPEN_MAX_ATTEMPTS, backoff \${backoff}s)"
      /bin/sleep "$backoff"
    fi
  done

  if [ "$open_ok" -ne 1 ]; then
    log "open command kept failing after $OPEN_MAX_ATTEMPTS attempts (suspected LaunchServices race)"
    LAUNCH_ATTEMPTS_USED=$OPEN_MAX_ATTEMPTS
    LAUNCH_FAILURE_KIND="open-race"
    return 1
  fi

  # \u8DEF\u5F84 2\uFF1Aopen \u5DF2\u6210\u529F\uFF0C\u63A2\u6D4B\u4E3B\u8FDB\u7A0B\u662F\u5426\u5B58\u6D3B\uFF1B\u672A\u5B58\u6D3B\u6309\u9996\u542F\u5D29\u6E83\u91CD\u8BD5\uFF08\u6CBF\u7528 #109958\uFF09\u3002
  local attempt=1
  while [ "$attempt" -le "$LAUNCH_MAX_ATTEMPTS" ]; do
    /bin/sleep "$LAUNCH_PROBE_DELAY_SEC"
    if probe_app_alive; then
      log "app alive after launch attempt $attempt"
      LAUNCH_ATTEMPTS_USED=$attempt
      return 0
    fi
    log "app not alive \${LAUNCH_PROBE_DELAY_SEC}s after launch attempt $attempt"
    if [ "$attempt" -eq 1 ]; then
      diagnose_launch_failure
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -le "$LAUNCH_MAX_ATTEMPTS" ]; then
      /bin/sync 2>/dev/null || true
      /bin/sleep 1
      log "retrying launch (attempt $attempt of $LAUNCH_MAX_ATTEMPTS)"
      /usr/bin/open "$CURRENT_APP_PATH" >/dev/null 2>&1 || true
    fi
  done
  LAUNCH_ATTEMPTS_USED=$LAUNCH_MAX_ATTEMPTS
  LAUNCH_FAILURE_KIND="process-crash"
  return 1
}

trap on_exit EXIT
# Issue #164560: TERM is softened (keep installing; the main process going away
# is exactly what we wait for), while INT/HUP remain hard aborts.
trap on_term_soft TERM
trap 'on_signal INT 130' INT
trap 'on_signal HUP 129' HUP

IT_S0=$(_ts_ms)
log "installer started"
log "current=$CURRENT_APP_PATH staging=$STAGING_APP_PATH backup=$BACKUP_APP_PATH pid=$CURRENT_PID"
# Issue #164560: TERM-sender diagnostics. Record our own process identity at
# startup so on_signal can compare against it. If detached/setsid worked, our
# PGID and SID should equal our own PID (we are a session+group leader) and be
# independent from the main app process; if they still match the parent app's
# group, a parent-exit (launchd/group) TERM can reach us. $PPID is the shell's
# parent at startup (expected: the Electron main process, i.e. CURRENT_PID).
log "installer identity: self_pid=$$ ppid=$PPID self_pgid_sid=$(/bin/ps -o pgid=,sess= -p $$ 2>/dev/null | /usr/bin/tr -s ' ') startup_ps=$(/bin/ps -o pid=,ppid=,pgid=,sess=,stat=,comm= -p $$ 2>/dev/null | /usr/bin/tr -s ' ')"

if [ ! -d "$STAGING_APP_PATH" ]; then
  fail_install "STAGING_APP_MISSING" "staged app path does not exist"
fi

validate_staged_app
verify_staging_bundle_hashes
/bin/sync 2>/dev/null || true
IT_S1=$(_ts_ms)
log "staging app verified ($(( IT_S1 - IT_S0 ))ms)"

if ! wait_for_exit "$CURRENT_PID"; then
  /usr/bin/open "$CURRENT_APP_PATH" 2>/dev/null || true
  fail_install "PROCESS_EXIT_TIMEOUT" "current process still alive after 60s"
fi
IT_S2=$(_ts_ms)
log "wait_for_exit done ($(( IT_S2 - IT_S0 ))ms, got_term=$GOT_TERM)"

# Issue #164560: final guard before touching /Applications. Whether we exited
# wait_for_exit normally or via a softened TERM, never start the swap until the
# main process is positively confirmed gone \u2014 this is the gate that makes the
# "keep installing on TERM" behavior safe (no racing the still-running app for
# its own bundle files).
if ! confirm_main_process_fully_exited "$CURRENT_PID"; then
  /usr/bin/open "$CURRENT_APP_PATH" 2>/dev/null || true
  fail_install "PROCESS_EXIT_UNCONFIRMED" "main process exit could not be confirmed before swap"
fi

ensure_parent_writable
IT_S3=$(_ts_ms)
log "writable check done ($(( IT_S3 - IT_S0 ))ms)"

/bin/mkdir -p "$(/usr/bin/dirname "$BACKUP_APP_PATH")" || fail_install "BACKUP_DIR_CREATE_FAILED" "failed to create backup directory"
/bin/rm -rf "$BACKUP_APP_PATH" 2>/dev/null || true

SWAP_STARTED=1
if [ -d "$CURRENT_APP_PATH" ]; then
  if ! /bin/mv "$CURRENT_APP_PATH" "$BACKUP_APP_PATH"; then
    fail_install "BACKUP_MOVE_FAILED" "failed to move current app to backup"
  fi
fi
if ! /bin/mv "$STAGING_APP_PATH" "$CURRENT_APP_PATH"; then
  log "failed to move staged app into place, attempting restore"
  if ! restore_backup; then
    fail_install "RESTORE_FAILED" "failed to restore backup after swap failure"
  fi
  fail_install "SWAP_FAILED" "failed to move staged app into place"
fi
SWAP_DONE=1
IT_S4=$(_ts_ms)
log "swap done ($(( IT_S4 - IT_S0 ))ms, backup=$(( IT_S4 - IT_S3 ))ms)"
verify_final_bundle_hashes
if ! /usr/bin/codesign --verify --deep --strict --verbose=2 -R='anchor apple generic and certificate leaf[subject.OU] = "${w}"' "$CURRENT_APP_PATH" >> "$INSTALL_LOG_PATH" 2>&1; then
  fail_after_swap_restore "FINAL_CODESIGN_FAILED" "installed app code signature verification failed"
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$CURRENT_APP_PATH" >> "$INSTALL_LOG_PATH" 2>&1 || true
fi
IT_S5=$(_ts_ms)
log "lsregister done ($(( IT_S5 - IT_S0 ))ms)"

/usr/bin/xattr -dr com.apple.quarantine "$CURRENT_APP_PATH" >> "$INSTALL_LOG_PATH" 2>&1 || true
IT_S6=$(_ts_ms)
log "quarantine cleared ($(( IT_S6 - IT_S0 ))ms)"

if ! launch_with_probe; then
  # \u5206\u6D41\u5904\u7F6E\uFF1A
  # - open-race\uFF1A\u6362\u5305\u5DF2\u6210\u529F\u4E14 bundle \u7269\u7406\u5B8C\u597D\uFF08hash/codesign \u5DF2\u5728\u6362\u4F4D\u524D\u540E\u6821\u9A8C\uFF09\uFF0C
  #   \u4EC5 open \u56E0 LaunchServices \u7ADE\u6001\u672A\u5728\u7A97\u53E3\u5185\u62C9\u8D77\u3002\u6B64\u65F6\u56DE\u6EDA\u6539\u540D\u53CD\u800C\u8BA9\u65B0\u7248
  #   "\u6D88\u5931"\uFF08\u7528\u6237\u641C\u4E0D\u5230\uFF09\uFF0C\u800C\u7CFB\u7EDF\u7A0D\u540E\u5373\u53EF\u81EA\u884C\u62C9\u8D77\u3002\u6545\u4FDD\u7559\u65B0\u7248\u539F\u5730\uFF0C\u6807\u8BB0\u5B89\u88C5\u6210\u529F\uFF0C
  #   \u4EC5\u8BB0\u5F55\u5F85\u89C2\u6D4B\u3002
  # - process-crash\uFF1Aopen \u6210\u529F\u4F46\u8FDB\u7A0B\u59CB\u7EC8\u672A\u5B58\u6D3B\uFF0C\u7591\u4F3C\u9996\u542F native \u5D29\u6E83\uFF0C\u56DE\u6EDA\u65E7\u7248\u3002
  if [ "$LAUNCH_FAILURE_KIND" = "open-race" ]; then
    log "open kept failing (suspected LaunchServices race); keeping new bundle in place without rollback, system is expected to launch it shortly"
    IT_S7=$(_ts_ms)
    log "install complete with launch deferred ($(( IT_S7 - IT_S0 ))ms total, launchAttempts=$LAUNCH_ATTEMPTS_USED)"
    log "backup retained at $BACKUP_APP_PATH for manual recovery"
    write_install_timing
    write_result true "OK_LAUNCH_DEFERRED"
    exit 0
  fi

  log "updated app failed to stay alive after $LAUNCH_MAX_ATTEMPTS attempts, attempting restore"
  if ! restore_backup; then
    fail_install "RESTORE_FAILED" "failed to restore backup after launch failure"
  fi
  fail_install "LAUNCH_FAILED" "updated app crashed on every launch attempt"
fi
IT_S7=$(_ts_ms)
log "install complete ($(( IT_S7 - IT_S0 ))ms total, launchAttempts=$LAUNCH_ATTEMPTS_USED)"

log "updated app opened successfully"
log "backup retained at $BACKUP_APP_PATH for manual recovery"
write_install_timing
write_result true "OK"
exit 0
`}},D=(0,p.promisify)(m.execFile),O=1048576,k=209715200,A=12e4,j=36e5,M=72e5,N=200,P=4096,F=3405691582,I=3199925962,L=3405691583,R=3216703178,z=4277009102,B=4277009103,V=16777223,H=16777228,UpdateServiceDarwin=class extends c.t{celljs;logger;cachedFeedUpdate;shipItCacheDir;migrationCacheDir;currentBundleId;installResultPath;installLockPath;migrationFailureRecordPath;pendingUpdatePath;allowedBundleIds;installer=new MacBundleUpdateInstaller;pendingUpdate;installInProgress=!1;checkInProgress=!1;startupRestorePromise;downloadAbortController;updateAbandoned=!1;installFailureCount=0;MAX_INSTALL_FAILURES=3;constructor(e,t,r,i){super(t,r),this.celljs=i,this.logger=e;let a=n.T()?.darwinBundleIdentifier||`com.workbuddy.workbuddy`;this.currentBundleId=a,this.allowedBundleIds=new Set([...T,a]),this.shipItCacheDir=f.join(d.homedir(),`Library/Caches/${a}.ShipIt`),this.migrationCacheDir=f.join(d.homedir(),`Library/Caches/${a}.BundleMigration`),this.installResultPath=f.join(this.migrationCacheDir,`last-install-result.json`),this.installLockPath=f.join(this.migrationCacheDir,`install-in-progress.json`),this.migrationFailureRecordPath=f.join(this.migrationCacheDir,`failure-record.json`),this.pendingUpdatePath=f.join(this.migrationCacheDir,`pending-update.json`),this.setupListeners(),this.consumeLastInstallResult().catch(e=>{let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to consume last install result: ${t}`)}),this.startupRestorePromise=this.restoreThenCleanupOnStartup().catch(e=>{let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to restore/cleanup on startup: ${t}`)}),this.cleanupLegacyBundleMigrationDirs().catch(e=>{let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to cleanup legacy bundle migration dirs on startup: ${t}`)})}async waitForStartupRestore(){await this.startupRestorePromise}async shouldQuitForActiveInstallLock(){let e=await this.readActiveInstallLock();if(!e)return!1;if(!this.isNewVersion(e.version,this.version))return await this.removeInstallLockFile(),!1;if(e.phase!==`installing`)return!1;let t=e.currentPid;return typeof t!=`number`||!this.isProcessAlive(t)?(this.fileLogger.warn(`[darwin] Clearing stale install lock: writer pid=${t??`unknown`} is not alive, installer likely aborted (version=${e.version})`),await this.removeInstallLockFile(),!1):!0}isProcessAlive(e){if(!Number.isInteger(e)||e<=0)return!1;try{return process.kill(e,0),!0}catch(e){return e?.code!==`ESRCH`}}async restoreThenCleanupOnStartup(){let e=await this.restorePendingUpdate();await this.cleanupMigrationArtifacts(e?this.toSafePathPart(e):void 0);let t=await this.readActiveInstallLock();await this.cleanupStaleStagedApps([this.pendingUpdate?.stagedAppPath,t?.stagedAppPath])}async cleanupStaleStagedApps(e){try{let t=this.getCurrentAppPath();if(a.n(t))return;let{removed:n,failed:r}=await this.installer.removeStagedApps(t,e);for(let e of n)this.fileLogger.info(`[darwin] Removed stale staged app: ${e}`);for(let{path:e,message:t}of r)this.fileLogger.warn(`[darwin] Failed to remove stale staged app ${e}: ${t}`)}catch(e){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to cleanup stale staged apps: ${t}`)}}async restorePendingUpdate(){let e;try{let t=await g.readFile(this.pendingUpdatePath,`utf8`);e=JSON.parse(t)}catch{return}if(!e?.version||!e.extractedAppPath||!e.zipPath||!e.stagedAppPath){await this.clearPendingInstallState();return}if(!this.isNewVersion(e.version,this.version)){this.fileLogger.info(`[darwin] pending update ${e.version} <= current ${this.version}, treating as installed; clearing state`),await this.clearPendingInstallState();return}if(!await this.pathExists(e.stagedAppPath)){this.fileLogger.info(`[darwin] pending update staged app missing on disk (stagedAppPath=${e.stagedAppPath}); clearing state`),await this.clearPendingInstallState();return}return this.pendingUpdate=e,this.activeUpdateVersion=e.version,this.cachedFeedUpdate={version:e.version,releaseNotes:e.releaseNotes},this.setState(`ready`,{version:e.version,releaseNotes:e.releaseNotes}),this.fileLogger.info(`[darwin] Restored pending update from disk: version=${e.version}`),e.version}async persistPendingUpdate(e){try{await g.mkdir(f.dirname(this.pendingUpdatePath),{recursive:!0}),await g.writeFile(this.pendingUpdatePath,JSON.stringify(e),`utf8`),this.fileLogger.info(`[darwin] Persisted pending update: version=${e.version}`)}catch(e){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to persist pending update: ${t}`)}}abandonUpdate(){return this.installInProgress?(this.fileLogger.info(`[darwin] abandonUpdate ignored: install already in progress`),!1):(this.updateAbandoned=!0,this.downloadAbortController?.abort(`abandoned`),this.downloadAbortController=void 0,this.pendingUpdate=void 0,this.cachedFeedUpdate=void 0,g.rm(this.pendingUpdatePath,{force:!0}).catch(e=>{let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to remove pending update snapshot: ${t}`)}),super.abandonUpdate())}async removePendingUpdateFile(){await g.rm(this.pendingUpdatePath,{force:!0}).catch(()=>{})}async removeInstallLockFile(){await g.rm(this.installLockPath,{force:!0}).catch(()=>{})}async clearPendingInstallState(){await Promise.all([this.removePendingUpdateFile(),this.removeInstallLockFile()])}async writeInstallLock(e,t){let n={version:e.version,zipPath:e.zipPath,extractedAppPath:e.extractedAppPath,stagedAppPath:e.stagedAppPath,currentAppPath:e.currentAppPath,backupAppPath:e.backupAppPath,installResultPath:e.installResultPath,targetBundleId:e.targetBundleId,phase:t,createdAt:Date.now(),currentPid:t===`installing`?process.pid:void 0};await g.mkdir(f.dirname(this.installLockPath),{recursive:!0}),await g.writeFile(this.installLockPath,JSON.stringify(n),`utf8`),this.fileLogger.info(`[darwin] Wrote install lock: version=${e.version}, phase=${t}`)}async readActiveInstallLock(){let e;try{e=JSON.parse(await g.readFile(this.installLockPath,`utf8`))}catch{return}if(!e.version||!e.zipPath||!e.extractedAppPath||!e.stagedAppPath||!e.currentAppPath||!e.backupAppPath||!e.installResultPath||!e.targetBundleId||e.phase!==`prepared`&&e.phase!==`installing`||typeof e.createdAt!=`number`){await this.removeInstallLockFile();return}if(Date.now()-e.createdAt>M){this.fileLogger.info(`[darwin] Removing stale install lock: version=${e.version}, phase=${e.phase}`),await this.removeInstallLockFile();return}return e}async pathExists(e){try{return await g.stat(e),!0}catch{return!1}}reportMigrationEvent(e,n){this.celljs&&this.celljs.eventService.report(t.W.AppUpdate,{action:e,text:JSON.stringify(n)}).catch(()=>{})}markInstallChannelAutoUpdate(e){try{n.M(n.T(),{targetVersion:e,platform:`darwin`})}catch(e){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to mark install channel auto-update: ${t}`)}}classifyVerifyFailure(e){return o.t(e)}async readMigrationFailureRecord(){let e;try{e=await g.readFile(this.migrationFailureRecordPath,`utf8`)}catch(e){if(e?.code!==`ENOENT`){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to read migration failure record: ${t}`)}return}try{let t=JSON.parse(e);if(typeof t?.version==`string`&&typeof t.failureCount==`number`&&typeof t.lastFailureAt==`number`)return t;this.fileLogger.warn(`[darwin] Migration failure record has unexpected shape, treating as missing`);return}catch(e){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to parse migration failure record: ${t}`);return}}async writeMigrationFailureRecord(e,t){let n=await this.readMigrationFailureRecord(),r=n&&n.version===e?n.failureCount+1:1,i={version:e,failureCount:r,lastFailureAt:Date.now(),lastCode:t};try{await g.mkdir(f.dirname(this.migrationFailureRecordPath),{recursive:!0}),await g.writeFile(this.migrationFailureRecordPath,JSON.stringify(i),`utf8`),this.fileLogger.info(`[darwin] Migration failure recorded: version=${e}, failureCount=${r}, code=${t}`)}catch(e){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to persist migration failure record: ${t}`)}}async clearMigrationFailureRecord(){try{await g.rm(this.migrationFailureRecordPath,{force:!0})}catch{}}async isMigrationCircuitOpen(e){let t=await this.readMigrationFailureRecord();return!t||t.version!==e?{open:!1}:t.failureCount>=3?{open:!0,reason:`failure_limit_exceeded`,failureCount:t.failureCount,lastCode:t.lastCode}:Date.now()-t.lastFailureAt<864e5?{open:!0,reason:`cooldown_active`,failureCount:t.failureCount,lastCode:t.lastCode}:{open:!1}}setupListeners(){l.autoUpdater.on(`error`,e=>{let t=`autoUpdater error: ${e.message}`;this.logger?.error(`[UpdateService.darwin] ${t}`),this.fileLogger.error(`[darwin] ${t}\n${e.stack||``}`),this.isStateInstallable()?this.cleanupStaleShipItCache().catch(e=>{let t=`Failed to cleanup ShipIt cache after install-stage error: ${e instanceof Error?e.message:String(e)}`;this.logger?.warn(`[UpdateService.darwin] ${t}`),this.fileLogger.warn(`[darwin] ${t}`)}):this.fileLogger.info(`[darwin] Skipping ShipIt cache cleanup (state=${this.state}, likely transient network error)`),this.setState(`error`,void 0,void 0,{message:e.message,code:`UPDATE_ERROR`})}),l.autoUpdater.on(`before-quit-for-update`,()=>{this.logger?.info(`[UpdateService.darwin] Squirrel before-quit-for-update event`),this.fileLogger.info(`[darwin] Squirrel before-quit-for-update event`)}),l.autoUpdater.on(`checking-for-update`,()=>{this.logger?.info(`[UpdateService.darwin] Checking for updates...`),this.fileLogger.info(`[darwin] Checking for updates...`),this.setState(`checking`)}),l.autoUpdater.on(`update-available`,()=>{this.logger?.info(`[UpdateService.darwin] Update available, downloading...`),this.fileLogger.info(`[darwin] Update available, downloading...`),this.setState(`downloading`)}),l.autoUpdater.on(`update-not-available`,()=>{this.logger?.info(`[UpdateService.darwin] Update not available`),this.fileLogger.info(`[darwin] Update not available (current version is up to date)`),this.setState(`idle`)}),l.autoUpdater.on(`update-downloaded`,(e,t,n,r,i)=>{let a=n;!a&&this.cachedFeedUpdate&&(this.logger?.info(`[UpdateService.darwin] Squirrel returned empty version, using cached feed version: ${this.cachedFeedUpdate.version}`),this.fileLogger.info(`[darwin] Squirrel returned empty version, using cached feed version: ${this.cachedFeedUpdate.version}`),a=this.cachedFeedUpdate.version),this.logger?.info(`[UpdateService.darwin] Update downloaded: ${a}`),this.fileLogger.info(`[darwin] Update downloaded: version=${a}`),this.activeUpdateVersion=a||void 0,this.installFailureCount=0;let o={version:a||`unknown`,releaseNotes:t||this.cachedFeedUpdate?.releaseNotes||void 0};this.setState(`downloaded`,o),this.setState(`ready`,o)})}async checkForUpdates(e=!1){let t=this.state===`downloading`;if(this.checkInProgress&&!(e&&t)){this.logger?.info(`[UpdateService.darwin] checkForUpdates ignored: check already in progress`),this.fileLogger.info(`[darwin] checkForUpdates ignored: check already in progress`);return}let n=this.checkInProgress;this.checkInProgress=!0,this.updateAbandoned=!1;try{if(this.setLastExplicit(e),this.state===`downloaded`||this.state===`ready`||this.state===`downloading`){if(e&&this.state===`downloading`){this.logger?.info(`[UpdateService.darwin] Explicit check during in-flight download, re-emitting progress`),this.fileLogger.info(`[darwin] Explicit check re-emitting in-flight download progress`),this.setState(this.state,this.updateInfo,this.progress,void 0,{explicit:!0});return}if(await this.shouldSkipForActiveUpdate(this.state,e)){this.state===`idle`&&(this.pendingUpdate=void 0),this.logger?.info(`[UpdateService.darwin] Update already ${this.state}, latest version matches, skipping check`),this.fileLogger.info(`[darwin] Update already ${this.state}, latest version matches, skipping check`);return}if(e&&this.isStateInstallable()){this.logger?.info(`[UpdateService.darwin] Explicit check with installable update, re-emitting state`),this.fileLogger.info(`[darwin] Explicit check re-emitting ${this.state} for user`),this.setState(this.state,this.updateInfo,void 0,void 0,{explicit:!0});return}this.logger?.info(`[UpdateService.darwin] New version available on server, re-checking...`),this.fileLogger.info(`[darwin] New version available on server, re-checking...`)}let t=this.buildUpdateFeedUrl();this.logger?.info(`[UpdateService.darwin] Checking for updates with custom updater: ${this.redactUpdateUrl(t)}`),this.fileLogger.info(`[darwin] Checking for updates with custom updater: ${this.redactUpdateUrl(t)}`),await this.checkForUpdatesWithCustomUpdater(t)}catch(e){let t=e instanceof Error?e.message:String(e);if(this.updateAbandoned){this.logger?.info(`[UpdateService.darwin] checkForUpdates aborted by user: ${t}`),this.fileLogger.info(`[darwin] checkForUpdates aborted by user, keeping idle: ${t}`);return}this.logger?.error(`[UpdateService.darwin] checkForUpdates error: ${t}`),this.fileLogger.error(`[darwin] checkForUpdates error: ${t}`),this.setState(`error`,void 0,void 0,{message:e instanceof Error?e.message:`Unknown error`,code:`CHECK_ERROR`}),o.i({kind:`update`,outcome:`failed`,stage:`check`,error_code:o.t(e instanceof Error?e.message:`Unknown error`),from_version:this.version})}finally{this.checkInProgress=n}}updateTimingCheckStart=0;updateTimingFeedReceived=0;updateTimingDownloadStart=0;updateTimingDownloadDone=0;updateTimingVerifyDone=0;updateTimingExtractDone=0;async checkForUpdatesWithCustomUpdater(e){this.pendingUpdate=void 0,this.setState(`checking`),this.updateTimingCheckStart=Date.now();let n=await this.fetchUpdateFeed(e);if(!n){this.setState(`idle`);return}this.updateTimingFeedReceived=Date.now(),this.reportMigrationEvent(t.B.FeedMarked,{version:this.getFeedVersion(n),targetBundleId:n.targetBundleId,bundleIdMigration:n.bundleIdMigration??n.migration});let r=this.getFeedVersion(n);if(!r)throw Error(`Missing update version for mac bundle id migration update`);let i=c.i(n);if(i.length===0)throw Error(`Missing update download url for mac bundle id migration update`);let a=i[0].url;if(!this.isNewVersion(r,this.version)){this.logger?.info(`[UpdateService.darwin] No new version available (remote: ${r}, current: ${this.version})`),this.fileLogger.info(`[darwin] No new version available (remote: ${r}, current: ${this.version})`),this.setState(`idle`);return}let s=await this.isMigrationCircuitOpen(r);if(s.open){let e=s.reason===`failure_limit_exceeded`?`Mac bundle id migration update ${r} skipped: failed ${s.failureCount} times locally`:`Mac bundle id migration update ${r} skipped: cooling down after recent failure`;this.logger?.warn(`[UpdateService.darwin] ${e}`),this.fileLogger.warn(`[darwin] ${e}`),this.reportMigrationEvent(t.B.VerifyFailed,{version:r,code:`circuit_open`,reason:s.reason,failureCount:s.failureCount,lastCode:s.lastCode}),this.setState(`error`,void 0,void 0,{message:e,code:`MIGRATION_CIRCUIT_OPEN`}),o.i({kind:`update`,outcome:`failed`,stage:`download`,error_code:`circuit_open`,from_version:this.version,to_version:r});return}let l=this.getFeedReleaseNotes(n);this.setState(`available`,{version:r,downloadUrl:a,releaseNotes:l});let u;try{u=await this.downloadAndVerifyUpdate(n,r)}catch(e){let n=e instanceof Error?e.message:String(e);this.reportMigrationEvent(t.B.VerifyFailed,{version:r,code:this.classifyVerifyFailure(n),message:n}),o.i({kind:`update`,outcome:`failed`,stage:o.n(n),error_code:o.t(n),from_version:this.version,to_version:r}),this.setState(`error`,void 0,void 0,{message:n,code:`DOWNLOAD_ERROR`});return}await this.startupRestorePromise;let d,f;try{d=await this.installer.prepare(u),f=d.stagedAppPath,await this.validateBundleExecutable(d.stagedAppPath),await this.validateAppArchitecture(d.stagedAppPath),await this.validateAppCodeSignature(d.stagedAppPath);let e=await validateMacAsarIntegrity(d.stagedAppPath);this.fileLogger.info(`[darwin] ASAR integrity verified for staged app: expected=${e.expectedHash}, actual=${e.actualHash}`),await this.writeInstallLock(d,`prepared`)}catch(e){let n=e instanceof Error?e.message:String(e);f&&await this.installer.discardStagedApp(f).catch(e=>{let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to discard staged app ${f}: ${t}`)}),this.reportMigrationEvent(t.B.VerifyFailed,{version:r,code:this.classifyVerifyFailure(n),message:n}),o.i({kind:`update`,outcome:`failed`,stage:o.n(n),error_code:o.t(n),from_version:this.version,to_version:r}),this.setState(`error`,void 0,void 0,{message:n,code:`PREPARE_ERROR`});return}this.pendingUpdate=d,this.activeUpdateVersion=r,this.cachedFeedUpdate={version:r,releaseNotes:l};let p={version:r,downloadUrl:u.downloadUrl,releaseNotes:l};this.setState(`downloaded`,p),this.setState(`ready`,p),await this.persistPendingUpdate(d),await this.cleanupStaleStagedApps([d.stagedAppPath])}async fetchUpdateFeed(e){let t=await this.fetchFeedResponse(e);if(t.status===204){this.logger?.info(`[UpdateService.darwin] No update available (HTTP 204)`),this.fileLogger.info(`[darwin] No update available (HTTP 204)`);return}if(!t.ok)throw Error(`HTTP ${t.status} ${t.statusText}`);let n=await t.json();if(n&&typeof n==`object`)return n}getFeedVersion(e){let t=e.productVersion||e.version;return typeof t==`string`&&t.trim()?t.trim():void 0}getFeedReleaseNotes(e){let t=e.releaseNotes||e.notes;return typeof t==`string`&&t.trim()?t:void 0}async downloadAndVerifyUpdate(e,t){let n=typeof e.sha256hash==`string`?e.sha256hash.trim().toLowerCase():void 0;if(!n||!/^[a-f0-9]{64}$/.test(n))throw Error(`Missing or invalid SHA256 hash in macOS update feed`);let r=this.resolveTrustedDownloadCandidates(e),i=r[0].url,a=this.toSafePathPart(t),s=f.join(this.migrationCacheDir,`downloads`),c=f.join(this.migrationCacheDir,`extracted`,a),l=f.join(this.migrationCacheDir,`backups`);await this.cleanupMigrationArtifacts(a),await g.mkdir(s,{recursive:!0}),await g.mkdir(l,{recursive:!0});let u=f.join(s,`WorkBuddy-${a}.zip`),d=`${u}.tmp`,p=`${d}.etag`,m=await this.isValidCachedZip(u,n),h=!1,_=`default`,v=0;if(m)this.fileLogger.info(`[darwin] Reusing cached download: ${u}`),this.updateTimingDownloadStart=Date.now(),this.updateTimingDownloadDone=Date.now(),this.updateTimingVerifyDone=Date.now();else{await g.rm(u,{force:!0}),h=!0,this.setState(`downloading`),this.updateTimingDownloadStart=Date.now(),o.i({kind:`update`,outcome:`started`,stage:`download`,from_version:this.version,to_version:t});try{let t=await this.downloadWithCandidates(r,d,p,e.url,n);i=t.candidate.url,_=t.candidate.source,v=t.fallbackDepth,this.updateTimingDownloadDone=Date.now(),this.updateTimingVerifyDone=Date.now(),await g.rename(d,u),await g.rm(p,{force:!0}).catch(()=>{})}catch(e){throw this.isDownloadCorruptionError(e)&&(await g.rm(d,{force:!0}).catch(()=>{}),await g.rm(p,{force:!0}).catch(()=>{})),e}}await this.forceRemoveDir(c),await g.mkdir(c,{recursive:!0}),await this.extractZip(u,c),this.updateTimingExtractDone=Date.now();let y=await this.findExtractedApp(c),b=await this.readPlistValue(y,`CFBundleIdentifier`);this.validateTargetBundleId(b,e.targetBundleId),this.validateMigrationTargetBundleId(b),await this.validateBundleExecutable(y),await this.validateAppArchitecture(y),await this.validateAppCodeSignature(y);let x=await validateMacAsarIntegrity(y);this.fileLogger.info(`[darwin] ASAR integrity verified for extracted app: expected=${x.expectedHash}, actual=${x.actualHash}`);let S=this.getCurrentAppPath();return await this.validateInstallPreflight(S,y),h&&o.i({kind:`update`,outcome:`succeeded`,stage:`download`,from_version:this.version,to_version:t,download_source:_,fallback_depth:v},{persist:`pending`}),{version:t,downloadUrl:i,zipPath:u,extractedAppPath:y,currentAppPath:S,backupAppPath:f.join(l,`WorkBuddy-${a}-${Date.now()}.backup.app`),installResultPath:this.installResultPath,targetBundleId:b,releaseNotes:this.getFeedReleaseNotes(e)}}resolveTrustedDownloadCandidates(e){let t=c.i(e);if(t.length===0)throw Error(`Missing update download url`);let n=[],r;for(let e of t)try{this.validateDownloadUrl(e.url),n.push(e)}catch(t){r=t;let n=t instanceof Error?t.message:String(t);this.fileLogger.warn(`[darwin] Skipping untrusted download candidate (${e.source}): ${n}`)}if(n.length===0)throw r instanceof Error?r:Error(`Missing update download url`);return n}async downloadWithCandidates(e,t,n,r,i){let a;for(let o=0;o<e.length;o++){let s=e[o],l=c.r(s,o,e.length);o>0&&(await g.rm(t,{force:!0}).catch(()=>{}),await g.rm(n,{force:!0}).catch(()=>{}));try{return this.fileLogger.info(`[darwin] Downloading update with candidate ${l}`),await this.downloadFile(s.url,t,{allowLegacyResumeEtag:!!r&&s.url===r}),await this.verifyDownloadedFile(t,i),o>0&&this.fileLogger.info(`[darwin] Download succeeded after falling back to candidate ${l}`),{candidate:s,fallbackDepth:o}}catch(e){if(!c.a(e))throw e;a=e;let t=e instanceof Error?e.message:String(e);this.logger?.warn(`[UpdateService.darwin] Download candidate ${l} failed: ${t}`),this.fileLogger.warn(`[darwin] Download candidate ${l} failed: ${t}`)}}throw a instanceof Error?a:Error(`Download failed: all candidate urls exhausted`)}validateDownloadUrl(e){let t;try{t=new URL(e)}catch{throw Error(`Invalid update download url`)}if(t.protocol!==`https:`&&(t.protocol!==`http:`||!([`localhost`,`127.0.0.1`,`::1`].includes(t.hostname)||this.isTrustedHttpUpdateOrigin(t))))throw Error(`Unsupported update download protocol: ${t.protocol}`)}isTrustedHttpUpdateOrigin(e){let t=this.updateBaseUrlProvider?.getUpdateBaseUrl();if(!t)return!1;let n;try{n=new URL(t)}catch{return!1}return n.protocol===`http:`&&(n.host===e.host||this.fileLogger.info(`[darwin] Allowing cross-host http update download within private http deployment: feedHost=${n.host}, downloadHost=${e.host}`),!0)}async validateInstallPreflight(e,t){if(!e.endsWith(`.app`))throw Error(`Current app path is not a macOS app bundle: ${e}`);if(a.n(e))throw Error(`Current app path cannot be replaced automatically (mounted volume or translocated): ${e}`);let n=f.dirname(e);await this.assertDirectoryWritable(n);let r=await this.getPathSizeBytes(e)+await this.getPathSizeBytes(t)+k,i=await this.getAvailableDiskBytes(n);if(i<r)throw Error(`Insufficient free disk space for mac bundle id migration update: required ${r} bytes, available ${i} bytes`)}async assertDirectoryWritable(e){let t=f.join(e,`.workbuddy-update-preflight-${process.pid}-${Date.now()}`);try{await g.writeFile(t,`ok`)}catch(t){throw Error(`Update target directory is not writable: ${e} (${t instanceof Error?t.message:String(t)})`)}finally{try{await g.rm(t,{force:!0})}catch{}}}async getAvailableDiskBytes(e){let t=await g.statfs(e);return t.bavail*t.bsize}async getPathSizeBytes(e){try{await g.stat(e)}catch{return 0}let{stdout:t}=await D(`/usr/bin/du`,[`-sk`,e]),n=parseInt(t.trim().split(/\s+/)[0]||`0`,10);return Math.max(0,n)*1024}async downloadFile(e,t,n){let r=this.redactUpdateUrl(e);this.logger?.info(`[UpdateService.darwin] Downloading update from: ${r}`),this.fileLogger.info(`[darwin] Downloading update from: ${r}`);let i=new AbortController;this.downloadAbortController=i;let a=setTimeout(()=>i.abort(`max_timeout`),j),o,resetStall=()=>{o!==void 0&&clearTimeout(o),o=setTimeout(()=>i.abort(`stall_timeout`),A)};try{let r=0,s,c=`${t}.etag`;try{r=(await g.stat(t)).size,r>0&&(s=await this.readResumeEtag(c,e,n?.allowLegacyResumeEtag===!0))}catch{}r>0&&!s&&(r=0);let d={"Accept-Encoding":`identity`,Range:`bytes=${r}-`};r>0&&s&&(d[`If-Range`]=s,this.fileLogger.info(`[darwin] Attempting resume from byte ${r}`)),resetStall();let f=await l.net.fetch(e,{signal:i.signal,headers:d}),p,m,h;if(f.status===206)m=this.parseContentRangeTotal(f.headers.get(`content-range`))||0,p=r,h=r>0?`a`:`w`,r>0&&this.fileLogger.info(`[darwin] Resume accepted, continuing from ${r}/${m}`);else if(f.ok)m=parseInt(f.headers.get(`content-length`)||`0`,10)||0,p=0,h=`w`,r>0&&this.fileLogger.info(`[darwin] Resume not accepted (HTTP ${f.status}), restarting full download`);else if(f.status===416){this.fileLogger.warn(`[darwin] Resume rejected with HTTP 416, discarding partial file and restarting`),clearTimeout(a),o!==void 0&&clearTimeout(o),await g.rm(t,{force:!0}).catch(()=>{}),await g.rm(c,{force:!0}).catch(()=>{}),await this.downloadFile(e,t);return}else throw Error(`Download failed: HTTP ${f.status} ${f.statusText}`);{let e=f.headers.get(`content-length`),t=f.headers.get(`content-range`),n=f.headers.get(`transfer-encoding`);this.fileLogger.info(`[darwin] Download size headers: status=${f.status}, content-length=${e??`<none>`}, content-range=${t??`<none>`}, transfer-encoding=${n??`<none>`}, resolvedTotalSize=${m}`),m<=0&&this.fileLogger.warn(`[darwin] totalSize=0 (missing content-length/content-range). Progress will be reported as indeterminate (no percent) \u2014 this is usually caused by a proxy (e.g. whistle) stripping the size header. Download itself is unaffected.`)}if(f.status!==206||r===0){let t=f.headers.get(`etag`);t&&await g.writeFile(c,JSON.stringify({url:e,etag:t})).catch(()=>{})}if(!f.body)throw Error(`Download failed: response body is empty`);let _=u.createWriteStream(t,{flags:h}),v=f.body.getReader(),y=Date.now(),b=0,x=m>0,S=0;await new Promise((e,t)=>{_.on(`error`,t);let pump=()=>{v.read().then(({done:t,value:n})=>{if(t){let t=(Date.now()-y)/1e3;this.fileLogger.info(`[darwin] Download stream complete: transferred=${p} bytes, total=${m||`<unknown>`}, elapsed=${t.toFixed(1)}s`),_.end(()=>e());return}resetStall(),p+=n.byteLength;let r=x?p/m*100:0,i=Date.now();if(i-b>=2e3){b=i;let e=(i-y)/1e3,t=e>0?p/e:0;this.fileLogger.info(`[darwin] Download progress: transferred=${p}${x?`/${m}`:` (total unknown)`}, percent=${r.toFixed(1)}%, avgBps=${Math.round(t)}`)}i-S>=200&&(S=i,x?this.setState(`downloading`,void 0,{percent:r,bytesPerSecond:0,total:m,transferred:p}):this.setState(`downloading`)),_.write(Buffer.from(n))?pump():_.once(`drain`,pump)}).catch(t)};pump()})}finally{clearTimeout(a),o!==void 0&&clearTimeout(o),this.downloadAbortController===i&&(this.downloadAbortController=void 0)}}async readResumeEtag(e,t,n){let r;try{r=(await g.readFile(e,`utf-8`)).trim()}catch{return}if(r){try{let e=JSON.parse(r);if(e&&typeof e==`object`&&typeof e.etag==`string`&&e.etag)return e.url===t?e.etag:void 0}catch{}return n?r:void 0}}parseContentRangeTotal(e){if(!e)return;let t=/\/(\d+)$/.exec(e);return t?parseInt(t[1],10):void 0}isDownloadCorruptionError(e){if(!(e instanceof Error))return!1;let t=e.message;return t.includes(`too small`)||t.includes(`hash mismatch`)||t.includes(`invalid`)}async verifyDownloadedFile(e,t){let n=await g.stat(e);if(n.size<O)throw Error(`Downloaded file is too small (${n.size} bytes), possibly invalid`);let r=await this.computeFileSha256(e);if(r!==t)throw Error(`SHA256 hash mismatch for macOS update: expected ${t}, got ${r}`);this.fileLogger.info(`[darwin] Update ZIP SHA256 verified`)}async computeFileSha256(e){let t=(0,h.createHash)(`sha256`);for await(let n of u.createReadStream(e))t.update(n);return t.digest(`hex`)}async isValidCachedZip(e,t){try{return await this.verifyDownloadedFile(e,t),!0}catch{return!1}}async extractZip(e,t){await D(`/usr/bin/ditto`,[`-x`,`-k`,e,t]),this.fileLogger.info(`[darwin] Extracted update zip to ${t}`)}async findExtractedApp(e){let t=[{dir:e,depth:0}],n=[];for(;t.length>0;){let e=t.shift();if(!e||e.depth>3)continue;let r=await g.readdir(e.dir,{withFileTypes:!0});for(let i of r){if(!i.isDirectory())continue;let r=f.join(e.dir,i.name);if(i.name.endsWith(`.app`)){n.push(r);continue}t.push({dir:r,depth:e.depth+1})}}if(n.length!==1)throw Error(`Expected exactly one .app in update zip, found ${n.length}`);return n[0]}async readPlistValue(e,t){let n=f.join(e,`Contents`,`Info.plist`),{stdout:r}=await D(`/usr/libexec/PlistBuddy`,[`-c`,`Print :${t}`,n]),i=r.trim();if(!i)throw Error(`Missing ${t} in ${n}`);return i}validateTargetBundleId(e,t){if(!this.allowedBundleIds.has(e))throw Error(`Unexpected update bundle id: ${e}`);if(t&&t!==e)throw Error(`Feed targetBundleId ${t} does not match package bundle id ${e}`)}validateMigrationTargetBundleId(e){if(!this.allowedBundleIds.has(e))throw Error(`Update bundle id ${e} is not in the allowed set`);this.fileLogger.info(`[darwin] update target bundle id verified: ${e}`)}async validateBundleExecutable(e){let t=await this.readPlistValue(e,`CFBundleExecutable`);if(t!==`Electron`)throw Error(`Unexpected CFBundleExecutable: ${t}`)}async validateAppArchitecture(e){let t=f.join(e,`Contents`,`MacOS`,`Electron`),n=await this.detectAppArchitectures(t),r=this.getRequiredMacArchitecture();if(!n.includes(r))throw Error(`Update app architecture mismatch: required ${r}, got ${n.join(`,`)||`unknown`}`);this.fileLogger.info(`[darwin] Update app architectures verified: ${n.join(`,`)}`)}getRequiredMacArchitecture(){return process.arch===`arm64`?`arm64`:`x86_64`}async detectAppArchitectures(e){try{return await this.readMachOArchitectures(e)}catch(t){let n=this.formatArchProbeError(t);this.fileLogger.warn(`[darwin] Mach-O architecture probe failed, falling back to file: ${n}`);try{let t=await this.readArchitecturesWithFile(e);return this.fileLogger.info(`[darwin] Update app architectures detected by file: ${t.join(`,`)}`),t}catch(e){let t=this.formatArchProbeError(e);throw Error(`Unable to determine update app architecture: Mach-O probe failed: ${n}; file probe failed: ${t}`)}}}async readMachOArchitectures(e){let t=await this.readFileHeader(e),n=this.parseMachOArchitectures(t);if(n.length===0)throw Error(`No supported architectures found in Mach-O header`);return n}async readFileHeader(e){let t=await g.open(e,`r`);try{let e=Buffer.alloc(P),{bytesRead:n}=await t.read(e,0,e.length,0);if(n<8)throw Error(`Mach-O header too short: ${n} bytes`);return e.subarray(0,n)}finally{await t.close()}}parseMachOArchitectures(e){let t=this.parseFatMachOArchitectures(e);return t===void 0?this.parseThinMachOArchitectures(e):t}parseFatMachOArchitectures(e){let t=e.readUInt32BE(0),n=t===F||t===L;if(!n&&t!==I&&t!==R)return;let r=n?e.readUInt32BE(4):e.readUInt32LE(4),i=t===L||t===R?32:20,a=8+r*i;if(r===0||r>128||a>e.length)throw Error(`Invalid Mach-O fat header: nfat_arch=${r}, bytes=${e.length}`);let o=new Set;for(let t=0;t<r;t+=1){let r=8+t*i,a=n?e.readInt32BE(r):e.readInt32LE(r),s=this.mapCpuTypeToArchitecture(a);s&&o.add(s)}return[...o]}parseThinMachOArchitectures(e){let t=e.readUInt32LE(0),n=e.readUInt32BE(0),r=t===z||t===B;if(!r&&n!==z&&n!==B)throw Error(`Unsupported Mach-O magic: 0x${n.toString(16)}`);let i=r?e.readInt32LE(4):e.readInt32BE(4),a=this.mapCpuTypeToArchitecture(i);return a?[a]:[]}mapCpuTypeToArchitecture(e){switch(e){case H:return`arm64`;case V:return`x86_64`;default:return}}async readArchitecturesWithFile(e){let{stdout:t}=await D(`/usr/bin/file`,[`-b`,e]),n=t.trim().toLowerCase(),r=new Set;if(/\barm64e?\b/.test(n)&&r.add(`arm64`),/\bx86_64h?\b/.test(n)&&r.add(`x86_64`),r.size===0)throw Error(`Unable to parse file architecture output: ${this.formatArchProbeError(t.trim()||`empty output`)}`);return[...r]}formatArchProbeError(e){let t=(e instanceof Error?e.message:String(e)).replace(/\s+/g,` `).trim();return t.length<=N?t:`${t.slice(0,N)}...`}async validateAppCodeSignature(e){try{await D(`/usr/bin/codesign`,[`--verify`,`--deep`,`--strict`,`--verbose=2`,`-R=anchor apple generic and certificate leaf[subject.OU] = "${w}"`,e])}catch(e){let t=e?.stderr??``,n=e instanceof Error?e.message:String(e),r=t.split(`
`).filter(Boolean).slice(0,2).join(` | `)||n;throw Error(`Code signature verification failed for update app: ${r}`)}this.fileLogger.info(`[darwin] Code signature verified for ${e}`)}getCurrentAppPath(){let e=process.execPath.split(f.sep),t=e.findIndex(e=>e.endsWith(`.app`));if(t<0)throw Error(`Cannot resolve current .app path from execPath: ${process.execPath}`);return e.slice(0,t+1).join(f.sep)||f.sep}toSafePathPart(e){return e.replace(/[^a-zA-Z0-9._-]/g,`_`)}redactUpdateUrl(e){try{let t=new URL(e);for(let e of Array.from(t.searchParams.keys()))/user|tenant|machine|token|key|auth/i.test(e)&&t.searchParams.set(e,`***`);return t.toString()}catch{return e}}isNewVersion(e,t){let parse=e=>e.split(`-`,1)[0].split(`.`).map(e=>parseInt(e,10)||0),n=parse(e),r=parse(t);for(let e=0;e<Math.min(n.length,r.length);e++){let t=n[e]||0,i=r[e]||0;if(t>i)return!0;if(t<i)return!1}return!1}async consumeLastInstallResult(){let e;try{e=await g.readFile(this.installResultPath,`utf8`)}catch(e){if(e?.code!==`ENOENT`){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to read last install result: ${t}`)}return}try{await g.rm(this.installResultPath,{force:!0})}catch{}try{let n=JSON.parse(e);if(this.reportMigrationEvent(t.B.InstallConsumed,{success:n.success,code:n.code,version:n.version,targetBundleId:n.targetBundleId}),n.success){let e=n.version??`unknown`,t=n.targetBundleId??`unknown`;this.fileLogger.info(`[darwin] Previous bundle migration install succeeded: version=${e}, bundleId=${t}`),await this.clearMigrationFailureRecord(),await this.clearPendingInstallState();return}let r=`Previous bundle migration install failed (${n.code})${n.version?` for version ${n.version}`:``}`;this.logger?.warn(`[UpdateService.darwin] ${r}`),this.fileLogger.warn(`[darwin] ${r}`),n.version&&await this.writeMigrationFailureRecord(n.version,n.code),await this.removeInstallLockFile(),this.setState(`error`,void 0,void 0,{message:r,code:`INSTALL_ERROR`}),o.i({kind:`update`,outcome:`failed`,stage:`apply`,error_code:n.code||`install_failed`,from_version:this.version,to_version:n.version})}catch(e){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to parse last install result: ${t}`)}}quitAndInstall(){if(this.pendingUpdate){this.quitAndInstallCustomUpdate();return}if(!this.isStateInstallable()){if(this.activeUpdateVersion){let e=`State is '${this.state}' (not installable) but activeUpdateVersion=${this.activeUpdateVersion} exists, attempting install anyway`;this.logger?.warn(`[UpdateService.darwin] ${e}`),this.fileLogger.warn(`[darwin] ${e}`)}else{let e=`quitAndInstall ignored: no installable update (current state=${this.state}, no activeUpdateVersion)`;this.logger?.warn(`[UpdateService.darwin] ${e}`),this.fileLogger.warn(`[darwin] ${e}`);return}}try{if(this.logger?.info(`[UpdateService.darwin] Quitting and installing...`),this.fileLogger.info(`[darwin] Quitting and installing via Squirrel (state=${this.state}, activeUpdateVersion=${this.activeUpdateVersion??`none`}, pid=${process.pid})`),this.installFailureCount++,this.installFailureCount>this.MAX_INSTALL_FAILURES){this.logger?.error(`[UpdateService.darwin] Installation failed ${this.installFailureCount} times, cleaning ShipIt cache`),this.fileLogger.error(`[darwin] Installation failed ${this.installFailureCount} times, cleaning ShipIt cache`),this.cleanupStaleShipItCache().then(()=>{this.logger?.info(`[UpdateService.darwin] ShipIt cache cleaned, user should check for updates again`),this.fileLogger.info(`[darwin] ShipIt cache cleaned, user should check for updates again`),this.setState(`idle`)}).catch(e=>{this.logger?.error(`[UpdateService.darwin] Failed to cleanup ShipIt cache: ${e instanceof Error?e.message:String(e)}`),this.fileLogger.error(`[darwin] Failed to cleanup ShipIt cache: ${e instanceof Error?e.message:String(e)}`),this.setState(`idle`)});return}this.logger?.info(`[darwin] Calling autoUpdater.quitAndInstall()`),this.fileLogger.info(`[darwin] Calling autoUpdater.quitAndInstall()`),this.fileLogger.info(`[darwin] Emitting before-quit-for-update on app`),l.app.emit(`before-quit-for-update`),this.fileLogger.info(`[darwin] before-quit-for-update emitted, now calling autoUpdater.quitAndInstall()`),this.markInstallChannelAutoUpdate(this.activeUpdateVersion),o.i({kind:`update`,outcome:`started`,stage:`apply`,from_version:this.version,to_version:this.activeUpdateVersion},{persist:`pending`}),l.autoUpdater.quitAndInstall(),this.ensureLaunchAfterInstallation(),this.fileLogger.info(`[darwin] autoUpdater.quitAndInstall() returned, requesting app.quit() without bypassing native quit flow`),l.app.quit(),this.fileLogger.info(`[darwin] app.quit() requested; waiting for Squirrel/ShipIt to continue install and relaunch`),setTimeout(()=>{this.logger?.warn(`[UpdateService.darwin] abnormal fallback: quitAndInstall did not exit after 5 seconds; forcing exit may skip relaunch`),this.fileLogger.warn(`[darwin] abnormal fallback: quitAndInstall did not exit after 5 seconds; forcing app.exit(0), relaunch may be skipped`),l.app.exit(0)},5e3).unref?.()}catch(e){let t=e instanceof Error?e.message:String(e);this.logger?.error(`[UpdateService.darwin] quitAndInstall error: ${t}`),this.fileLogger.error(`[darwin] quitAndInstall error: ${t}`),o.i({kind:`update`,outcome:`failed`,stage:`apply`,error_code:o.t(t),from_version:this.version,to_version:this.activeUpdateVersion},{persist:`pending`}),this.cleanupStaleShipItCache().catch(e=>{this.logger?.warn(`[UpdateService.darwin] Failed to cleanup ShipIt cache: ${e instanceof Error?e.message:String(e)}`)})}}quitAndInstallCustomUpdate(){if(!this.pendingUpdate){this.fileLogger.warn(`[darwin] custom quitAndInstall ignored: no pending update`);return}if(this.installInProgress){this.fileLogger.warn(`[darwin] custom quitAndInstall ignored: install already in progress`);return}if(!this.isStateInstallable()){let e=`custom quitAndInstall ignored: state=${this.state} is not installable`;this.logger?.warn(`[UpdateService.darwin] ${e}`),this.fileLogger.warn(`[darwin] ${e}`);return}let e=this.pendingUpdate;this.installInProgress=!0;try{s.t({fromVersion:this.version,toVersion:e.version,targetBundleId:e.targetBundleId,checkStart:this.updateTimingCheckStart,feedReceived:this.updateTimingFeedReceived,downloadStart:this.updateTimingDownloadStart,downloadDone:this.updateTimingDownloadDone,verifyDone:this.updateTimingVerifyDone,extractDone:this.updateTimingExtractDone,installSpawn:Date.now()})}catch(e){this.fileLogger.warn(`[darwin] Failed to write update timing: ${e instanceof Error?e.message:String(e)}`)}o.i({kind:`update`,outcome:`started`,stage:`apply`,from_version:this.version,to_version:e.version},{persist:`pending`}),this.writeInstallLock(e,`installing`).then(()=>this.installer.install(e,process.pid,this.installLockPath)).then(()=>{this.logger?.info(`[UpdateService.darwin] Custom installer spawned for version=${e.version}, bundleId=${e.targetBundleId}`),this.fileLogger.info(`[darwin] Custom installer spawned for version=${e.version}, bundleId=${e.targetBundleId}`),this.reportMigrationEvent(t.B.HelperSpawned,{version:e.version,targetBundleId:e.targetBundleId}),this.markInstallChannelAutoUpdate(e.version),this.fileLogger.info(`[darwin] Emitting before-quit-for-update on app`),l.app.emit(`before-quit-for-update`),l.app.quit(),setTimeout(()=>{this.logger?.warn(`[UpdateService.darwin] custom quitAndInstall did not quit after 5 seconds, forcing exit`),this.fileLogger.warn(`[darwin] custom quitAndInstall did not quit after 5 seconds, forcing exit`),l.app.exit(0)},5e3)}).catch(t=>{this.installInProgress=!1;let n=t instanceof Error?t.message:String(t);this.logger?.error(`[UpdateService.darwin] custom quitAndInstall error: ${n}`),this.fileLogger.error(`[darwin] custom quitAndInstall error: ${n}`),this.setState(`error`,void 0,void 0,{message:n,code:`INSTALL_ERROR`}),o.i({kind:`update`,outcome:`failed`,stage:`apply`,error_code:o.t(n),from_version:this.version,to_version:e.version},{persist:`pending`})})}ensureLaunchAfterInstallation(){let e=f.join(this.shipItCacheDir,`ShipItState.plist`);try{if(!u.existsSync(e)){this.fileLogger.warn(`[darwin] ShipItState.plist not found at ${e}, cannot patch launchAfterInstallation`);return}let t=u.readFileSync(e,`utf-8`),n=t.trimStart();if(this.fileLogger.info(`[darwin] ShipItState.plist detected format=${n.startsWith(`{`)?`JSON`:`XML/binary`}, size=${t.length}B, path=${e}`),n.startsWith(`{`)){let n=JSON.parse(t),r=n.launchAfterInstallation;n.launchAfterInstallation=!0,u.writeFileSync(e,JSON.stringify(n),`utf-8`),this.fileLogger.info(`[darwin] Patched ShipItState.plist (JSON): launchAfterInstallation ${r} -> true`)}else(0,m.execFileSync)(`/usr/libexec/PlistBuddy`,[`-c`,`Set :launchAfterInstallation true`,e],{timeout:3e3}),this.fileLogger.info(`[darwin] Patched ShipItState.plist (PlistBuddy): launchAfterInstallation=true`)}catch(e){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to patch ShipItState.plist launchAfterInstallation: ${t}`)}}async cleanupStaleShipItCache(){try{if(!(await g.stat(this.shipItCacheDir).catch(()=>null))?.isDirectory()){this.logger?.debug(`[UpdateService.darwin] ShipIt cache directory does not exist: ${this.shipItCacheDir}`);return}let e=(await g.readdir(this.shipItCacheDir,{withFileTypes:!0})).filter(e=>e.isDirectory()&&e.name.startsWith(`update.`));if(e.length===0){this.logger?.info(`[UpdateService.darwin] No update directories found in ShipIt cache`);return}this.logger?.info(`[UpdateService.darwin] Found ${e.length} update directories in ShipIt cache, removing them...`),this.fileLogger.info(`[darwin] Found ${e.length} update directories in ShipIt cache, removing them...`);for(let t of e){let e=f.join(this.shipItCacheDir,t.name);try{await g.rm(e,{recursive:!0,force:!0}),this.logger?.info(`[UpdateService.darwin] Removed update directory: ${t.name}`),this.fileLogger.info(`[darwin] Removed update directory: ${t.name}`)}catch(e){this.logger?.warn(`[UpdateService.darwin] Failed to remove directory ${t.name}: ${e instanceof Error?e.message:String(e)}`),this.fileLogger.warn(`[darwin] Failed to remove directory ${t.name}: ${e instanceof Error?e.message:String(e)}`)}}this.logger?.info(`[UpdateService.darwin] ShipIt cache cleanup completed`),this.fileLogger.info(`[darwin] ShipIt cache cleanup completed`)}catch(e){let t=e instanceof Error?e.message:String(e);this.logger?.warn(`[UpdateService.darwin] Error during ShipIt cache cleanup: ${t}`),this.fileLogger.warn(`[darwin] Error during ShipIt cache cleanup: ${t}`)}}async forceRemoveDir(e){try{await g.rm(e,{recursive:!0,force:!0});return}catch(t){this.fileLogger.warn(`[darwin] fs.rm failed for ${e}: ${t instanceof Error?t.message:String(t)}, retrying after 500ms`)}await new Promise(e=>setTimeout(e,500));try{await g.rm(e,{recursive:!0,force:!0});return}catch{}try{await D(`/bin/rm`,[`-rf`,e]),this.fileLogger.info(`[darwin] Fallback /bin/rm -rf succeeded for ${e}`)}catch(t){throw this.fileLogger.error(`[darwin] forceRemoveDir failed for ${e}: ${t instanceof Error?t.message:String(t)}`),t}}async cleanupLegacyBundleMigrationDirs(){for(let e of T){if(e===this.currentBundleId)continue;let t=f.join(d.homedir(),`Library/Caches/${e}.BundleMigration`);if((await g.stat(t).catch(()=>void 0))?.isDirectory())try{await this.forceRemoveDir(t),this.fileLogger.info(`[darwin] Removed legacy bundle migration cache dir: ${t}`)}catch(e){let n=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to remove legacy bundle migration cache dir ${t}: ${n}`)}}}async cleanupMigrationArtifacts(e){if(!(await g.stat(this.migrationCacheDir).catch(()=>void 0))?.isDirectory())return;let t=e?void 0:await this.readActiveInstallLock(),n=e??(t?this.toSafePathPart(t.version):void 0);t&&this.fileLogger.info(`[darwin] Active install lock protects migration artifacts: version=${t.version}, phase=${t.phase}`);let r=f.join(this.migrationCacheDir,`downloads`),i=f.join(this.migrationCacheDir,`extracted`),a=f.join(this.migrationCacheDir,`backups`);await this.cleanupOldDownloadZips(r,n),await this.cleanupOldExtractedApps(i,n),await this.cleanupOldBackupApps(a,t?.backupAppPath)}async cleanupOldDownloadZips(e,t){let n=await g.readdir(e).catch(()=>[]),r=t?new Set([`WorkBuddy-${t}.zip`,`WorkBuddy-${t}.zip.tmp`,`WorkBuddy-${t}.zip.tmp.etag`]):void 0;for(let t of n){if(r?.has(t))continue;let n=f.join(e,t);try{await g.rm(n,{force:!0}),this.fileLogger.info(`[darwin] Cleaned migration download: ${t}`)}catch(e){let n=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to clean migration download ${t}: ${n}`)}}}async cleanupOldExtractedApps(e,t){let n=await g.readdir(e,{withFileTypes:!0}).catch(()=>[]);for(let r of n){if(!r.isDirectory()||t&&r.name===t)continue;let n=f.join(e,r.name);try{await this.forceRemoveDir(n),this.fileLogger.info(`[darwin] Cleaned migration extract: ${r.name}`)}catch(e){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to clean migration extract ${r.name}: ${t}`)}}}async cleanupOldBackupApps(e,t){let n=await g.readdir(e,{withFileTypes:!0}).catch(()=>[]),r=[];for(let t of n){if(!t.name.endsWith(`.backup.app`))continue;let n=f.join(e,t.name),i=await g.stat(n).catch(()=>void 0);i&&r.push({name:t.name,mtimeMs:i.mtimeMs})}if(r.length<=1)return;r.sort((e,t)=>t.mtimeMs-e.mtimeMs);let i=r.slice(1);for(let{name:n}of i){let r=f.join(e,n);if(!(t&&r===t))try{await this.forceRemoveDir(r),this.fileLogger.info(`[darwin] Cleaned migration backup: ${n}`)}catch(e){let t=e instanceof Error?e.message:String(e);this.fileLogger.warn(`[darwin] Failed to clean migration backup ${n}: ${t}`)}}}};exports.UpdateServiceDarwin=UpdateServiceDarwin;