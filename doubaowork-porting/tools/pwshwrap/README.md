# pwshwrap（实验，暂不可用）

给应用自带的 `pwsh.exe` 套一层 ConPTY 中转的 PE 包装器，用于验证「Wine 下 .NET 控制台程序
在管道 stdio 时不执行」能否绕开。

## 原理

应用用管道调用 `pwsh.exe`，而 Wine 11 下 .NET 只有在 stdio 是终端时才正常。包装器：

1. `CreatePseudoConsole()` 建一个伪控制台；
2. 用 `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` 启动真正的 `pwsh-real.exe`；
3. 在自身 stdin/stdout（应用的管道）与伪控制台之间双向转发。

## 构建

```bash
./build.sh          # 需要 x86_64-w64-mingw32-gcc
```

## 用法（实验）

```bash
cp -a <pwsh 目录> /tmp/t && mv /tmp/t/pwsh.exe /tmp/t/pwsh-real.exe
cp pwshwrap.exe /tmp/t/pwsh.exe
WINEPREFIX=... wine /tmp/t/pwsh.exe -NoProfile -Command "..."
```

`PWSHWRAP_DEBUG=1` 会打印 `CreatePseudoConsole` 的 HRESULT 与属性设置结果。

## 实测结论（2026-11-23，Wine 11.0）

- ConPTY 本身可用：`cmd /c echo hi` 经包装器能正常回传输出；
- `CreatePseudoConsole` 返回 `S_OK`，`EXTENDED_STARTUPINFO_PRESENT` 生效；
- 但真正的 `pwsh.exe` 仍然失败：
  `System.IO.FileNotFoundException: Could not load file or assembly '...\System.Runtime.dll'`
  与管道直连时一模一样；
- 同一二进制在个别前缀 + 真实 Unix PTY 组合下曾成功，但无法稳定复现。

结论：Wine 的 ConPTY 不能替代真实终端，这条路走不通；需要 Wine 侧修复 .NET 的
程序集加载/控制台处理。
