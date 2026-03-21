# npm-toolkit

npm 发布与 GitHub Actions CI/CD 配置工具包。

## 包含技能

### npm-publish

配置 npm 包通过 GitHub Actions + OIDC Trusted Publishing 自动发布，无需管理 npm token。

核心经验：
- **必须用 Node 24**（npm 11+），Node 22 的 npm 10.x 不支持 OIDC
- **Private 仓库不能用 `--provenance`**，会报 E422
- 首次发布必须手动 `npm publish`，之后才能配置 Trusted Publisher

### github-actions-setup

GitHub Actions 工作流配置，覆盖常见 CI/CD 场景：
- Push / PR / Release / 定时 / 手动触发
- Node.js / Python / Docker 项目模板
- Environment、Secrets、Permissions 配置
- 排查 workflow 失败的方法
