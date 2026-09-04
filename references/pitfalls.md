# 客户端打包：同事常踩的坑

只认这一条成功链：客户端仓库（有 `build_and_pack.bat`）+ conda 环境 `golgi-build` + `setup_build_env.bat` + `build_and_pack.bat`。

本文件给人对着看。agent 先跑 `scripts/check_pack_env.ps1`，对着 FAIL 行往下翻。

不要把密码、SSH、服务器账号写进 skill 或打包脚本。

---

## 先分清：成功文档 vs 过期文档

**用这些：**

- `setup_build_env.bat`
- `build_and_pack.bat`
- 本仓库 `templates\Golgi_fNIRS_community.spec`（onedir，`COLLECT`）。客户端 git 若没有 bat 点名的那个文件，一键打包会拷这份进去
- `installer.iss`
- `requirements.txt`（已钉死 `pyinstaller==6.20.0`、`PySide6==6.6.2`、`shiboken6==6.6.2`）
- `VERSION.txt`

**不要用这些（过期，按它们做会失败或打出旧产品）：**

| 文件 | 为什么过期 |
|------|------------|
| 写着 `--onefile` 的 md/txt | 成功链是 onedir + Inno，不是单文件 exe |
| 没有 `COLLECT` 的 `.spec` | 旧 onefile spec，不要用 |
| 客户端 git 里的 `fNIRS_Community.spec` | 名字对不上 `build_and_pack.bat`，而且 onefile/onedir 混在一起。要用 `templates\Golgi_fNIRS_community.spec` |
| README 里别的 conda 环境名 | 打包必须 `golgi-build` |

同事最常见的失败：打开仓库里第一份带「打包」字样的 md，按 onefile 或别的 conda 环境做。

---

## 硬失败

### 1. 项目路径有中文（或任何非 ASCII）

`build_and_pack.bat` 会直接停。

坏例子：桌面中文目录、用户名是中文的盘符路径。

好例子：纯英文路径下的客户端仓库（里面有 `build_and_pack.bat`）。

处理：把整个仓库挪到纯英文路径再打。用户主目录是中文名也不行。

### 2. CMD 找不到 `conda.bat`

打包脚本用的是 **CMD** 的 `where conda.bat`，不是 PowerShell 里的 `conda` 函数。

现象：Anaconda Prompt 里能跑，普通 CMD / 某些 AI 终端里报：

`[ERROR] conda.bat not found in PATH.`

处理：不要自己找镜像、不要装系统 Python。跑 skill 里的安装脚本（URL 只写在该脚本顶部）：

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File <skill>\scripts\bootstrap_pack_tools.ps1
```

或双击 `一键安装打包工具.cmd`。成功行是 `RESULT=TOOLS_READY`。然后 **新开一个 CMD**，`where conda.bat` 应能看到 `...\condabin\conda.bat`。

不要用 Git Bash 当打包壳。`setup_build_env.bat` / `build_and_pack.bat` 是 bat。

一键入口用 skill 里的 `scripts\pack_client.cmd`，不要双击 `build_and_pack.bat`：后者会 `pause`、不先检查环境、CMD 找不到 `conda.bat` 时直接停。

`conda create` 若报 `ProxyError` / `WinError 10061`，多半是 conda/libmamba 走了 Windows 系统代理里已经关掉的 Clash `127.0.0.1:7890`。环境变量里可能是空的，但 Python 仍会读 Internet 设置。bootstrap 发现本机 7890 没人听，会设 `NO_PROXY=*`。`pip install` 下 PySide6 / pywin32 大轮子若 `Read timed out`，bootstrap 会设 `PIP_DEFAULT_TIMEOUT=300` 和 `PIP_RETRIES=15` 再装。不要用系统自带的 Python 3.11 打包。

### 3. Python 不对

成功环境：conda 环境 **`golgi-build`**，Python **3.8.20，64 位**。

`build_and_pack.bat` 只检查大版本 **Python 3.8**。3.9 / 3.10 / 3.13 一律失败。32 位也失败。

特别坑：`setup_build_env.bat` 若发现环境已存在，会 **直接复用**，不会把 3.10 改成 3.8。

处理（Python 版本错了时）：

```bat
conda remove -n golgi-build --all
setup_build_env.bat
```

不要用系统 Python、微软商店 Python、别的 conda 环境里的 `python`。

### 4. 版本钉死不一致

`build_and_pack.bat` 精确比较：

| 包 | 必须是 |
|----|--------|
| Python | 3.8（major.minor） |
| PySide6 | 6.6.2 |
| shiboken6 | 6.6.2 |
| PyInstaller | 6.20.0 |

同事常装成 PyInstaller 6.10.0 / 最新版，或 PySide6 6.7+。Qt / shiboken 一漂，运行时必炸。

处理：PyInstaller 没有独立安装包。在仓库根目录跑 `setup_build_env.bat`（`一键安装打包工具.cmd` 带上仓库路径也会跑它）。它会 `pip install -r requirements.txt`，然后再强制 `pip install pyinstaller==6.20.0`。不要对系统 Python 执行 `pip install pyinstaller`。

老 checkout 若 `requirements.txt` 没钉 `pyinstaller==6.20.0`：先更新这个客户端仓库，不要手工猜版本。

### 5. 用错 conda 环境

打包 **必须** `golgi-build`（可用环境变量 `GOLGI_BUILD_ENV` 改名，不要拿 README 里别的旧环境名凑合）。

在别的环境里手动 `pyinstaller ...` = 失败路径。

### 6. 没有 Inno Setup 6

`build_and_pack.bat` 找：

1. `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`
2. `C:\Program Files\Inno Setup 6\ISCC.exe`
3. 环境变量 `GOLGI_ISCC`（指向 `ISCC.exe` 本身）

装的是 Inno 5、或只装了界面没装命令行、或装到自定义目录却没设 `GOLGI_ISCC`，都会在 PyInstaller 已经跑完之后才失败。

处理：跑同一个 bootstrap。Inno **钉死 6.7.3**，文件是官网 isdl.php 指向的 GitHub 不可变发布 `innosetup-6.7.3.exe`，不要下 `download.php/is.exe`（会变成 7）。机器上若已经有 7，检查脚本仍能认 `ISCC.exe`。

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File <skill>\scripts\bootstrap_pack_tools.ps1
```

不要装 Inno 5。若必须用便携目录：`set GOLGI_ISCC=D:\Tools\Inno Setup 6\ISCC.exe`（指向 `ISCC.exe` 本身）。

### 6.5 没有真 ffmpeg

`build_and_pack.bat` 会 `find_ffmpeg()`，并且要把 `ffmpeg.exe` 打进 `_internal`。scoop/商店的 shim 往往只有几十 KB，脚本会当成假的。

处理：跑同一个 bootstrap。它会把 Gyan 8.0 essentials（GitHub 不可变包）解压到 `%LOCALAPPDATA%\Programs\ffmpeg`，并写用户环境变量 `GOLGI_FFMPEG`。真文件必须 **≥ 1MB**。不要用 gyan.dev 那个会跳转的 `ffmpeg-release-essentials.zip` 当下载地址。

```bat
set GOLGI_FFMPEG=%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe
```

### 6.6 客户端没有 `Golgi_fNIRS_community.spec`

`build_and_pack.bat` 写死调用这个文件名。`develop2` 里目前只有 `fNIRS_Community.spec`，按那份打会失败或打出不对的包。

处理：一键安装 / 一键打包会自动从本仓库 `templates\` 拷一份（不覆盖已有文件）。也可以手动：

```bat
copy <skill>\templates\Golgi_fNIRS_community.spec <client_repo>\Golgi_fNIRS_community.spec
```

### 7. 缺资源：wav / json / 字体 / toml

源码树里必须有（缺一个 PyInstaller 或事后检查就会停）：

- `gorky.png` `bgkd.png`
- `SimSun.ttf` `SimHei.ttf`
- `GreenTek_v4.json` `valid_channel.json`
- `fnirs_app\config\defaults.toml`
- `addfiles\audio_pool_template\fixed\` 里要有 wav
- `addfiles\audio_pool_template\say_word\` 里要有 wav（含 `word_grouping\`）
- `addfiles\audio_pool_template\dichotic\` 里要有 wav

打包完成后还会查 `dist\<exe名>\_internal\` 里是否带上了 json、png、`audio_pool\...`（exe 名以检查脚本打印的为准）。

常见原因：浅拷贝、U 盘漏文件夹、Git 没拉全（wav 很多，`say_word` 下文件名是中文）。缺 wav 时不要用 TTS 现场现生成来「凑数」——安装包必须用仓库模板。

### 8. 按 onefile 文档打

成功产物是 **目录模式 onedir** + Inno 安装包，不是单文件 exe。

- spec 里有 `COLLECT`（检查脚本会打印找到的 spec / exe 名）
- 安装包在 `dist\installer\*_setup_*.exe`
- 具体文件名以该仓库 `build_and_pack.bat` / `installer.iss` 为准

看到 `--onefile` 或只有一个孤立 exe、没有 `_internal`，说明走错文档了。停掉。

---

## 其它容易错

**用错壳：** 在 Git Bash / MSYS 里跑 bat，路径会被改掉。用 CMD，或用本 skill 的 `pack_client.cmd`。

**`conda` 有了但 `conda.bat` 没有：** 只装了 micromamba / 只把 `conda.exe` 加到 PATH。打包脚本认 `conda.bat`。

**PowerShell 执行策略：** 跑检查脚本时用：

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File ...\check_pack_env.ps1 <repo>
```

**现成环境 Python 是 3.8 但包漂了：** `check_pack_env.ps1` 会给 `RESULT=NEEDS_SETUP`。`pack_client.cmd` 会自动再跑 `setup_build_env.bat`。

**想跳过暂停：** `set GOLGI_NOPAUSE=1`（包装脚本已经设了）。`setup_build_env.bat` 在找不到 conda 时仍会 `pause`。

**想少等一轮 clean：** `set GOLGI_FAST_BUILD=1`（跳过 PyInstaller `--clean`）。出过脏缓存问题时不要开。

**VERSION.txt：** 只能是 `1.0`、`1.0.0`、`V1.0` 这种。空文件、`1.0-beta`、中文说明都会失败。安装包版本从这里读，脚本不会自动加版本号。

**打完没有安装包：** 看 `build_and_pack.bat` 最后有没有 `Build completed successfully`。只有 `dist\<exe>\_internal` 旁边的主程序、没有 `dist\installer\*_setup_*.exe`，说明 Inno 没跑完。

**杀毒软件锁 `dist\`：** PyInstaller / ISCC 写文件失败时先排除项目目录。

**把 skill 目录当成工程：** `client-pack` 里没有客户端源码。必须把路径指到带 `build_and_pack.bat` 的客户端仓库。

---

## 干净机器最小清单

1. 64 位 Windows。
2. 仓库放在纯英文路径。
3. 跑 `scripts\bootstrap_pack_tools.ps1 -Repo <client_repo>`（Miniconda + Inno 6 + ffmpeg + golgi-build / PyInstaller 6.20.0）。
4. 再打包：

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File <skill>\scripts\check_pack_env.ps1 <client_repo>

<skill>\scripts\pack_client.cmd <client_repo>
```

成功时最后一行类似：

`OUTPUT=<client_repo>\dist\installer\*_setup_*.exe`
