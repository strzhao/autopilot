---
name: npm-publish
description: |
  配置 npm 包通过 GitHub Actions 自动发布到 npmjs.com。使用 OIDC Trusted Publishing（无需 npm token）。
  当用户提到"发布 npm"、"npm publish"、"配置 npm 自动发布"、"npm 包发布"、"设置 npm CI/CD"、
  "把包发到 npm"、"npm trusted publishing"、"OIDC 发布"时使用此技能。
  也适用于用户已有项目想添加 npm 自动发布流程的场景，或者 npm publish 失败需要排查的场景。
---

# npm 自动发布配置指南

将 npm 包通过 GitHub Actions + OIDC Trusted Publishing 自动发布，无需管理 npm token。

## 核心知识

### Node 版本要求

OIDC Trusted Publishing 需要 npm CLI >= 11.5.1。各 Node 版本对应的 npm：

| Node 版本 | npm 版本 | 是否支持 Trusted Publishing |
|-----------|---------|--------------------------|
| Node 20   | npm 10.x | 不支持 |
| Node 22   | npm 10.9.x | 不支持 |
| Node 24   | npm 11.x+ | 支持 |

**必须使用 Node 24**，这是最常见的失败原因。

### Private 仓库限制

`--provenance` 签名仅支持 public 仓库。Private 仓库使用 `--provenance` 会报错：

```
Error verifying sigstore provenance bundle: Unsupported GitHub Actions source repository visibility: "private"
```

Private 仓库需要去掉 `--provenance` flag。

## 配置流程

### 第一步：确认 package.json 配置

确保 package.json 包含以下关键字段：

```json
{
  "name": "@scope/package-name",
  "version": "1.0.0",
  "files": ["dist", "README.md"],
  "publishConfig": {
    "access": "public"
  }
}
```

- scoped 包（`@xxx/yyy`）需要 `publishConfig.access: "public"`，否则默认 restricted
- `files` 字段控制发布内容，避免发布 src、node_modules 等

### 第二步：创建 GitHub Actions Workflow

创建 `.github/workflows/publish.yml`：

**Public 仓库（推荐，带 provenance）：**

```yaml
name: Publish to npm

on:
  release:
    types: [published]

jobs:
  publish:
    runs-on: ubuntu-latest
    environment: npm
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 24
          registry-url: https://registry.npmjs.org

      - run: npm ci
      - run: npm run build
      - run: npm publish --provenance --access public
```

**Private 仓库（不带 provenance）：**

```yaml
name: Publish to npm

on:
  release:
    types: [published]

jobs:
  publish:
    runs-on: ubuntu-latest
    environment: npm
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 24
          registry-url: https://registry.npmjs.org

      - run: npm ci
      - run: npm run build
      - run: npm publish --access public
```

关键配置说明：
- `environment: npm` — 必须与 npmjs.com 上配置的 environment 名称一致
- `permissions.id-token: write` — 允许 GitHub Actions 生成 OIDC token
- `node-version: 24` — 确保 npm >= 11.5.1
- `registry-url` — 必须设置，否则 npm publish 不知道往哪发

### 第三步：创建 GitHub Environment

通过 `gh` CLI 创建：

```bash
gh api repos/{owner}/{repo}/environments/npm -X PUT --input - <<< '{}'
```

或到 GitHub 仓库 Settings → Environments → New environment，名称填 `npm`。

### 第四步：在 npmjs.com 配置 Trusted Publisher

前提：包必须已经手动发布过至少一个版本（npm 要求包已存在才能配置 trusted publisher）。

1. 访问 `https://www.npmjs.com/package/{package-name}/access`
2. 找到 "Trusted Publisher" 部分
3. 选择 GitHub Actions，填入：
   - **Owner**: GitHub 用户名或组织名
   - **Repository**: 仓库名（不含 owner）
   - **Workflow**: `publish.yml`（仅文件名，不含路径）
   - **Environment**: `npm`（大小写敏感，必须精确匹配）

### 第五步：测试发布

1. 在 package.json 中 bump version
2. 提交并推送
3. 创建 GitHub Release：
   ```bash
   gh release create v{version} --title "v{version}" --notes "Release notes" --target main
   ```
4. 检查 workflow 运行状态：
   ```bash
   gh run list --limit 1
   gh run watch {run-id}
   ```

## 常见问题排查

### E404 Not Found

```
npm error 404 Not Found - PUT https://registry.npmjs.org/@scope%2fpackage
```

可能原因：
1. npm 版本太低（Node 22 以下），OIDC token 无法被识别 → 升级到 Node 24
2. Trusted Publisher 配置不匹配（owner/repo/workflow/environment 任一不对）→ 逐项检查
3. 包从未手动发布过 → 先本地 `npm publish` 一次

### E422 Unprocessable Entity (provenance)

```
Error verifying sigstore provenance bundle: Unsupported GitHub Actions source repository visibility: "private"
```

→ Private 仓库去掉 `--provenance` flag。

### npm warn Unknown user config "always-auth"

这是 npm 11+ 的警告，不影响发布，可忽略。

### 首次发布

Trusted Publishing 无法用于首次发布（包不存在时无法配置）。首次发布流程：
1. 确保本地 npm 已登录：`npm whoami`，未登录则 `npm adduser`
2. 确认 registry：`npm config get registry`（应为 `https://registry.npmjs.org`）
3. Build 项目：`npm run build`
4. 手动发布：`npm publish --access public`
5. 发布成功后再去 npmjs.com 配置 Trusted Publisher
