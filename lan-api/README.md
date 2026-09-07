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

拉最新代码需要在 `D:\golgi\pack-api\git.token` 放公司仓库只读 token（不要用个人 GitHub 账号登录）。没有 token 时会打当前目录里已有的代码。
