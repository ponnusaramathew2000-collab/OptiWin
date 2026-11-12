# OptiWin 2.1

Debloat and tidy Windows 10/11 from one window. OptiWin removes preinstalled apps, Store apps, desktop programs, bloatware, OneDrive, Microsoft Edge and Python packages; disables non-essential services, startup items and scheduled tasks; turns off telemetry, ads, search indexing and Delivery Optimization; and clears temp and update caches. Nothing is changed until you press **Apply**, a System Restore point is made first, and almost everything can be rolled back.

*Powered by CyberX, SVPNPA.*

## Starting OptiWin

**Unblock the zip before extracting.** Right-click the downloaded zip → **Properties** → tick **Unblock** → **OK**, then extract. This clears the "downloaded from the internet" mark that makes SmartScreen treat the files as untrusted. Do this first.

Then double-click **`OptiWin.cmd`** and choose **Yes** at the administrator prompt. OptiWin needs administrator rights to remove apps and change system settings; it asks for them itself. The first scan takes up to a minute, because reading the list of Windows features is slow.

- Works on **Windows 10 (version 1809 or later)** and **Windows 11**.
- Uses the **Windows PowerShell 5.1** that ships with Windows — nothing to install.
- If SmartScreen still warns, choose **More info → Run anyway**, or unblock each file under Properties.
- Per-user settings apply to the account that is signed in when you run it.

## Building OptiWin.exe (optional, for IT)

OptiWin ships as a single PowerShell script so you can read every line. To hand users a double-clickable **`OptiWin.exe`** instead, build it on a Windows machine:

```
powershell -ExecutionPolicy Bypass -File .\Build-OptiWin-exe.ps1
```

The script installs the community **ps2exe** module the first time (one-time internet), then produces `OptiWin.exe` with the CyberX icon, version information, the company name **CyberX, SVPNPA**, and a built-in request for administrator rights. After that the exe runs offline and the `.ps1` is only needed to rebuild after changes.

## How it works

1. Open OptiWin. **Recommended** items are ticked for you; the app, program, Python and startup lists start with nothing ticked.
2. Go through the tabs and adjust the ticks. Hover any row for a full description.
3. Press **Preview changes** to see exactly which registry values, services, scheduled tasks, packages and uninstall commands would run. Nothing is touched.
4. Press **Apply selected**. OptiWin makes a restore point, then applies everything and writes each step to the log.

**Handy controls**

- **Find** box filters every tab at once.
- **Right-click** any list → **Tick all shown** / **Untick all shown**.
- **Select recommended** / **Clear all** buttons for the whole window.
- Options: *Create a restore point first*, *Uninstall silently when possible*, *Remove leftover files and registry entries*, *Show services that need care*.

## What each tab does

| Tab | What it covers |
|-----|----------------|
| **Built-in apps** | Bloat that ships with Windows (News, Weather, Tips, Clipchamp, Solitaire, Copilot, preinstalled games and social apps…), plus **OneDrive** and **Microsoft Edge** under *Advanced*. |
| **Store apps** | Every removable Microsoft Store app on the PC, from Microsoft or anyone else. Core system apps (Photos, Calculator, codecs…) sit in a separate warned group; the Store and core Windows parts are never listed. |
| **Desktop programs** | Every program installed with its own installer, as in *Settings → Apps*. Genuine **bloatware** (OEM utilities, trial antivirus, toolbars, bundled junk) floats to a highlighted group at the top. Runtimes and drivers are grouped apart because other software depends on them. |
| **Python packages** | `pip` packages found in each Python on the PC, listed per interpreter. `pip`, `setuptools` and `wheel` are never offered. |
| **Startup** | Programs that start at sign-in, Store-app startup tasks and third-party scheduled tasks. Disabling keeps them installed. Windows' own tasks are left alone. |
| **Privacy** | Diagnostic data to minimum, telemetry service and tasks off, advertising ID, activity history, tailored experiences, typing/inking data, Recall snapshots. |
| **Start & taskbar** | Suggested and silently-installed apps, tips and promotions, Start-menu and Settings ads, lock-screen "fun facts", Widgets, web/Bing results in search, Copilot. |
| **Explorer & system** | Show file extensions, classic right-click menu, Cortana off, **Delivery Optimization** (the peer-sharing that can use ~20% of your bandwidth), reserved bandwidth, Game DVR, and more. |
| **Services** | Non-essential background services, each with its live **Running/Stopped** state. Disabling only sets startup to *Disabled* — it never deletes a service. Services that need care (printing, search, location, Xbox) are hidden until you tick the box. |
| **Windows features** | Optional components such as **SMB 1.0**, the **PowerShell 2.0** engine, Recall, Internet Explorer, WordPad and Steps Recorder. |
| **Clean up** | Temp files, the Windows Update download cache, the Delivery Optimization cache and the component store, with sizes. |

**What the Status column means**

| Status | Meaning |
|--------|---------|
| Not applied / Running now | The change hasn't been made yet (services also show if they're running). |
| Already applied | The setting is already in the state OptiWin would set. |
| Partly applied | Some of the values in that item are set, some aren't. |
| Not on this PC | The target service, task or key doesn't exist here, so it's skipped. |

## Microsoft Edge

Edge can't be uninstalled from Settings, so OptiWin uses Edge's **own uninstaller**. Outside the EU, Microsoft blocks that uninstaller, so OptiWin briefly creates a placeholder file that unlocks it (the method [WinUtil](https://winutil.christitus.com) uses) and removes it afterwards.

- **WebView2 is kept** — Teams, Outlook, Widgets and many other apps rely on it.
- Windows Update is told **not to reinstall** Edge. A Windows *feature* update may still bring it back; Undo lifts the block.
- OptiWin warns if no other browser is found, and asks before deleting your Edge profile (favourites, passwords, history).

## Microsoft Defender

For PCs that run another antivirus, or isolated malware-analysis machines, OptiWin can **disable** Defender (it can't be uninstalled on client Windows). This lives under *Built-in apps → Advanced*.

- You must turn **Tamper Protection OFF** first (Windows Security → Virus & threat protection → Manage settings). OptiWin checks this with Defender's own API and **will not bypass it**; nothing — not even a local admin or a script — can turn Tamper Protection off programmatically, by Microsoft's design. If it's on, OptiWin offers to open Windows Security straight to that setting.
- With it off, OptiWin applies the Group Policy keys plus Defender's supported `Set-MpPreference`, disables Defender's scheduled tasks, and sets its non-driver services to *Disabled*, then verifies real-time protection actually went off.
- Every change is recorded, so **Undo** re-enables it. A Windows security update may switch parts back on.

## Restore and roll back

Every time you Apply, OptiWin saves a **backup point**, and they are **all kept** — so you always have a history to return to. Press **Restore / roll back…** to see every point by date and choose:

- **Undo this run only** — reverse just that one run's changes.
- **Roll back to before this point** — reverse that run **and every run applied after it**, returning the PC to how it was just before then. (Example: with backups from yesterday, this morning and noon, rolling back to before this morning undoes the morning and noon runs and leaves yesterday's in place.)

**Reversible:** settings, services, scheduled tasks, startup entries, Windows features, the Defender changes, and quarantined leftover files and registry keys.
**Not reversible:** removed apps, programs and Python packages — reinstall them (the log lists what was removed). Clean-ups can't be undone.

A **System Restore point** named *"Before OptiWin …"* is also made on each run, as a whole-system fallback. Open it with `rstrui`, or Control Panel → Recovery → Open System Restore.

## Where your data lives

Everything OptiWin writes stays under `C:\ProgramData\OptiWin`:

- `Backups\` — one `run-*.json` per Apply (used by Restore / roll back).
- `Logs\` — a full log per session.
- `Quarantine\` — leftover files moved aside, so they can be restored.
- `RegBackups\` — `.reg` and task `.xml` backups of removed registry keys, services and tasks.

## Safety

- Nothing changes until you press **Apply**, and **Preview** shows every exact change first.
- A restore point is made before any change (OptiWin offers to turn System Protection on if it's off).
- Settings are changed with care: services are disabled, never deleted; leftover removal is conservative and asks before each program; protected Windows locations are never touched.
- Some changes finish only after **File Explorer restarts** (OptiWin offers to do it) or after a **PC restart** (features, services, policies).

## Change log

**2.1** — Renamed **OptiWin**, with the CyberX + SVPNPA logo card and footer. Added the Python-package remover, the bloatware highlight, the Delivery Optimization option, and a **Restore / roll back** history that keeps every backup point. Defender disabling now uses `Set-MpPreference` with reliable Tamper Protection detection.

**2.0** — Store apps, desktop programs with leftover-file/registry/service/task removal, Microsoft Edge removal, optional services and Windows features, clean-up, the Startup tab and a find box.

**1.0** — First release: built-in app removal and privacy, telemetry, ads and Explorer tweaks, with Preview, a restore point and Undo.
