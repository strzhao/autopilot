---
name: github-actions-setup
description: |
  配置 GitHub Actions 工作流，包括 CI/CD 自动触发、构建、测试等。
  当用户提到"配置 GitHub Actions"、"设置 CI/CD"、"添加 workflow"、"自动构建"、"自动测试"、
  "github action 触发"、"workflow 配置"、"CI 流水线"、"持续集成"时使用此技能。
  也适用于需要修改现有 workflow、排查 workflow 失败、或添加新的自动化流程的场景。
---

# GitHub Actions 工作流配置指南

帮助快速配置 GitHub Actions 工作流，覆盖常见的 CI/CD 场景。

## 工作流基础结构

```yaml
name: Workflow Name

on:
  # 触发条件
  push:
    branches: [main]

jobs:
  job-name:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Step name
        run: echo "Hello"
```

## 触发器配置

### Push 触发

```yaml
on:
  push:
    branches: [main, develop]        # 指定分支
    paths:                            # 路径过滤（可选）
      - 'src/**'
      - 'package.json'
    tags:
      - 'v*'                         # tag 匹配
```

### Pull Request 触发

```yaml
on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened]  # 默认就是这三个
```

### Release 触发

```yaml
on:
  release:
    types: [published]               # 发布 release 时触发
```

### 定时触发

```yaml
on:
  schedule:
    - cron: '0 2 * * 1-5'           # 工作日 UTC 2:00（北京时间 10:00）
```

### 手动触发

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deploy environment'
        required: true
        default: 'staging'
        type: choice
        options: [staging, production]
```

### 组合触发

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
```

## 常用工作流模板

### Node.js 项目 CI

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [20, 22, 24]
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: 'npm'

      - run: npm ci
      - run: npm run build
      - run: npm test
```

### Python 项目 CI

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.11', '3.12', '3.13']
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}

      - run: pip install -e ".[dev]"
      - run: pytest
```

### Docker 构建推送

```yaml
name: Docker

on:
  push:
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
```

### 部署到 Vercel / Cloudflare

对于前端项目，通常直接在 Vercel / Cloudflare 平台配置 Git 集成即可，无需手写 workflow。仅在需要自定义构建步骤或多环境部署时才需要 workflow。

## Environment 与 Secrets

### 创建 Environment

```bash
# 通过 gh CLI
gh api repos/{owner}/{repo}/environments/{env-name} -X PUT --input - <<< '{}'
```

### 添加 Secret

```bash
# 仓库级 secret
gh secret set SECRET_NAME --body "value"

# environment 级 secret
gh secret set SECRET_NAME --env production --body "value"
```

### 在 workflow 中使用

```yaml
jobs:
  deploy:
    environment: production          # 引用 environment
    steps:
      - run: deploy --token ${{ secrets.DEPLOY_TOKEN }}
```

## Permissions 配置

GitHub Actions 默认权限较小，某些操作需要显式声明：

```yaml
permissions:
  contents: read          # 读取仓库代码（默认）
  contents: write         # 推送代码、创建 tag
  id-token: write         # OIDC token（npm trusted publishing 等）
  packages: write         # 推送 GitHub Container Registry
  pull-requests: write    # 评论 PR
  issues: write           # 操作 issue
```

最小权限原则：只声明需要的权限。

## 实用技巧

### 缓存依赖

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 24
    cache: 'npm'          # 自动缓存 node_modules
```

### 条件执行

```yaml
- run: npm run deploy
  if: github.ref == 'refs/heads/main'   # 仅主分支
```

### 并行任务

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps: [...]

  test:
    runs-on: ubuntu-latest
    steps: [...]

  build:
    needs: [lint, test]                 # 等 lint 和 test 都过了再 build
    runs-on: ubuntu-latest
    steps: [...]
```

### 复用 workflow

```yaml
# .github/workflows/reusable.yml
on:
  workflow_call:
    inputs:
      node-version:
        type: string
        default: '24'

# 调用方
jobs:
  ci:
    uses: ./.github/workflows/reusable.yml
    with:
      node-version: '24'
```

## 排查 Workflow 失败

```bash
# 查看最近的 run
gh run list --limit 5

# 查看某次 run 的失败日志
gh run view {run-id} --log-failed

# 重新运行失败的 job
gh run rerun {run-id} --failed
```

常见失败原因：
1. **Node.js 版本过低** — 升级到需要的版本
2. **权限不足** — 检查 `permissions` 配置
3. **Secret 未配置** — 检查 Settings → Secrets
4. **依赖安装失败** — 检查 package-lock.json 是否提交
5. **actions/checkout/setup-node 版本过旧** — 升级到 v4/v5
