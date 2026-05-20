# Mihomo for fnOS

[Mihomo](https://github.com/MetaCubeX/mihomo) (前 Clash.Meta) 多协议代理内核 + 自研轻量管理面板 [fnos-mihomo-dashboard](https://github.com/conversun/fnos-mihomo-dashboard) + [MetaCubeXD](https://github.com/MetaCubeX/metacubexd) 高级管理面板的一体化打包。

## 架构

```
LAN 浏览器 → :9097 (fnos-mihomo-dashboard)
                   ├─ /          fnOS 自研极简管理面板（订阅 + 状态 + 节点选择 + 日志）
                   ├─ /api/*     dashboard 自己的 REST API
                   ├─ /mihomo/*  反代到 mihomo (127.0.0.1:9090)
                   └─ /ui/       MetaCubeXD 高级面板（高级用户）

mihomo (127.0.0.1:9090) ← 仅本机访问, dashboard 管控所有配置写入
       :7890           ← HTTP+SOCKS5 混合代理 (LAN 可达)
```

**核心设计**：mihomo 的 `external-controller` 始终绑 `127.0.0.1:9090`，外界永远不直连 mihomo；所有配置变更经过 dashboard，避免端口漂移与 SAFE_PATHS 限制。

## 端口分配

| 端口 | 协议 | 用途 |
|------|------|------|
| 9097 | TCP | fnos-mihomo-dashboard (管理面板 + 反代) |
| 7890 | TCP | HTTP + SOCKS5 混合代理 (LAN 可用) |
| 1053 | UDP/TCP (localhost) | mihomo 内部 DNS (TUN 模式劫持 53) |
| 9090 | TCP (localhost) | mihomo RESTful API (内部) |

## 快速上手

### 1. 安装并打开管理面板

在 fnOS 应用中心安装 Mihomo，自动启动后浏览器打开 `http://<NAS_IP>:9097/`。看到自研的极简面板。

### 2. 添加代理订阅

在「订阅管理」输入你的 Clash 订阅 URL → 「保存并应用」。dashboard 会：
- 把订阅 URL 写入 mihomo 的 `proxy-providers.fnos-subscription`
- 让 PROXY 策略组通过 `use: [fnos-subscription]` 引用此订阅
- 通过 mihomo `/configs?path=...` API 触发重载（**不动 `external-controller`**，dashboard 永远不掉线）

mihomo 自动每 24 小时刷新订阅节点。

### 3. 选择节点

「节点选择」面板里点击想用的节点。

### 4. 启用 TUN 模式（可选）

透明代理整个 NAS 出口流量：编辑 `${TRIM_PKGVAR}/config/config.yaml` 改 `tun.enable: true`，dashboard 点「重载」。安装时已通过 `setcap` 授予 `CAP_NET_ADMIN/NET_RAW/NET_BIND_SERVICE`。

### 5. 进入 MetaCubeXD 高级面板（可选）

dashboard 右上角「高级管理 (MetaCubeXD) →」按钮，进入功能完整的 metacubexd（看实时连接、流量、规则调试）。

## 配置文件位置

```
${TRIM_PKGVAR}/config/config.yaml
```

dashboard 拥有此文件的写权限；用户可手动编辑，但建议通过 dashboard 操作避免冲突。

## 关于配置漂移

- ✓ `external-controller` 永远是 `127.0.0.1:9090`（dashboard 反代到这）
- ✓ `external-ui` 不需要（metacubexd 由 dashboard 在 `/ui/` 路径下托管）
- ✓ 用户在 dashboard 改订阅 → dashboard 重写 yaml → mihomo `reload from path` → 不动 external-controller
- ✓ MetaCubeXD 高级面板里的 "Update Config from URL" 仍可用，但**建议从主面板做**避免误操作

## Local Build

```bash
cd apps/mihomo
./update_mihomo.sh                  # 自动检测架构，拉取最新 mihomo + dashboard
./update_mihomo.sh --arch arm       # 强制 ARM
MIHOMO_VERSION=1.19.25 DASHBOARD_VERSION=v0.1.0 ./update_mihomo.sh
```

打包包括：
- `mihomo` 二进制（MetaCubeX/mihomo 上游）
- `fnos-mihomo-dashboard` 二进制（conversun/fnos-mihomo-dashboard 上游）
- `metacubexd/` 静态文件（MetaCubeX/metacubexd gh-pages）
- shell 启动器 + manifest + 防火墙规则

## 故障排查

### 1. 主面板打不开

- fnOS 应用中心 → Mihomo → 查看日志 (`${TRIM_PKGVAR}/mihomo.log`)
- 错误一般会写明 mihomo 或 dashboard 启动失败原因
- 重置：fnOS 应用中心 → 重启

### 2. 节点拉取失败

- 检查订阅 URL 在浏览器可达
- 主面板「日志」里看 mihomo 的 proxy-providers 错误
- 备用：通过 MetaCubeXD 高级面板 → 「Providers」→ 手动 Refresh

### 3. mihomo 启动失败

- 主面板「日志」会显示 mihomo 错误
- 即使 mihomo 挂了，dashboard 仍然可访问（运行在独立进程）
- SSH 救援：编辑 `/vol*/apps/mihomo/var/config/config.yaml`

## 上游版本

- mihomo 内核：跟随 MetaCubeX/mihomo latest release
- fnos-mihomo-dashboard：跟随 conversun/fnos-mihomo-dashboard latest release
- MetaCubeXD：跟随 gh-pages 分支最新快照
