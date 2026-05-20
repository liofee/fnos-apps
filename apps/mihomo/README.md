# Mihomo for fnOS

[Mihomo](https://github.com/MetaCubeX/mihomo)(前 Clash.Meta)多协议代理内核 + [MetaCubeXD](https://github.com/MetaCubeX/metacubexd) 可视化面板, 打包为 fnOS 第三方应用. 零外部依赖, 安装即可用.

## 功能特性

- **多协议代理**: Shadowsocks / V2Ray / Trojan / Hysteria2 / WireGuard / Tuic 等
- **可视化面板**: `http://<NAS_IP>:9097/ui/`
- **混合代理端口**: `7890/tcp` (HTTP + SOCKS5 同端口), 默认监听 `0.0.0.0`, LAN 内任意设备可用
- **TUN 模式**: 默认关闭, 可在 dashboard 启用, 安装时已通过 `setcap` 授予所需 Linux capabilities
- **GeoIP / GeoSite 自动更新**: 通过 ghfast.top CDN 加速, 每 24 小时刷新
- **零外部依赖**: 不下载远程模板, 不依赖第三方 repo

## 端口分配

| 端口 | 协议 | 用途 |
|------|------|------|
| 9097 | TCP | 外部管理 API + MetaCubeXD dashboard |
| 7890 | TCP | HTTP + SOCKS5 混合代理 |
| 1053 | UDP/TCP (localhost) | 内部 DNS (TUN 模式下劫持 53 端口) |

## 快速上手

### 1. 安装并打开 dashboard

在 fnOS 应用中心点击 Mihomo 图标, 浏览器自动打开 `http://<NAS_IP>:9097/ui/`. dashboard 默认无 secret, 可在「设置」中修改.

### 2. 添加代理节点 (关键步骤)

dashboard **不支持**直接编辑 yaml. 用以下任一方式编辑 `config.yaml`:

- **SSH**: `nano /vol*/apps/mihomo/var/config/config.yaml`
- **fnOS 文件管理器**: 打开 `apps/mihomo/var/config/config.yaml`

在 `proxies:` 下追加自己的节点, 例如:

```yaml
proxies:
  - name: "HK-01"
    type: ss
    server: example.com
    port: 443
    cipher: aes-128-gcm
    password: your-password
```

或使用 [proxy-providers](https://wiki.metacubex.one/config/proxy-providers/) 从订阅 URL 自动拉取:

```yaml
proxy-providers:
  my-sub:
    type: http
    url: "https://your-subscription-url"
    interval: 86400
    path: ./providers/my-sub.yaml
    health-check:
      enable: true
      url: http://www.gstatic.com/generate_204
      interval: 300

proxy-groups:
  - name: "PROXY"
    type: select
    use:
      - my-sub
    proxies:
      - DIRECT
```

### 3. 重新加载配置

任选其一:
- dashboard → 点击「Reload Config」按钮 (右上角或设置区域, 取决于 dashboard 主题)
- fnOS 应用中心 → Mihomo → 重启

### 4. 启用 TUN 模式 (可选)

透明代理整个 NAS 出口流量:
- 编辑 config.yaml 中 `tun.enable: true`
- 或 dashboard → 「设置」→ 开启 TUN

## 配置文件位置

```
${TRIM_PKGVAR}/config/config.yaml
```

## 故障排查 (三层防线)

mihomo + dashboard 是强耦合体系, 本应用通过分层降级保证用户永远不会失联.

### 第 1 层 [99% 情况]: mihomo 正常运行

用户通过 dashboard (`http://<NAS_IP>:9097/ui/`) 控制一切:
- 切换代理节点 / 策略组
- 看实时流量与连接
- 查看运行日志
- 切换 mode / log-level / TUN 等基本字段

注意: metacubexd dashboard **不支持**直接编辑 yaml 配置, 编辑请用 SSH 或文件管理器.

### 第 2 层 [config.yaml 错误]: 自动降级

每次启动前 `mihomo -t` 验证配置:
- 验证通过 → 正常启动
- 验证失败 → 备份原配置到 `config.failed-<timestamp>.yaml`, 切换到 minimal default, **dashboard 仍可访问**
- 日志中会写明备份位置与恢复步骤

### 第 3 层 [极端情况]: minimal default 也挂

- **fnOS 应用中心 → Mihomo → 查看日志**: 所有 mihomo 启动错误都写在 `${TRIM_PKGVAR}/mihomo.log`
- **SSH / 文件管理器编辑** `/vol*/apps/mihomo/var/config/config.yaml`
- **重置配置**: 删除 `config.yaml` 后重启应用, 会自动重新生成 minimal default

## 端口 / 字段管理边界

| 字段 | 谁管 | 说明 |
|------|------|------|
| `external-controller` 端口 | **fnOS 框架强制** | 每次启动还原为 `0.0.0.0:<manifest.service_port>` |
| `external-ui` 路径 | **fnOS 框架强制** | 每次启动还原为 `metacubexd` (相对 home dir, symlink 到只读 dashboard 目录) |
| `secret` | **用户管理** | 默认为空, 可在 dashboard 设置 |
| `tun.enable` | **用户管理** | 默认关闭, 启用前已通过 setcap 授权 |
| `proxies` / `proxy-providers` / `rules` / 其他业务字段 | **用户管理** | dashboard 仅查看, 编辑请用 SSH 或文件管理器 |

## Local Build

```bash
cd apps/mihomo
./update_mihomo.sh                  # 自动检测架构, 拉取最新版
./update_mihomo.sh --arch arm       # 强制 ARM
./update_mihomo.sh 1.19.25          # 指定版本
```

## 上游版本管理

MetaCubeXD dashboard 始终拉取 `gh-pages` 分支最新快照, 跟随 mihomo 内核版本一同打包发布.
