## 2026-05-12

- 启用 1-tap self-update：挂载 `/var/run/docker.sock` + `group_add: ["999"]`，让 ZoneFoundry iOS app 的"升级"按钮直接拉取并应用新镜像，不用 SSH 或 Container Manager
- 跟 Unraid CA 模板 (`selfhosters/unRAID-CA-templates#668`) 行为一致

## 2026-05-10

- 首次发布
