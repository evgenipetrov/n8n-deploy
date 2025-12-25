# Tech Stack

## Container Orchestration & Runtime
- **Container Engine:** Docker (latest stable version)
- **Orchestration:** Docker Compose v2
- **Network Driver:** Bridge networking with custom subnet (172.19.0.0/16)
- **Volume Management:** Docker named volumes for persistent data

## Core Application
- **Workflow Engine:** n8n (docker.n8n.io/n8nio/n8n:latest)
- **Execution Mode:** Queue-based with worker separation
- **Architecture Pattern:** Main instance (UI/API) + 3 worker replicas

## Database & Storage
- **Primary Database:** PostgreSQL 16
- **Database Tuning:** Optimized for 32GB RAM server
  - Shared buffers: 8GB (25% of total RAM)
  - Effective cache size: 24GB (75% of total RAM)
  - Work memory: 256MB per operation
  - Maintenance work memory: 1GB
- **Connection Pooling:** 10 connections per n8n instance
- **Query Optimizer:** SSD-optimized (random_page_cost: 1.1)

## Queue & Caching
- **Queue Backend:** Redis 7
- **Persistence:** AOF (Append-Only File) with fsync every second
- **Memory Policy:** allkeys-lru with 1GB limit
- **Queue Library:** Bull (via n8n's built-in integration)

## Reverse Proxy & SSL
- **Reverse Proxy:** Caddy (latest)
- **SSL/TLS:** Automatic HTTPS with Let's Encrypt
- **Certificate Management:** Automated renewal and storage
- **Protocol:** HTTP/2 and HTTP/3 support

## AI & Machine Learning
- **LLM Inference:** Ollama (latest)
- **GPU Support:**
  - NVIDIA: CUDA-enabled via nvidia-docker runtime
  - AMD: ROCm-enabled via rocm image variant
- **Default Model:** Llama 3.2 (auto-downloaded on first start)
- **Vector Database:** Qdrant (latest)
- **Vector Storage:** Persistent volume for embeddings and collections

## DNS & Networking
- **DNS Resolvers:**
  - Primary: Google DNS (8.8.8.8, 8.8.4.4)
  - Fallback: Cloudflare DNS (1.1.1.1)
- **Network Isolation:** Dedicated bridge network (br-web)
- **Service Discovery:** Docker internal DNS

## Resource Management
- **Memory Limits:**
  - PostgreSQL: 12GB limit, 10GB reservation
  - Redis: 1.5GB limit, 1GB reservation
  - n8n Main: 4GB limit, 2GB reservation
  - n8n Workers: 2GB limit, 1GB reservation (per worker)
  - Caddy: No hard limit (~512MB typical)
  - Qdrant: No hard limit (~2GB typical)
  - Ollama: No hard limit (varies by model, 2-8GB)
- **Total Allocation:** ~22GB of 32GB available (10GB headroom)

## Data Persistence Strategy
- **Execution History:** 14-day retention, 10,000 execution limit
- **Pruning Strategy:** Soft delete every 60 minutes, hard delete every 15 minutes
- **Binary Data:** Filesystem storage (not in database)
- **Backup Volumes:**
  - n8n_data: Workflows, credentials, configurations
  - postgres_data: Database files
  - redis_data: Queue persistence
  - caddy_data: SSL certificates
  - ollama_storage: LLM models
  - qdrant_storage: Vector embeddings

## Configuration Management
- **Environment Variables:** .env file for all configuration
- **Secrets Management:** Environment-based (not committed to git)
- **Configuration Files:**
  - Caddyfile: Reverse proxy routing
  - docker-compose.yml: Service orchestration
  - PostgreSQL init scripts: Schema optimization

## Health Monitoring
- **PostgreSQL:** pg_isready check every 5 seconds
- **Redis:** redis-cli ping every 5 seconds
- **n8n Main:** HTTP healthz endpoint every 5 seconds
- **Queue Workers:** Built-in Bull health checks
- **Retry Strategy:** 10 retries with 5-second timeout

## Development Tools
- **Version Control:** Git
- **Environment Templates:** .env.sample for configuration scaffolding
- **Demo Data:** Sample workflows and credentials in n8n/demo-data
- **Override Support:** docker-compose.override.yml for local customization

## Platform Requirements
- **Target Server:** Bare metal server with 32GB RAM
- **OS Compatibility:** Linux (tested), macOS (compatible), Windows (WSL2 compatible)
- **Minimum Disk:** 100GB SSD recommended for database and model storage
- **Network Requirements:** Public domain with DNS access for automatic HTTPS

## Deployment Profiles
- **CPU-only:** Default profile for LLM inference without GPU
- **GPU-NVIDIA:** NVIDIA GPU acceleration profile
- **GPU-AMD:** AMD GPU acceleration profile (ROCm)
