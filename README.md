# explorer-shell-fix

[English](#english) | [中文](#中文)

---

## 中文

诊断并**可逆禁用**导致 Windows 资源管理器白屏 / 双击无反应的第三方 **Shell 扩展**（图标覆盖、右键菜单等）。  
不卸载软件，机制与 [ShellExView](https://www.nirsoft.net/utils/shexview.html) 的 Blocked 列表一致。

### 典型症状

- 打开文件夹内容区白屏，结束「Windows 资源管理器」后暂时恢复  
- 双击文件夹没反应  
- 任务管理器里出现多个 `explorer.exe`（含 `/factory,... -Embedding`）  
- 主资源管理器句柄数异常偏高（如 4000+）

### 常见原因（本工具优先匹配）

| 风险 | 示例 |
|------|------|
| high | 百度网盘图标覆盖 / 右键、WPS 壳扩展、部分安全软件 |
| medium | 搜狗进 explorer、迅雷壳扩展等 |

> 你前台/托盘看不到某软件，**不代表**它的 DLL 没有注入 `explorer.exe`。

### 环境

- Windows 10 / 11  
- PowerShell 5.1+（系统自带即可）  
- 禁用图标覆盖键名需要**管理员**权限时更稳妥（HKLM）  
- CLSID Blocked 写入 **HKCU** 通常无需管理员

### 快速开始

```powershell
# 若提示无法运行脚本：
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

cd path\to\explorer-shell-fix
.\Start-ExplorerShellFix.ps1
```

GUI 按钮：

1. **Diagnose / 诊断** — 看 explorer 进程、图标覆盖、匹配到的厂商 CLSID  
2. 选择厂商 → **Disable + Restart** — 禁用并重启资源管理器  
3. **Restore last** — 从备份恢复  
4. **Export JSON** — 导出诊断报告

CLI：

```powershell
.\Start-ExplorerShellFix.ps1 -Cli diagnose
.\Start-ExplorerShellFix.ps1 -Cli list-vendors
.\Start-ExplorerShellFix.ps1 -Cli disable -VendorId baidu-netdisk -RestartExplorer
.\Start-ExplorerShellFix.ps1 -Cli restore -BackupPath .\.backups\xxx.json -RestartExplorer
.\Start-ExplorerShellFix.ps1 -Cli restart-explorer
.\Start-ExplorerShellFix.ps1 -Cli export
```

### 原理（简图）

```text
打开文件夹
  → explorer 列举目录 / 画图标
  → 调用第三方 Shell 扩展（覆盖层、右键…）
  → 扩展卡住 → 白屏或无法开新窗
禁用：写入 Shell Extensions\Blocked + 重命名覆盖层键
  → 重启 explorer 卸 DLL
  → 文件夹恢复
```

备份目录：`.backups\`  
报告目录：`reports\`  
厂商规则：`data\risk-vendors.json`（可 PR 扩充）

### 免责声明

- 修改注册表有风险；请先读诊断输出再禁用  
- 禁用后，对应软件在资源管理器内的角标/右键可能消失，**主程序一般仍可用**  
- 软件更新后可能重新注册扩展，需再禁用一次  
- 本项目按 MIT 提供，**不对数据损失或系统故障负责**

### 致谢

- 禁用思路对齐 NirSoft ShellExView 的 Blocked 机制  
- 真实案例：百度网盘 `YunShellExt` 多图标覆盖导致文件夹白屏，禁用后立即恢复

---

## English

Diagnose and **reversibly disable** third-party Windows Explorer **shell extensions** that cause blank folder windows or “double-click does nothing”.  
Does **not** uninstall apps. Uses the same `Shell Extensions\Blocked` approach as [ShellExView](https://www.nirsoft.net/utils/shexview.html).

### Symptoms

- Folder window opens white/blank; restarting Explorer fixes it temporarily  
- Double-clicking a folder does nothing  
- Multiple `explorer.exe` processes (including factory hosts)  
- Main Explorer handle count very high

### Quick start

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\Start-ExplorerShellFix.ps1
```

CLI examples: see Chinese section above (`-Cli diagnose|disable|restore|...`).

### Safety

Registry changes can break shell integrations. Backups are written under `.backups\`. MIT license, no warranty.

### Contributing

- Add vendor patterns in `data/risk-vendors.json`  
- Keep core logic in `src/ExplorerShellFix.Core.ps1`  
- Prefer small, testable functions over giant scripts

### License

MIT — see [LICENSE](LICENSE)