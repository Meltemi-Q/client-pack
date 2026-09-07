# 局域网打包页

给同事用的页面：打开后能看到**正在处理什么**和**百分比**，点「开始打包」即可。不用填参数。

固定行为：拉 `develop2` 最新 → 打包 → 拷到 NAS `\\nas.golgi-bci.com\软件组共享\最新社区筛查客户端`。

## 同事

浏览器打开：

`http://192.168.0.226:8765`

## 这台打包机

打包页跑在开发机本机（`192.168.0.226`），用这台电脑已有的 GitHub / NAS 登录。

```bat
D:\Programs\golgi\geerji_all\client-pack\lan-api\start_pack_api.cmd
D:\Programs\golgi\geerji_all\client-pack\lan-api\install_autostart.cmd
```

安装包会拷到 NAS；本机备份在 `D:\Programs\golgi\geerji_all\_pack_out`。
