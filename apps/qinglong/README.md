## QingLong for fnOS

每日自动同步 [QingLong 官方](https://github.com/whyour/qinglong) 最新版本并构建 `.fpk` 安装包。

## 下载

从 [Releases](https://github.com/conversun/fnos-apps/releases?q=qinglong) 下载最新的 `.fpk` 文件。

## 安装

1. 根据设备架构下载对应的 `.fpk` 文件
2. fnOS 应用管理 → 手动安装 → 上传

**访问地址**: `http://<NAS-IP>:5700`

> 首次访问 Web 界面将引导您完成初始管理员账号设置。

## 说明

- 支持 Python / JavaScript / Shell / TypeScript 的定时任务管理面板
- 内置 cron 调度与 PM2 进程管理
- 支持脚本编辑、运行日志查看、依赖管理
- 基于 Docker 部署，首次启动需要拉取镜像
- 数据持久化目录: `/ql/data`（包含脚本、配置、日志、数据库、依赖缓存）

## 本地构建

```bash
cd apps/qinglong && ./update_qinglong.sh
```

## Credits

- [QingLong](https://github.com/whyour/qinglong) by [whyour](https://github.com/whyour)
