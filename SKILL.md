---
name: client-pack
description: |
  Pack a Windows client into a PyInstaller onedir + Inno Setup installer.
  Empty PC: run scripts/bootstrap_pack_tools.ps1 or 一键安装打包工具.cmd (Miniconda + Inno Setup 6.7.3 + real ffmpeg). PyInstaller is pip-installed by setup_build_env.bat as pyinstaller==6.20.0, never as a standalone exe.
  Trigger phrases: 客户端打包, client pack, Inno, PyInstaller, build_and_pack, 安装包, 一键安装打包工具, bootstrap, /client-pack.
  Pin conda env golgi-build (Python 3.8.20 64-bit, PySide6 6.6.2, shiboken6 6.6.2, PyInstaller 6.20.0) then run pack_client.cmd.
  Do not follow onefile packaging guides or a different conda env than golgi-build.
---

# Windows client pack

Recipe for a client checkout that has `build_and_pack.bat` + `setup_build_env.bat` + `installer.iss` + an onedir `.spec` (`COLLECT`). This folder is not the app source. Do not copy client code here. Do not put secrets here.

Do not hardcode product names. Point `-Repo` at the checkout; `check_pack_env.ps1` prints the spec and exe name it found. `build_and_pack.bat` in that checkout is the source of truth for the installer filename.

Shared pins: Python 3.8, PySide6 6.6.2, shiboken6 6.6.2, PyInstaller 6.20.0, Inno Setup 6 `ISCC.exe`. Extra files (json, fonts, wav templates, ffmpeg, vendor trees) are whatever that checkout's pack script requires.

## ACTION REQUIRED

Do not invent downloaders or mirrors.

Official files (allowlist). Bootstrap must use these exact strings; if a download fails, retry the **same** URL, then stop.

| What | Official landing (human) | File / id the agent actually fetches |
|------|--------------------------|--------------------------------------|
| Miniconda 64-bit Windows | https://www.anaconda.com/docs/getting-started/miniconda/install/windows-cli-install | https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe |
| Miniconda (optional winget) | same | winget id `Anaconda.Miniconda3` |
| Inno Setup **6.7.3** (pinned) | https://jrsoftware.org/isdl.php | https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe |
| Inno Setup 6 (optional winget) | same | `winget install --id JRSoftware.InnoSetup --version 6.7.3` |
| ffmpeg (real Windows build) | https://www.gyan.dev/ffmpeg/builds/ | https://github.com/GyanD/codexffmpeg/releases/download/8.0/ffmpeg-8.0-essentials_build.zip |
| ffmpeg (optional winget) | same | `winget install --id Gyan.FFmpeg.Essentials` |
| PyInstaller 6.20.0 | PyPI | **no exe**. `setup_build_env.bat` → `pip install pyinstaller==6.20.0` inside `golgi-build` |

Do **not** fetch `https://jrsoftware.org/download.php/is.exe` (tracks Inno 7). Pack looks for `Inno Setup 6\ISCC.exe`. Constants also live at the top of `scripts/bootstrap_pack_tools.ps1`. If SKILL.md and the script disagree, **stop and fix the skill**.

### 0) Confirm the job

1. `NOW`: Windows **client installer** pack (onedir + Inno), not onefile.
2. `NOW`: locate the client checkout (`build_and_pack.bat` + `setup_build_env.bat` + `installer.iss` + a `*.spec` that contains `COLLECT`). If the path has Chinese or other non-ASCII, stop and move it.

Set `SKILL` = this folder, `REPO` = the client checkout. CMD only, not Git Bash.

### A) Empty PC / conda.bat FAIL / ISCC FAIL

3. `ACT`:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File %SKILL%\scripts\bootstrap_pack_tools.ps1 -Repo %REPO%
```

Colleague: `一键安装打包工具.cmd` (Enter between steps). Agent:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File %SKILL%\scripts\guided_pack_wizard.ps1 -Mode Install -SkipEnv -AutoContinue -Repo %REPO%
```

Do **not**: python.org 3.11, Inno 5, `pip install pyinstaller` on system Python, any conda env except `golgi-build`.

4. `NOW`: wait for `RESULT=TOOLS_READY`. With `-Repo`, also `RESULT=ENV_READY`.
5. If `RESULT=FAIL`, follow `NEXT=`. Do not switch URL.
6. `NOW`: new CMD after `conda init` if a **new** window still lacks `conda.bat`.
7. `NOW`: re-run check:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File %SKILL%\scripts\check_pack_env.ps1 %REPO%
```

`conda.bat`, `ISCC`, and `ffmpeg` must be PASS. Read `Found spec:` / `Found exe name in spec:` from the check output.

### B) Pack

8. `NOW`: check_pack_env.ps1. Exit `0` READY, `2` NEEDS_SETUP, `1` FAIL.
9. `ACT`: FAIL on conda/ISCC/ffmpeg → A. Other FAIL → `references/pitfalls.md`.
10. `ACT`:

```bat
%SKILL%\scripts\pack_client.cmd %REPO%
```

Colleague: `一键打包.cmd`. Agent:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File %SKILL%\scripts\guided_pack_wizard.ps1 -Mode Pack -AutoContinue -Repo %REPO%
```

Do **not** double-click `build_and_pack.bat` alone.

11. Confirm stdout `OUTPUT=` under `dist\installer\*_setup_*.exe`.

## Successful chain (ONLY this)

1. ASCII-only project path.
2. Miniconda via `bootstrap_pack_tools.ps1`; CMD can find `conda.bat`.
3. Inno Setup 6.7.3 via the same bootstrap; `ISCC.exe` in Program Files or `GOLGI_ISCC`.
4. Real `ffmpeg.exe` (>= 1MB) via the same bootstrap; user env `GOLGI_FFMPEG` or `LOCALAPPDATA\Programs\ffmpeg\bin\ffmpeg.exe`. A scoop/store shim is not enough.
5. Conda env `golgi-build`, Python **3.8.20 64-bit** (pack script asserts Python **3.8**).
6. `setup_build_env.bat` pip-installs `pyinstaller==6.20.0`, PySide6 6.6.2, shiboken6 6.6.2.
7. `build_and_pack.bat` using **this checkout's** onedir spec and `installer.iss`.

Optional env: `GOLGI_NOPAUSE=1`, `GOLGI_FAST_BUILD=1`, `GOLGI_BUILD_ENV`, `GOLGI_ISCC`, `GOLGI_FFMPEG`.

## Do not use (obsolete)

- Markdown/txt that says `--onefile` or a conda env other than `golgi-build`
- Any `.spec` without `COLLECT`

## Load this skill

Keep it in a `client-pack` folder next to (not inside) the client checkout.

```bat
mklink /J %USERPROFILE%\.grok\skills\client-pack <path-to-client-pack>
```

## Failures

`references/pitfalls.md` when a check FAILs.
