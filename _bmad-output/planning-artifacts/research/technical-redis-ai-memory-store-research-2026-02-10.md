---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Redis as AI Agent Memory Store in n8n'
research_goals: 'Determine if current n8n-deploy docker-compose config needs changes to support Redis as AI agent memory store'
user_name: 'Boss'
date: '2026-02-10'
web_research_enabled: true
source_verification: true
---

# Enabling Redis as AI Agent Memory Store in n8n: Technical Research Report

**Date:** 2026-02-10
**Author:** Boss
**Research Type:** Technical — Infrastructure Configuration Analysis

---

## Executive Summary

Your existing n8n-deploy stack can support Redis as an AI agent memory store with **minimal configuration changes** — no new services, no image swaps, no architectural redesign. The current `redis:7` instance already on the Docker `web` network is reachable by all workers and the main n8n instance, providing the shared state needed for persistent AI agent conversations across a distributed queue-mode deployment.

However, **one critical config issue must be fixed first**: the current `--maxmemory-policy allkeys-lru` eviction policy will **silently delete conversation history** when Redis approaches its memory limit. This policy was correct for a queue-only workload but is incompatible with persistent chat memory data.

**Key Findings:**

- n8n has a built-in **Redis Chat Memory** node (LangChain integration) — configured at the workflow level, not infrastructure level
- Simple Memory (Window Buffer) is **broken in queue mode** — Redis or Postgres Chat Memory are the only viable production options
- Bull queue keys (`bull:*`) and chat memory keys (`message_store:*`) coexist safely with no collision risk
- Your deployment already has a complete **three-tier AI memory architecture** (Redis + Postgres + Qdrant) once this change is applied
- The total memory budget impact is +512MB (22GB → 22.5GB), well within your 32GB server's headroom

**Required Changes (answer to the original question):**

1. **Eviction policy**: `allkeys-lru` → `noeviction` (prevents silent data loss)
2. **Memory limit**: `maxmemory` 1gb → 1.5gb, container limits proportionally increased
3. **Authentication** (recommended): Add `--requirepass` + `QUEUE_BULL_REDIS_PASSWORD` to all services
4. **Healthcheck**: Add password flag to Redis healthcheck command
5. **n8n UI**: Create a Redis credential and wire Redis Chat Memory nodes into AI Agent workflows

---

## Table of Contents

1. [Research Introduction and Methodology](#1-research-introduction-and-methodology)
2. [Technology Stack Analysis](#2-technology-stack-analysis)
3. [Integration Patterns Analysis](#3-integration-patterns-analysis)
4. [Architectural Patterns and Design Decisions](#4-architectural-patterns-and-design-decisions)
5. [Implementation Guide](#5-implementation-guide)
6. [Risk Assessment and Mitigation](#6-risk-assessment-and-mitigation)
7. [Recommendations and Roadmap](#7-recommendations-and-roadmap)
8. [Source Documentation](#8-source-documentation)

---

## 1. Research Introduction and Methodology

### Research Significance

n8n's AI agent capabilities depend on persistent memory to maintain conversation context across interactions. In a queue-mode deployment where workflows execute on different workers, in-process memory is lost between executions. This makes external memory stores like Redis essential — not optional — for production AI agent workflows.

This research was prompted by a direct question: **"Do we need to update anything in our config to use Redis as an AI agent memory store?"** The answer required analyzing how n8n's memory system works, how it interacts with the existing Redis queue infrastructure, and what specific changes are needed.

### Research Methodology

- **Technical Scope**: n8n AI memory architecture, Redis configuration, Docker Compose integration, queue-mode compatibility
- **Data Sources**: Official n8n documentation, Redis documentation, n8n GitHub issue tracker, LangChain API docs, community forums, and current (2025-2026) technical guides
- **Analysis Framework**: Existing `docker-compose.yml` and `.env.sample` analyzed against n8n requirements; eviction policies evaluated against mixed workload patterns
- **Confidence Levels**: All claims tagged with confidence assessments; HIGH confidence requires multi-source verification

### Research Goals — Achieved

**Original Goal:** Determine if the current n8n-deploy docker-compose config needs changes to support Redis as AI agent memory store.

**Achieved:**
- Identified exact config changes needed (4 in docker-compose.yml, 1 in .env)
- Discovered critical eviction policy conflict that would cause silent data loss
- Confirmed no new services or image changes are required for chat memory
- Produced copy-paste-ready implementation guide with deployment sequence

---

## 2. Technology Stack Analysis

### n8n AI Agent Memory Types

n8n provides a modular memory system for AI agents through its LangChain integration. The available memory backends are:

| Memory Type | Persistence | Production-Ready | Use Case |
|---|---|---|---|
| **Simple Memory (Window Buffer)** | In-process only | No — data lost on restart; broken in queue mode | Development/testing only |
| **Redis Chat Memory** | Persistent (Redis) | Yes | Real-time chat, low-latency session memory |
| **Postgres Chat Memory** | Persistent (PostgreSQL) | Yes | Long-term conversation storage |
| **MongoDB Chat Memory** | Persistent (MongoDB) | Yes | Flexible document-based memory |

**Critical for queue mode:** Simple Memory (Window Buffer) **does not work** in queue mode deployments because workers don't share in-process memory. The current n8n-deploy setup runs in queue mode, so Redis or Postgres Chat Memory are the only viable options.

_Confidence: HIGH — confirmed via official n8n docs and multiple community sources_
_Source: [n8n Simple Memory Docs](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.memorybufferwindow/), [n8n Redis Chat Memory Docs](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.memoryredischat/)_

### Redis Chat Memory Node

The **Redis Chat Memory** node (`n8n-nodes-langchain.memoryredischat`) stores and retrieves conversation history in Redis. Key parameters:

- **Session ID** — Unique identifier per conversation/user (must be dynamic, not hardcoded)
- **Session Time To Live** — Auto-expire sessions after N seconds
- **Context Window Length** — Number of previous interactions to include (note: [known bug #12193](https://github.com/n8n-io/n8n/issues/12193) where this limit may not be respected)
- **Credentials** — Redis connection: host, port, password (optional), database number, SSL toggle

The node is configured **within n8n workflows** (not at the infrastructure level). You drag a Redis Chat Memory sub-node and connect it to an AI Agent node's memory input.

**Known issue:** Redis Chat Memory has a [different message shape](https://github.com/n8n-io/n8n/issues/11730) than Window Buffer Memory and is **not** a drop-in replacement — workflow adjustments may be needed when migrating.

_Confidence: HIGH — verified against official docs and GitHub issues_
_Source: [Redis Chat Memory Node Docs](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.memoryredischat/), [GitHub Issue #11730](https://github.com/n8n-io/n8n/issues/11730)_

### Redis Vector Store (Out of Scope)

n8n also supports a **Redis Vector Store** node for embedding-based semantic search (RAG). This is a **different capability** from chat memory:

- **Requires the RediSearch module** — NOT available in the standard `redis:7` image
- Requires switching to `redis/redis-stack-server:latest` Docker image
- The current Qdrant deployment already handles vector storage

_Confidence: HIGH — confirmed via [Redis Blog](https://redis.io/blog/n8ns-redis-vector-store-node/) and [n8n Redis Vector Store Docs](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.vectorstoreredis/)_

### Current Redis Configuration Analysis

The existing `docker-compose.yml` Redis service:

```yaml
redis:
  image: redis:7
  command:
    - "redis-server"
    - "--maxmemory" "1gb"
    - "--maxmemory-policy" "allkeys-lru"
    - "--appendonly" "yes"
    - "--appendfsync" "everysec"
  deploy:
    resources:
      limits: { memory: 1536m }
      reservations: { memory: 1g }
```

**Critical finding — eviction policy conflict:**

| Setting | Current Value | Impact on Chat Memory |
|---|---|---|
| `maxmemory` | 1gb | Shared between Bull queues AND chat memory data |
| `maxmemory-policy` | `allkeys-lru` | **WILL EVICT chat memory data** when memory is full — LRU eviction applies to ALL keys including conversation history |
| `appendonly` | yes | AOF persistence is enabled (good — data survives Redis restart) |
| No password | — | Redis Chat Memory credential in n8n supports password; currently no auth is configured |

_Confidence: HIGH — confirmed via [Redis Eviction Docs](https://redis.io/docs/latest/develop/reference/eviction/) and docker-compose.yml analysis_

---

## 3. Integration Patterns Analysis

### Two Independent Redis Connection Paths

n8n uses **two completely separate mechanisms** to connect to Redis:

| Connection Path | Purpose | Configuration Method | Used By |
|---|---|---|---|
| **Environment Variables** (`QUEUE_BULL_REDIS_HOST`, `QUEUE_BULL_REDIS_DB`) | Queue mode job broker | `docker-compose.yml` env vars | Bull queue (main + workers) |
| **n8n Credentials** (Host, Port, Password, DB Number) | Workflow node operations | n8n UI → Settings → Credentials | Redis Chat Memory node, Redis node |

These are **independent connections**. The Bull queue env vars do NOT automatically configure workflow-level Redis nodes. You must create a Redis credential in the n8n UI separately.

_Confidence: HIGH — confirmed via [n8n Queue Mode Docs](https://docs.n8n.io/hosting/scaling/queue-mode/) and [Redis Credentials Docs](https://docs.n8n.io/integrations/builtin/credentials/redis/)_

### Redis Key Namespace Isolation

Bull queue keys and Chat Memory keys use **different prefixes** and naturally coexist without collision:

| Data Type | Key Pattern | Example | TTL Behavior |
|---|---|---|---|
| Bull queue jobs | `bull:{queue_name}:{key_type}` | `bull:n8n:jobs:123` | Auto-expires (job lifecycle) |
| Chat Memory | `message_store:{session_id}` | `message_store:user-abc-123` | No TTL by default (persistent) |

**There is no key collision risk** between queue data and chat memory data on the same Redis instance.

_Confidence: HIGH — verified via [LangChain RedisChatMessageHistory API](https://api.python.langchain.com/en/latest/chat_message_histories/langchain_community.chat_message_histories.redis.RedisChatMessageHistory.html) and [BullMQ Docs](https://docs.bullmq.io/bull/patterns/redis-cluster)_

### Database Number Isolation

Redis supports 16 logical databases (0-15). An additional isolation layer:

- `QUEUE_BULL_REDIS_DB` controls which DB number Bull uses (default: `0`)
- Redis Chat Memory credential has its own "Database Number" field (recommended: `1`)

Note: `maxmemory` and `maxmemory-policy` are **per-instance**, not per-database. All databases share the same memory pool.

_Confidence: HIGH — confirmed via [Redis Eviction Docs](https://redis.io/docs/latest/develop/reference/eviction/)_

### Eviction Policy Options

| Policy | Behavior | Bull Queue Impact | Chat Memory Impact | Verdict |
|---|---|---|---|---|
| **`noeviction`** | Returns OOM errors on write | Safe — jobs self-clean, rarely >50MB | Protected — never silently deleted | **Recommended** |
| `volatile-lru` | Evicts only keys with TTL | Bull keys eligible for eviction | Protected if no Session TTL set | Viable alternative |
| `allkeys-lru` (current) | Evicts any key by LRU | Fine for queues | **Chat history WILL be deleted** | Incompatible |

_Confidence: HIGH — [Redis Eviction Docs](https://redis.io/docs/latest/develop/reference/eviction/), [Redis Cache Strategies](https://medium.com/@srujana.dakoju/redis-cache-eviction-strategies-b806c67e37c0)_

### Known Integration Issues

1. **Connection churn**: [Reported issue](https://github.com/redis/redis/issues/14591) — AI Agent node creates a new Redis connection on every execution
2. **Context Window Length bug**: [#12193](https://github.com/n8n-io/n8n/issues/12193) — may load full history regardless of limit
3. **Not a drop-in for Simple Memory**: [#11730](https://github.com/n8n-io/n8n/issues/11730) — different message shape

---

## 4. Architectural Patterns and Design Decisions

### System Architecture

```
┌─────────────┐     ┌───────────┐     ┌────────────────┐
│   Caddy      │────▶│  n8n Main │────▶│   PostgreSQL    │
│  (HTTPS)     │     │  (UI/API) │     │  (Persistent DB) │
└─────────────┘     └─────┬─────┘     └────────────────┘
                          │
                    ┌─────▼─────┐
                    │   Redis    │◀─── Bull Queue (DB 0)
                    │   :6379   │◀─── Chat Memory (DB 1)  ← NEW
                    └─────┬─────┘
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
        ┌──────────┐┌──────────┐┌──────────┐
        │ Worker 1 ││ Worker 2 ││ Worker 3 │
        └──────────┘└──────────┘└──────────┘
```

**Key property**: Any worker can read/write the same chat memory sessions. Session ID determines which conversation — not which worker. This is the correct behavior for distributed queue-mode.

_Confidence: HIGH — verified via [n8n Queue Mode Docs](https://docs.n8n.io/hosting/scaling/queue-mode/) and [n8n Community](https://community.n8n.io/t/can-i-create-multiagent-systems-with-shared-memory-using-n8n/81084)_

### Design Decision: Single Instance with Logical Separation

**Decision: Keep one Redis instance, use DB numbers for separation.**

- Bull queue data (DB 0): transient, auto-expires, typically <50MB
- Chat memory data (DB 1): persistent, bounded by session count
- Total footprint comfortably fits 1.5GB
- Second container would waste ~1GB RAM with minimal benefit

_Confidence: HIGH_

### Design Decision: Eviction Policy → `noeviction`

**Decision: Switch from `allkeys-lru` to `noeviction`.**

| Concern | Assessment |
|---|---|
| Bull queue under noeviction | Safe — jobs are transient with TTL, self-cleaning |
| Chat memory under noeviction | Protected — never silently deleted |
| What happens at OOM? | Redis returns errors for writes; system stays up |
| Monitoring requirement | Alert at 80% of maxmemory |

_Source: [Redis Eviction Docs](https://redis.io/docs/latest/develop/reference/eviction/)_

### Design Decision: Add Redis Authentication

**Decision: Add `--requirepass` for defense-in-depth.**

Redis now stores conversation data, not just transient queue jobs. Password auth adds a security layer even within the Docker network.

_Source: [Docker Redis security practices](https://nickjanetakis.com/blog/docker-tip-27-setting-a-password-on-redis-without-a-custom-config)_

### Multi-Tier Memory Architecture (Complete)

| Tier | Store | Purpose | Status |
|---|---|---|---|
| **Short-term (session)** | Redis Chat Memory | Active conversation context | After config change |
| **Long-term (persistent)** | Postgres Chat Memory | Historical conversations | Already available |
| **Semantic (RAG)** | Qdrant Vector Store | Knowledge base, embeddings | Already running |

_Source: [Redis — AI Agent Memory](https://redis.io/blog/ai-agent-memory-stateful-systems/), [Towards AI — n8n Memory Guide](https://towardsai.net/p/machine-learning/n8n-ai-agent-node-memory-complete-setup-guide-for-2026)_

### Scalability

| Factor | Current | With Chat Memory |
|---|---|---|
| Redis connections | 4 persistent (main + 3 workers) | +1 transient per AI agent execution |
| Memory growth | Stable (queue self-cleans) | ~1-10KB per session; 10K sessions ≈ 10-100MB |
| Latency | Sub-ms | Sub-ms (no change) |
| Backup | AOF (already enabled) | Chat memory included automatically |

---

## 5. Implementation Guide

### docker-compose.yml Changes

#### Change 1: Redis Service

```yaml
# BEFORE:
command:
  - "redis-server"
  - "--maxmemory"
  - "1gb"
  - "--maxmemory-policy"
  - "allkeys-lru"
  - "--appendonly"
  - "yes"
  - "--appendfsync"
  - "everysec"
deploy:
  resources:
    limits:
      memory: 1536m
    reservations:
      memory: 1g

# AFTER:
command:
  - "redis-server"
  - "--maxmemory"
  - "1.5gb"
  - "--maxmemory-policy"
  - "noeviction"
  - "--appendonly"
  - "yes"
  - "--appendfsync"
  - "everysec"
  - "--requirepass"
  - "${REDIS_PASSWORD}"
deploy:
  resources:
    limits:
      memory: 2g
    reservations:
      memory: 1536m
```

#### Change 2: Redis Healthcheck

```yaml
# BEFORE:
healthcheck:
  test: ["CMD", "redis-cli", "ping"]

# AFTER:
healthcheck:
  test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
```

#### Change 3: x-n8n Anchor Environment

Add alongside `QUEUE_BULL_REDIS_HOST=redis`:
```yaml
- QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
```

#### Change 4: All 3 Worker Environments

Add to **each** of `n8n-worker-1`, `n8n-worker-2`, `n8n-worker-3`:
```yaml
- QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
```

Workers duplicate their environment blocks (per CLAUDE.md pattern note), so all 3 must be updated individually.

### .env Changes

Add:
```bash
# =============================================================================
# Redis Authentication
# =============================================================================
REDIS_PASSWORD=change_me_to_a_secure_random_string
```

### n8n UI — Credential Setup

1. **Settings → Credentials → Add Credential → Redis**
2. Configure:

| Field | Value |
|---|---|
| Credential Name | `Redis - Chat Memory` |
| Host | `redis` |
| Port | `6379` |
| Password | _(same as REDIS_PASSWORD)_ |
| Database Number | `1` |
| SSL | Off |

3. **Test Connection** → Save

### Workflow Setup

1. Open/create workflow with **AI Agent** node
2. Click **Memory** input → select **Redis Chat Memory**
3. Configure:
   - **Credential**: `Redis - Chat Memory`
   - **Session ID**: Dynamic expression (e.g., `{{ $json.chatId }}`)
   - **Session Time To Live**: Optional (`86400` for 24h, or empty for permanent)
   - **Context Window Length**: `10`-`20`
4. Activate

### Deployment Sequence

```bash
# 1. Backup
./scripts/backup.sh

# 2. Stop
docker compose down

# 3. Apply docker-compose.yml + .env changes

# 4. Start
docker compose up -d

# 5. Verify
docker exec redis redis-cli -a "$REDIS_PASSWORD" CONFIG GET maxmemory
docker exec redis redis-cli -a "$REDIS_PASSWORD" CONFIG GET maxmemory-policy
docker compose ps
./scripts/health-check.sh
```

---

## 6. Risk Assessment and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Redis OOM with noeviction | Low | Medium — writes fail | Monitor at 80%. Increase maxmemory or add session TTL. |
| Connection churn ([known](https://github.com/redis/redis/issues/14591)) | Medium | Low | Monitor connection count. |
| Context Window bug ([#12193](https://github.com/n8n-io/n8n/issues/12193)) | Confirmed | Low — more tokens used | Use Session TTL to bound data. Monitor LLM costs. |
| Message shape mismatch ([#11730](https://github.com/n8n-io/n8n/issues/11730)) | Confirmed | Low | Build new workflows with Redis Chat Memory directly. |
| Password breaks services | Certain | High if missed | Apply to ALL 4 env blocks + healthcheck simultaneously. |

### Memory Budget Impact

| Service | Limit (Before) | Limit (After) | Delta |
|---|---|---|---|
| Redis | 1.5 GB | 2 GB | +512 MB |
| **Total allocated** | ~22 GB | ~22.5 GB | +512 MB |
| **OS headroom** | ~10 GB | ~9.5 GB | Acceptable |

---

## 7. Recommendations and Roadmap

### Implementation Roadmap

| Phase | Time | Actions |
|---|---|---|
| **Phase 1 — Infrastructure** | ~15 min | Update `docker-compose.yml` (4 changes), `.env`, `.env.sample`. Deploy with backup → down → up. |
| **Phase 2 — n8n Config** | ~5 min | Create Redis credential in n8n UI. Test connection. |
| **Phase 3 — Workflows** | Per workflow | Add Redis Chat Memory to AI Agent workflows. Configure dynamic Session IDs. |

### Technology Stack Recommendations

- **Chat memory**: Redis Chat Memory (fastest, already in stack)
- **Long-term audit**: Postgres Chat Memory (already available)
- **RAG/embeddings**: Qdrant (already running)
- **Avoid**: Simple Memory (Window Buffer) in production — broken in queue mode

### Success Metrics

| Metric | Target | How to Measure |
|---|---|---|
| Redis memory utilization | < 80% of maxmemory | `redis-cli INFO memory` |
| Chat memory persistence | Sessions survive restarts | Restart Redis, verify data |
| Cross-worker access | Same session readable from any worker | Trigger from different workers |
| Response latency | No measurable increase | Compare execution times |

---

## 8. Source Documentation

### Primary Sources

- [n8n Redis Chat Memory Node Documentation](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.memoryredischat/)
- [n8n Simple Memory Node Documentation](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.memorybufferwindow/)
- [n8n Redis Credentials Documentation](https://docs.n8n.io/integrations/builtin/credentials/redis/)
- [n8n Queue Mode Configuration](https://docs.n8n.io/hosting/scaling/queue-mode/)
- [n8n Queue Mode Environment Variables](https://docs.n8n.io/hosting/configuration/environment-variables/queue-mode/)
- [Redis Key Eviction Documentation](https://redis.io/docs/latest/develop/reference/eviction/)

### Secondary Sources

- [n8n AI Agent Node Memory: Complete Setup Guide for 2026 — Towards AI](https://towardsai.net/p/machine-learning/n8n-ai-agent-node-memory-complete-setup-guide-for-2026)
- [Redis Blog — AI Agent Memory: Build Stateful AI Systems](https://redis.io/blog/ai-agent-memory-stateful-systems/)
- [Redis Blog — Top AI Agent Orchestration Platforms in 2026](https://redis.io/blog/ai-agent-orchestration-platforms/)
- [Redis Blog — n8n's Redis Vector Store Node](https://redis.io/blog/n8ns-redis-vector-store-node/)
- [LangChain RedisChatMessageHistory API Reference](https://api.python.langchain.com/en/latest/chat_message_histories/langchain_community.chat_message_histories.redis.RedisChatMessageHistory.html)
- [BullMQ Documentation](https://docs.bullmq.io/bull/patterns/redis-cluster)

### GitHub Issues Referenced

- [#11730 — Redis chat memory different shape than window buffer memory](https://github.com/n8n-io/n8n/issues/11730)
- [#12193 — Redis Chat Memory Context Window Length not working](https://github.com/n8n-io/n8n/issues/12193)
- [#14591 — AI Agent Node creates new Redis connection on every execution](https://github.com/redis/redis/issues/14591)

### Community Sources

- [n8n Community — Multi-agent systems with shared memory](https://community.n8n.io/t/can-i-create-multiagent-systems-with-shared-memory-using-n8n/81084)
- [n8n Community — Memory node customization](https://community.n8n.io/t/memory-node-customization-when-working-with-ai-agent-node/89038)

---

**Technical Research Completion Date:** 2026-02-10
**Source Verification:** All facts cited with current sources
**Confidence Level:** HIGH — based on multiple authoritative sources with cross-validation

_This technical research document serves as an authoritative reference for enabling Redis as an AI agent memory store in the n8n-deploy project._
