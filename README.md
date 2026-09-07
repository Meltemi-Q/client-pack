# client-pack

Windows 客户端打包：PyInstaller onedir + Inno Setup。

不含客户端源码。把本目录放在客户端仓库旁边，对有 `build_and_pack.bat` 的 checkout 使用。

## 同事

目录建议（纯英文路径）：

```
D:\golgi\
  client-pack\              ← 本仓库
  medical_version_client\   ← 客户端源码（有 build_and_pack.bat）
```

1. 双击 `一键安装打包工具.cmd`（每步按 Enter）。第一次会下 Miniconda / Inno / ffmpeg，再装 Python 依赖，大概 20–40 分钟。
2. 双击 `一键打包.cmd`。打完看 `客户端仓库\dist\installer\*_setup_*.exe`。

客户端 git 里可能没有 `Golgi_fNIRS_community.spec`（bat 要这个名字）。一键打包会从本仓库 `templates\` 自动拷进去，已有文件不覆盖。不要用 git 里那份 `fNIRS_Community.spec` 打现在这套安装包。

工具安装：Miniconda、Inno Setup **6.7.3**（官网固定包，不是会跳到 7 的 `is.exe`）、ffmpeg（Gyan 8.0 essentials，真二进制，不是 scoop/商店 shim）。  
PyInstaller 不是独立安装包，由仓库里的 `setup_build_env.bat` 装进 conda 环境 `golgi-build`（`pyinstaller==6.20.0`）。

本机若开过 Clash 但已经关掉，bootstrap 会自动设 `NO_PROXY=*`，避免 conda/pip 去连死掉的 `127.0.0.1:7890`。

## Agent

读 `SKILL.md`。下载地址只准用那里的官网白名单。检查脚本会打印它在仓库里找到的 spec / exe 名，不要在文档里写死产品名。

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check_pack_env.ps1 <client_repo>
scripts\pack_client.cmd <client_repo>
```

## 局域网页面（105 打包机）

浏览器打开 `http://192.168.0.105:8765`，能看到当前步骤和百分比，点「开始打包」。不用填参数。

## 固定版本

Python 3.8、PySide6 6.6.2、shiboken6 6.6.2、PyInstaller 6.20.0、Inno Setup 6.7.3、ffmpeg（真 exe ≥ 1MB）。
