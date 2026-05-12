# ZoneFoundry Bridge for fnOS

每日自动同步 [ZoneFoundry Bridge 官方 Docker 镜像](https://hub.docker.com/r/zonefoundry/bridge) 最新版本并构建 `.fpk` 安装包。

## 下载

从 [Releases](https://github.com/conversun/fnos-apps/releases?q=zonefoundry-bridge) 下载最新的 `.fpk` 文件。

## 安装

1. 根据设备架构下载对应的 `.fpk` 文件（amd64 或 arm64）
2. fnOS 应用管理 → 手动安装 → 上传
3. 安装向导中填写 ZoneFoundry Token（在 `https://zonefoundry.dev` 设置 → Bridge Token 获取）
4. 留空可在装好后手动编辑 `docker/.env`

## 说明

- ZoneFoundry 是 Sonos 语音助手生态。Bridge 是用户家中 NAS 上跑的桥接客户端，连接：
  - 上行：`wss://relay.zonefoundry.dev/ws` 云端中继
  - 下行：局域网 Sonos 音箱（UPnP/SSDP 自动发现）
- 用户通过 ZoneFoundry App / 网页 / 接入的 IM bot 远程操控 Sonos 音箱
- 容器使用 **host 网络模式**（Sonos LAN 多播发现需要）
- 不监听独立端口；fnOS 应用图标仅作占位
- 镜像同时支持 amd64 / arm64

## 1-tap 自动更新

`docker-compose.yaml` 默认挂载 `/var/run/docker.sock` 并加 `group_add: ["999"]`（飞牛/Debian docker 组 GID）。当 ZoneFoundry iOS App 的 Bridges 页面出现"升级"按钮时，点一下即可：

1. Bridge 通过 docker socket 拉取最新镜像
2. SIGTERM 自身让 fnOS Apps 用新镜像重启容器
3. 全程不用 SSH / Container Manager / 手动 recreate

如果你不想让 Bridge 有 docker socket 访问权限，可在安装后编辑 `docker-compose.yaml` 删除 socket 挂载和 `group_add`，改回手动通过 fnOS Apps 升级。

## 本地构建

```bash
cd apps/zonefoundry-bridge && bash ../../scripts/build-fpk.sh . app.tgz
```

## Credits

- [ZoneFoundry](https://zonefoundry.dev) by Sam
- Docker 镜像：[zonefoundry/bridge](https://hub.docker.com/r/zonefoundry/bridge)
- 同生态：[OpenClaw](../openclaw/) · [ZeroClaw](../zeroclaw/)
