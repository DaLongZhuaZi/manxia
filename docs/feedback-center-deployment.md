# 漫匣反馈中心 ECS / Cloudflare 部署记录

反馈中心代码位于 `feedback-center/`，与现有 `cloudflare/manxia-worker` 分离。预检使用的 ECS 为 `47.77.221.34`，SSH 用户为 `root`；私钥路径只存在于本机，不应提交到 Git。

## 已确认的 ECS 条件（2026-08-05）

- Alibaba Cloud Linux 3 / OpenAnolis。
- Docker 26.1.3，Docker Compose v2.27.0。
- 根盘约 40 GB，当前剩余约 30 GB。
- 内存约 1.8 GiB，无 Swap。
- 现有 Homepage 服务使用独立 Compose 与 Cloudflare Tunnel；反馈服务不能占用或修改其容器和 Tunnel。
- 当前反馈服务设计不发布宿主机 80、443、8000、5432，仅由 cloudflared 出站连接访问 Docker 内部 API。

## 部署前需要补齐

1. Cloudflare 创建独立 Tunnel 和 `feedback.manxia.top` Public Hostname。
2. 创建 Turnstile Widget，允许 `feedback.manxia.top`，取得 Site Key（APP 挑战页使用）和 Secret（只放 ECS `.env`）。
3. 准备异地备份目标（推荐 OSS），并确认 ECS 磁盘容量告警。
4. 为 Cloudflare WAF 配置托管规则和对创建 Issue、支持、补充、上传会话的限速；后端限额仍然是最终约束。

## 验收命令

```bash
dig +short feedback.manxia.top
curl -fsS https://feedback.manxia.top/healthz
curl -fsS https://feedback.manxia.top/api/v1/issues
curl --connect-timeout 5 http://47.77.221.34:8000/healthz
ss -lntup
docker compose ps
```

公网 DNS 输出不应包含 `47.77.221.34`；直接访问 ECS 的反馈端口应失败。若 ECS 上仍有其他服务直连公网 IP，不能把“反馈中心不暴露源站”误解为“整台 ECS 的 IP 永远不可发现”。

