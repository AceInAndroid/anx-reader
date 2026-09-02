# Anx Reader 自托管进度同步

这是一个只同步阅读位置的轻量 API。它不接收小说文件、SQLite 数据库、笔记、书签、AI 成果或用户设置；单次 JSON 请求限制为 64 KiB。

## 本地运行

```sh
npm ci
SYNC_USERNAME=reader \
SYNC_PASSWORD_HASH="$(node scripts/hash-password.js '至少12个字符的密码')" \
node src/server.js
```

密码哈希也可以交互式生成：`npm run hash-password`。不要把明文密码或哈希提交到 Git。

## Docker / NAS

复制 `.env.example` 为 `.env`，生成 `SYNC_PASSWORD_HASH` 和 Cloudflare Tunnel token。首次启动前创建可由容器内 UID 1000 写入的数据目录，然后运行：

```sh
mkdir -p data
chown 1000:1000 data
docker compose up -d --build
```

服务只通过 Docker 内部网络暴露 `8080`，compose 不做公网端口映射。`./data` 是 SQLite 持久化目录，请定期备份（备份前停止容器或复制 WAL 一致快照）。容器以 `node` 非 root 用户运行。

## Cloudflare Tunnel

在 Cloudflare Zero Trust 创建 Tunnel，将 `sync.example.com` 指向：

```text
http://anx-progress-sync:8080
```

将 `cloudflared` 与 API 加入同一 Docker 网络。只发布这个独立子域名；不要在 API 前放 Cloudflare Access 的浏览器登录页，Anx Reader 使用 API 返回的 Bearer token。API 已设置 no-store、noindex、安全内容类型响应头；在 Cloudflare 侧为 `/v1/*` 配置速率限制和禁用缓存。

## API

- `GET /health`
- `POST /v1/auth/login`：单账号登录（无注册）
- `POST /v1/auth/logout`
- `PUT /v1/books/:bookKey/devices/:deviceId/progress`
- `DELETE /v1/books/:bookKey/devices/:deviceId/progress`
- `GET /v1/books/:bookKey/progress`
- `GET /v1/changes?cursor=<revision>`

首次增量同步省略 cursor，返回当前全量快照；之后保存 `nextCursor`。变更保留 90 天/最多 100,000 条，过期游标返回 `409 cursor_expired`，客户端应重新全量同步。

## 运维

SQLite 启用 WAL、外键和 5 秒 busy timeout。日志只包含错误摘要，不记录请求体、定位文本、密码或 Authorization。环境变量：`PORT`、`DATABASE_PATH`、`SESSION_TTL_DAYS`、`CHANGE_RETENTION_DAYS`、`MAX_CHANGES`。

```sh
npm test
```
