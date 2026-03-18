## 参考自https://www.nodeseek.com/post-183613-1 ，在此感谢大佬的教程

说明：在大佬的基础上添加了检测更新和重启服务等功能

## 脚本界面预览：

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
## 一键脚本：
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
## 默认配置文件（脚本在首次部署环境时会自动添加）
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
## 可视化面板配置文件路径：/root/realm/web/config.toml
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
## 如需其他更多配置请参考官方文档： https://github.com/zhboner/realm
