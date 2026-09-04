# templates

`Golgi_fNIRS_community.spec` 是已经打通过的 **onedir** spec（有 `COLLECT`，`console=False`）。

客户端 `develop2` 的 `build_and_pack.bat` 会调用这个文件名，但 git 里目前只有一份不能用的 `fNIRS_Community.spec`（onefile 和 onedir 混在一起）。

一键安装 / 一键打包时：如果客户端目录里没有 bat 点名的那个 `.spec`，会从这里拷一份进去。已有文件不会覆盖。
