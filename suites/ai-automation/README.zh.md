# AI 自动化套件

自托管 AI 自动化栈：工作流编排、本地 LLM 推理、向量搜索和低代码 AI 流构建器。灵感来自 [n8n-io/self-hosted-ai-starter-kit](https://github.com/n8n-io/self-hosted-ai-starter-kit)，适配 `mb` 套件规范（pinned tag、healthcheck、`mb-proxy` 网络、统一 `/data` 数据卷）。

## 包含内容

| 应用 | 用途 | 默认端口 | 配置文件 |
|------|------|----------|----------|
| n8n | 工作流 / Agent 自动化（可视化编辑器 + webhook） | 5678 | 默认 |
| Ollama | 本地 LLM 运行时（Llama 3、Qwen 等） | 11434 | 默认 |
| Qdrant | 向量数据库（RAG / 记忆） | 6333 | 默认 |
| Flowise | 低代码 AI 流构建器（拖拽式 LangChain） | 8150 | flowise |

## 架构

```
                         ┌──────────────┐
                         │  mb-proxy    │  (反向代理 / TLS)
                         │  网络        │
                         └──────┬───────┘
          ┌─────────────────────┼──────────────────────┐
          ▼                     ▼                      ▼
   ┌──────────────┐    ┌──────────────┐       ┌──────────────┐
   │     n8n      │───▶│    Ollama    │       │   Flowise    │
   │  :5678       │    │  :11434      │       │  :8150→3000  │
   │  工作流      │    │  本地 LLM    │       │  低代码 AI   │
   └──────┬───────┘    └──────────────┘       └──────┬───────┘
          │                                           │
          │            ┌──────────────┐               │
          └───────────▶│   Qdrant     │◀──────────────┘
                       │  :6333       │
                       │  向量数据库  │
                       └──────────────┘
```

- **n8n** 编排端到端自动化，通过共享的 `mb-proxy` 网络调用 Ollama（`OLLAMA_HOST=http://ollama:11434`）和 Qdrant（`QDRANT_URL=http://qdrant:6333`）。
- **Ollama** 从 `/data/ollama` 提供本地模型；用 `docker exec ollama ollama pull llama3.1` 拉取模型。
- **Qdrant** 存储嵌入向量，用于检索增强生成（RAG）和 Agent 记忆。
- **Flowise**（可选，`--profile flowise`）提供 n8n AI 节点的无代码替代方案，支持 LangChain 风格的流。

## 快速开始

1. 复制示例环境变量文件并填写你的值：

   ```bash
   cp .env.example .env
   # 编辑 .env —— 设置 AI_AUTOMATION_DOMAIN、N8N_ENCRYPTION_KEY、FLOWISE_PASSWORD
   ```

2. 创建数据目录（见[数据目录](#数据目录)）。

3. 启动核心服务（n8n + Ollama + Qdrant）：

   ```bash
   docker compose up -d
   ```

4. 同时启动 Flowise 构建器，使用 `flowise` profile：

   ```bash
   docker compose --profile flowise up -d
   ```

5. 一次性启动全部：

   ```bash
   docker compose --profile all up -d
   ```

6. 向 Ollama 拉取第一个 LLM：

   ```bash
   docker exec ollama ollama pull llama3.1
   ```

## 数据目录

所有持久化数据存放在宿主机 `/data` 下：

| 路径 | 服务 |
|------|------|
| `/data/n8n` | n8n 工作流、凭据、执行记录 |
| `/data/ollama` | Ollama 下载的模型 |
| `/data/qdrant/storage` | Qdrant 集合数据 |
| `/data/qdrant/snapshots` | Qdrant 快照 |
| `/data/flowise` | Flowise 流、凭据、数据库 |

## 端口规划

| 服务 | 宿主端口 | 容器端口 | 说明 |
|------|----------|----------|------|
| n8n | 5678 | 5678 | n8n 默认 |
| Ollama | 11434 | 11434 | Ollama 默认 |
| Qdrant | 6333 | 6333 | Qdrant 默认 |
| Flowise | 8150 | 3000 | 宿主端口 8150，避免与 dev-environment（Gitea，宿主 3000）和 self-hosted-cloud（Outline，宿主 3000）冲突 |

全局端口表见 [docs/port-allocation.md](../../docs/port-allocation.md)。

## 反向代理

此套件位于外部 `mb-proxy` Docker 网络上的反向代理之后。设置 TLS 终止并将流量路由到各服务的容器端口。常见布局：

- `https://ai.example.com/n8n/` → n8n `:5678`
- `https://ai.example.com/flowise/` → Flowise `:8150`
- `https://ai.example.com/qdrant/` → Qdrant `:6333`（建议限制为内部访问）

现成的反向代理 / 网络工具见：
https://github.com/0x10debug/network-toolkit

## 与 `ai-workstation` repo 的边界

此套件只部署**服务端、常驻运行的 AI 自动化服务**（工作流引擎、LLM 运行时、向量库、流构建器）。**不**包含：

- GPU 驱动 / CUDA 安装 —— 由宿主 OS 或 `vps-bootstrap` 处理。
- 桌面 ML 工具、Jupyter notebook、模型训练流水线 —— 属于 `ai-workstation` repo（交互式 / 按用户的工作站）。
- 模型微调或数据集管理 —— 同样属于 `ai-workstation`。

简言之：**compose-recipes/ai-automation = VPS 上 7×24 运行的共享服务；ai-workstation = 按开发者的交互式 ML 环境。** 两个 repo 互补，不重叠。

## 注意事项

- **GPU**：Ollama 默认用 CPU。要启用 GPU 加速，给 `ollama` 服务添加 `deploy.resources.reservations.devices`，并在宿主安装 NVIDIA Container Toolkit。见 [Ollama Docker 文档](https://github.com/ollama/ollama/blob/main/docs/docker.md)。
- **模型体积**：Ollama 模型存放在 `/data/ollama`，可能很大（多 GB）。确保 VPS 磁盘充足。
- **n8n 凭据**：`N8N_ENCRYPTION_KEY` 加密已存储的凭据。务必妥善保管；丢失后已有凭据无法恢复。
