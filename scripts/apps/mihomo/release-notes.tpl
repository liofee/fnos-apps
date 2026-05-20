自动构建的 fnOS 安装包

- 基于 [Mihomo v${VERSION}](https://github.com/MetaCubeX/mihomo/releases/tag/v${VERSION}) (Clash.Meta 内核)
- Dashboard: [MetaCubeXD](https://github.com/MetaCubeX/metacubexd) (gh-pages 最新)
- 平台: fnOS${REVISION_NOTE}

### 端口与访问

| 端口 | 用途 |
|---|---|
| `${DEFAULT_PORT}` | 外部管理 API + MetaCubeXD dashboard, 访问 `http://<NAS_IP>:${DEFAULT_PORT}/ui/` |
| `7890` | HTTP + SOCKS5 混合代理 (LAN 可用) |
| `1053` (localhost) | 内部 DNS (TUN 模式下劫持 53 端口) |

### 默认行为

- **零外部依赖**: 安装即用, 不下载任何远程模板
- **默认开 LAN 访问** (`allow-lan: true`), 局域网内任意设备可用代理
- **TUN 模式默认关闭**: 安装时已自动 `setcap` 授予 `CAP_NET_ADMIN / NET_RAW / NET_BIND_SERVICE`, 启用直接生效
- **GeoIP / GeoSite 自动更新**: 启动后通过 ghfast.top CDN 拉取, 每 24 小时刷新

### 添加代理节点

dashboard **不支持**直接编辑 yaml. 请用 SSH 或 fnOS 文件管理器编辑:

```
/vol*/apps/mihomo/var/config/config.yaml
```

在 `proxies:` 下追加自己的节点 (Shadowsocks / V2Ray / Trojan / Hysteria2 等), 然后在 dashboard 点 "Reload Config" 或 fnOS 应用中心重启 Mihomo.

需要完整分流规则的用户可手动引入 [Sukka 公共规则](https://ruleset.skk.moe/) 或自维护订阅.

### 三层故障防线

每次启动: 强制注入框架字段 (external-controller / external-ui) → `mihomo -t` 预校验 → 验证失败自动降级到 minimal default 并备份原配置, **保证 dashboard 永远可访问**.
${CHANGELOG}
**国内镜像**:
- [${FILE_PREFIX}_${FPK_VERSION}_x86.fpk](https://ghfast.top/https://github.com/conversun/fnos-apps/releases/download/${RELEASE_TAG}/${FILE_PREFIX}_${FPK_VERSION}_x86.fpk)
- [${FILE_PREFIX}_${FPK_VERSION}_arm.fpk](https://ghfast.top/https://github.com/conversun/fnos-apps/releases/download/${RELEASE_TAG}/${FILE_PREFIX}_${FPK_VERSION}_arm.fpk)
