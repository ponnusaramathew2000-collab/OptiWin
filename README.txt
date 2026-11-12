OptiWin 2.1
============
Powered by CyberX, SVPNPA.
A debloater and uninstaller for Windows 10 (1809 or later) and Windows 11.

NEW IN 2.1
- Renamed OptiWin, with the CyberX and SVPNPA logos in the header and a
  "Powered by CyberX, SVPNPA" footer. Can be built into a single OptiWin.exe
  (see MAKING OptiWin.exe below).
- Built-in apps now include a Microsoft Defender option (disable, not remove).
- When a desktop program is uninstalled, the tool offers to remove its leftover
  files, registry keys, services and scheduled tasks. Removed leftovers are
  quarantined / backed up so Undo can restore them.
- Services show their live Running/Stopped state. Services that need care are
  hidden behind the "Show services that need care" box.
- Stronger block on Start-menu search sending what you type to Bing.
- New settings to free the bandwidth Windows reserves and to cap background
  update downloads.

FILES
- OptiWin.ps1              The tool.
- OptiWin.cmd              Double-click this to run it.
- Build-OptiWin-exe.ps1    Builds OptiWin.exe on Windows (optional).
- assets\                   Logos and the exe icon.

HOW TO RUN
1. Unzip the folder anywhere and keep the files together.
2. Double-click "OptiWin.cmd" and choose Yes at the administrator prompt.
   If SmartScreen warns about a downloaded file, choose "More info" > "Run anyway",
   or right-click each file > Properties > tick "Unblock" first.
3. The first scan takes up to a minute (Windows features are slow to read).

MAKING OptiWin.exe (optional)
- An .exe has to be built on Windows. Right-click "Build-OptiWin-exe.ps1" >
  Run with PowerShell (or: powershell -ExecutionPolicy Bypass -File
  .\Build-OptiWin-exe.ps1). It installs the "ps2exe" helper the first time
  (needs internet once), then creates OptiWin.exe with the CyberX icon, the
  company name "CyberX, SVPNPA", and a built-in administrator prompt.
- After that, OptiWin.exe runs on its own; the .ps1 and .cmd are no longer needed
  to launch it, but keep OptiWin.ps1 if you want to rebuild after changes.

TABS
- Built-in apps      Bloat that ships with Windows, plus OneDrive and Microsoft Edge.
- Store apps         Every removable Microsoft Store app, from Microsoft or anyone else.
                     Photos, Calculator, codecs and similar sit in their own warned group.
- Desktop programs   Every program installed with its own installer (Settings > Apps).
                     Runtimes and drivers are grouped separately because other software needs them.
- Startup            Programs that start at sign-in, Store app startup tasks and
                     third-party scheduled tasks. Disabling keeps them installed.
- Privacy, Start & taskbar, Explorer & system   Settings, each with its current state.
- Services           Non-essential background services, with their live state.
                     Disabling sets startup to Disabled; it never deletes a service.
                     Services that need care are hidden until you tick the box below.
- Windows features   Optional components such as SMB 1.0 and PowerShell 2.0.
- Clean up           Temp files and update caches, with sizes.

LEFTOVER REMOVAL (desktop programs)
- With "Remove leftover files and registry entries" ticked, after a program
  uninstalls the tool scans for its install folder, its data under AppData /
  ProgramData, its vendor registry keys, and any service or task that runs from
  its folder. It lists what it found and asks before removing anything.
- Removed files go to C:\ProgramData\OptiWin\Quarantine and registry keys to
  \RegBackups, so "Undo a previous run" puts them back.
- Protected locations (Windows, the bare Program Files / AppData roots, drive
  roots) are never touched. Store apps already remove their own data on uninstall.

MICROSOFT DEFENDER (Built-in apps > Advanced)
- Defender cannot be uninstalled on client Windows, so this DISABLES it (real-time
  protection, its services where allowed, and its scheduled tasks).
- You must turn Tamper Protection off first: Windows Security > Virus & threat
  protection > Manage settings > Tamper Protection. The tool checks this and will
  not bypass it; with it on, the option is skipped.
- Only for PCs that run another antivirus, or isolated malware-analysis machines.
  The tool warns if no other antivirus is present.
- It is undoable, but a Windows security update may switch parts back on.

USING IT
- Recommended items are ticked for you. Nothing on the Store apps, Desktop programs
  or Startup tabs is ticked until you tick it.
- Find box: filters every tab at once. Right-click a list to tick or untick all shown rows.
- Preview changes: lists every registry value, service, task, package and uninstall
  command that would run. Nothing is touched.
- Apply selected: creates a System Restore point (if ticked), then applies everything.
- "Uninstall silently when possible": uses the program's own silent mode (MSI, Inno Setup,
  or the vendor's quiet command). Programs without one open their own uninstaller.

MICROSOFT EDGE
- Uses Edge's own uninstaller. Outside the EU, Microsoft blocks it, so the tool creates a
  temporary placeholder file that unlocks it (the same method WinUtil uses), then removes it.
- WebView2 is kept. Teams, Outlook, Widgets and many other apps need it.
- Windows Update is told not to reinstall Edge. A Windows feature update may still bring it back.
- Install another browser first. The tool warns you if it cannot find one.
- If Microsoft blocks removal on your build, the log says so and nothing else is changed.
- To get Edge back: run "Undo a previous run" for that run, then install from microsoft.com/edge.

RESTORE / ROLL BACK
- Every Apply saves a backup point, and ALL of them are kept (not just the last one),
  so you always have a history to return to.
- The "Restore / roll back..." button lists every backup point by date. Pick one and:
    * "Undo this run only"            - reverse just that run's changes.
    * "Roll back to before this point" - reverse that run AND every run applied after it,
      returning the PC to how it was just before that point. (Example: with backups from
      yesterday, this morning and noon, rolling back to before this morning undoes the
      morning and noon runs and leaves yesterday's in place.)
- Reversible: settings, services, scheduled tasks, startup entries, Windows features and
  quarantined leftover files/registry keys. Re-adding some Windows features needs internet.
- Not reversible: removed apps, programs and Python packages - reinstall them (the log lists
  what was removed). Clean-ups cannot be undone.
- A System Restore point ("Before OptiWin ...") is also made each run, as a whole-system fallback.
- Backups: C:\ProgramData\OptiWin\Backups    Logs: C:\ProgramData\OptiWin\Logs

NOTES
- Per-user settings go to the account signed in when you run the tool.
- Some changes appear only after File Explorer restarts (the tool offers to do it) or after
  a PC restart (features, services, policies).
