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
