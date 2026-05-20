## 2026-05-21

- v0.2.2: 嵌入 Mozilla CA 证书包, dashboard 在无 ca-certificates 的极简 Linux 环境 (容器) 也能完成 HTTPS 订阅验证 / 拉取
- 端到端自测覆盖: bad URL 拒绝 / 合法 URL 接受 / 备份文件 / 订阅信息 / 覆盖应用 / refresh
- bump fnos-mihomo-dashboard 至 v0.2.2

## 2026-05-21

- v0.2.1: 自测修复
  - 保存订阅前预验证 URL: 拒绝 HTML 页面 (如 example.com 误填) / 4xx / 空响应 / 非 yaml 内容
  - 自测确认: 错误 URL 立即返回 400, 正确 URL 通过验证并被 mihomo 加载
- bump fnos-mihomo-dashboard 至 v0.2.1

## 2026-05-21

- v0.2.0: 三项关键安全/自动化能力
  - **配置回滚**: 保存订阅时先备份, mihomo reload 失败自动回滚, 不再因配置错误失联
  - **订阅自动刷新**: 后台 ticker 默认每 12 小时刷新订阅 (proxy-provider + subscription-userinfo)
  - **流量/到期信息**: 解析机场返回的 subscription-userinfo 头, 主面板展示已用流量与剩余天数, 含「立即更新订阅」按钮
- bump fnos-mihomo-dashboard 至 v0.2.0

## 2026-05-21

- 主面板新增「最终配置文件」展示卡片, 可一键复制, 折叠/展开
- 用户可直接查看 dashboard 写入 mihomo 的 yaml 全文 (含 fnOS 旁路由覆盖与订阅源 proxy-providers)
- bump fnos-mihomo-dashboard 至 v0.1.5

## 2026-05-21

- 新增 fnOS 旁路由配置覆盖功能 (基于 mihomo 实战笔记):
  - 强制 profile.store-selected + store-fake-ip (重启保留选择)
  - 自动启用 TLS/HTTP/QUIC Sniffer (透明代理规则匹配必需, 解决坑14)
  - 自动剔除 tun.inet4-route-exclude-address 中的 198.18.0.0/16 (fake-ip 必须由 TUN 接管, 解决坑11)
- dashboard 主面板新增「fnOS 旁路由优化」卡片, 列出每次保存订阅后自动应用的覆盖项
- bump fnos-mihomo-dashboard 至 v0.1.4

## 2026-05-21

- 移除自研面板的「节点选择」与「当前节点」展示, 这些与 MetaCubeXD 高级面板重复
- 主面板聚焦订阅管理 / 内核状态 / 日志 (MetaCubeXD 没有的能力), 重复能力交给「高级管理」按钮
- bump fnos-mihomo-dashboard 至 v0.1.3

## 2026-05-21

- 修复 metacubexd 在 /clash/ 子路径下无法连接 mihomo 后端的问题
- dashboard 现在动态生成 /clash/config.js 让 metacubexd 自动通过 /mihomo 反代路径访问内核
- 用户进入「高级管理」时无需手动填后端 URL, 直接可用

## 2026-05-21

- 修复 mihomo 内部 API 端口与系统中常见 Prometheus (默认 0.0.0.0:9090) 冲突的问题
- mihomo external-controller 改为 127.0.0.1:19090 (冷门端口, 避开 fnOS 应用生态中已占用的 9090)
- 用户侧无感: fnOS 暴露端口仍为 9097, dashboard 反代到新内部端口

## 2026-05-20

- 首次发布
- mihomo (Clash.Meta) 内核 + 自研 fnos-mihomo-dashboard 管理面板 + MetaCubeXD 高级面板一体化打包
- **架构调整**：dashboard (port 9097) 反代 mihomo (127.0.0.1:9090)，彻底解决：
  - SAFE_PATHS: dashboard 用反代而非 external-ui，无路径检查
  - external-controller 漂移: mihomo 通过文件加载配置，不接受 dashboard payload 中的 external-controller 字段
  - 浏览器 fetch 拦截脆弱: 全部由服务端 dashboard 控制，无需 JS hook
- 主面板提供订阅管理 / 状态 / 节点选择 / 日志（覆盖 90% 日常场景）
- 保留 MetaCubeXD 在 `/ui/` 作为高级用户的逃生通道
- 默认端口: 9097 (管理), 7890 (HTTP+SOCKS5 代理)
- 安装时通过 setcap 授权支持 TUN 模式
- 双进程托管: bin/mihomo-server 启动 mihomo 子进程 + dashboard 前台主进程，挂任一可恢复
