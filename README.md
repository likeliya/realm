## 添加对Kvm Lxc Docker虚拟化Alpine系统的支持：

1.在脚本中添加了虚拟systemctl命令伪装好兼容alpine系统。

2.修改面板前端处理函数防止在虚拟化环境里无法获取转发规则。

3.修改转发面板和登录面板html文件用于支持新添加浏览器标签页图标。

4.添加标准Nginx处理块示例文件用于反代面板方便公网访问调整转发规则。

5.原开发者参考自https://www.nodeseek.com/post-183613-1 ，在此感谢大佬的教程。

6.我自己Fork的原开发者的GitHub项目地址https://github.com/wcwq98/realm，感谢大佬的开源。

### 使用一键脚本：

kvm lxc debian/ubuntu

```
curl -L https://github.com/likeliya/realm/releases/download/v3.1.2.1/realm-debian.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```

kvm lxc alpine

```
curl -L https://github.com/likeliya/realm/releases/download/v3.1.2.1/realm-alpine.sh -o realm.sh && chmod +x realm.sh && bash realm.sh
```

docker alpine

```
curl -L https://github.com/likeliya/realm/releases/download/v3.1.2.1/realm-docker-alpine.sh -o realm.sh && chmod +x realm.sh && bash realm.sh
```

## 

### 添加标签页图标：

![001.png](https://image.mlikeli.xyz/file/image/NH3PUsnz.png)

![002.png](https://image.mlikeli.xyz/file/image/myx0l8kM.png)



### 脚本界面预览：

```
################################################
#        Realm 一键转发脚本 (v3.1.2)         #
################################################
 Realm 状态: 运行中
 面板 状态: 已安装但未启动
------------------------------------------------
  1. 安装 / 重置 Realm
  2. 卸载 Realm
------------------------------------------------
  3. 添加转发规则
  4. 添加端口段转发
  5. 删除转发规则
  6. 查看当前配置
------------------------------------------------
  7. 启动服务
  8. 停止服务
  9. 重启服务
------------------------------------------------
  10. 更新脚本
  11. 面板管理
  0. 退出脚本
################################################

```

### 默认配置文件（脚本在首次部署环境时会自动添加）

```
[network]
no_tcp = false #是否关闭tcp转发
use_udp = true #是否开启udp转发

#参考模板
# [[endpoints]]
# listen = "0.0.0.0:本地端口"
# remote = "落地鸡ip:目标端口"

[[endpoints]]
listen = "0.0.0.0:1234"
remote = "0.0.0.0:5678"
```

### 可视化面板配置文件路径：/root/realm/web/config.toml

```
[auth]
password = "123456" # 面板密码

[server]
port = 8081 # 面板端口

[https]
enabled = false #是否开启HTTPS(强烈建议开启HTTPS)若certificate下没有证书不要开启此功能
cert_file = "./certificate/cert.pem"
key_file = "./certificate/private.key"

```

若将面板暴露在公网，必须使用https，密码在安装后请自行更改为复杂强度密码。

如需其他更多配置请参考官方文档： https://github.com/zhboner/realm
