# 局域网打包页

给同事用的页面：打开后能看到**正在处理什么**和**百分比**，点「开始打包」即可。不用填参数。

固定行为：拉 `develop2` 最新 → 打包 → 拷到 NAS `\\nas.golgi-bci.com\软件组共享\最新社区筛查客户端`。

## 同事

浏览器打开：

`http://192.168.0.105:8765`

## 这台打包机

```bat
D:\golgi\pack-api\start_pack_api.cmd
D:\golgi\pack-api\install_autostart.cmd
```

打包机 **不要登录个人 GitHub 账号**。

当前默认（不用仓库管理员）：开发机已能拉 GitHub，定时把 `develop2` 推到 105。脚本 `sync_develop2_to_105.ps1`，计划任务 `GolgiSyncDevelop2To105`。开发机关机时 105 打最后一次同步到的代码。

可选，让 105 自己拉 GitHub（仍不用登录个人账号）：

1. SSH 部署密钥：私钥 `D:\golgi\pack-api\id_ed25519_geerji_client`，公钥见 `105-deploy-key.pub`。需要仓库 **admin** 加到  
   `https://github.com/geerji/medical_version_client-/settings/keys`（不要勾写权限）。maintain 打不开这个页。
2. `D:\golgi\pack-api\git.token` 放只授权这一个仓库 Contents: Read 的 fine-grained PAT。组织若要求审批，还是得找管理员。

GitHub 直连失败时，打包页仍会快进本机已经同步过来的 `origin/develop2`。

拷到 NAS 需要 `D:\golgi\pack-api\nas.cred`（格式见 `nas.cred.example`）。没有这份文件时安装包仍会放到本机 `D:\golgi\pack-out`（共享名 `pack-out`）。
