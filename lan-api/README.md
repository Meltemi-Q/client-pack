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

打包机 **不要登录个人 GitHub 账号**。只给公司仓库 `geerji/medical_version_client-` 只读权限：

1. SSH 部署密钥（优先）：私钥 `D:\golgi\pack-api\id_ed25519_geerji_client`，公钥见 `105-deploy-key.pub`。仓库管理员在  
   `https://github.com/geerji/medical_version_client-/settings/keys`  
   添加 **Allow write access 不要勾**。
2. 备选：`D:\golgi\pack-api\git.token` 放 **fine-grained PAT**，只授权这一个仓库的 Contents: Read。凭据助手不会对别的 GitHub 仓库吐 token。

没有以上权限时，会打当前目录里已有的代码。

拷到 NAS 需要 `D:\golgi\pack-api\nas.cred`（格式见 `nas.cred.example`）。没有这份文件时安装包仍会放到本机 `D:\golgi\pack-out`（共享名 `pack-out`）。
