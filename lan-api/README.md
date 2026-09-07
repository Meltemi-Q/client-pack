# 局域网打包页

给同事用的页面：打开后能看到**正在处理什么**和**百分比**，点「开始打包」即可。不用填参数。

固定行为：拉 `develop2` 最新 → 打包 → 拷到 NAS `\\nas.golgi-bci.com\软件组共享\最新社区筛查客户端`。

## 同事

浏览器打开：

`http://192.168.0.226:8765`

能打开就是服务在跑（后台 `pythonw`，没有黑窗口）。页面上可以开始打包，也可以关服务。关了之后这个地址会打不开，再开请双击桌面上的 `打开社区打包页`。

## 这台打包机

```bat
D:\Programs\golgi\geerji_all\client-pack\lan-api\open_pack_page.cmd
D:\Programs\golgi\geerji_all\client-pack\lan-api\install_autostart.cmd
```

开机后会静默拉起服务。安装包拷到 NAS，本机备份在 `D:\Programs\golgi\geerji_all\_pack_out`。
