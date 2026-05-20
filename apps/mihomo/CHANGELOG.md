## 2026-05-20

- 首次发布
- mihomo (Clash.Meta) 内核 + MetaCubeXD dashboard 一体化打包
- 默认管理端口 9097 (避开 9090 与现有 Prometheus 冲突)
- 默认混合代理端口 7890 (HTTP + SOCKS5), 暴露至 LAN
- 安装时通过 setcap 授予 CAP_NET_ADMIN / CAP_NET_RAW / CAP_NET_BIND_SERVICE, 支持 TUN 模式
- 默认通过 ghfast.top CDN 自动下载 GeoIP / GeoSite 数据库
- 零外部依赖: minimal default 配置硬编码在 bin/mihomo-server 中, 不依赖任何远程模板 / CDN
- 三层故障防线: 每次启动强制注入框架字段 + mihomo -t 预校验 + 验证失败自动降级到 minimal default (保证 dashboard 永远可访问)
