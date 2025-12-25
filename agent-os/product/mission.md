# Product Mission

## Pitch
n8n-deploy is a production-grade personal automation laboratory that provides a single user with enterprise-level workflow automation, AI/ML capabilities, and unlimited experimentation potential through a carefully optimized, self-hosted n8n environment.

## Users

### Primary Customer
- **Personal Lab Owner**: Individual seeking complete control over their automation infrastructure with enterprise-grade reliability and performance.

### User Persona
**Automation Enthusiast** (25-45)
- **Role:** Self-hosted infrastructure owner, automation engineer, or technology experimenter
- **Context:** Runs personal projects, home automation, data processing workflows, and AI/ML experiments on dedicated hardware (32GB RAM bare metal server)
- **Pain Points:**
  - Cloud-hosted automation platforms lack flexibility and control
  - Limited ability to experiment with AI/ML workflows due to platform restrictions
  - Vendor lock-in and usage-based pricing constraints experimentation
  - Cannot customize or extend platform with custom integrations
  - Insufficient performance for complex, data-intensive workflows
- **Goals:**
  - Run unlimited workflows without cost concerns
  - Experiment with AI/ML capabilities using local LLMs
  - Maintain complete data privacy and control
  - Scale workflows with dedicated worker resources
  - Build and test custom integrations and nodes

## The Problem

### Limited Freedom in Automation Platforms
Cloud-hosted workflow automation platforms impose restrictions on execution time, resource usage, and integration capabilities. Personal projects and experiments become constrained by pricing tiers, rate limits, and vendor-imposed boundaries. Users cannot leverage their own hardware investments or experiment with cutting-edge AI capabilities without significant recurring costs.

**Our Solution:** A self-hosted, enterprise-optimized n8n deployment that delivers unlimited workflow executions, AI/ML capabilities via local LLMs, and complete infrastructure control on personal hardware.

## Differentiators

### Enterprise Performance for Personal Use
Unlike basic Docker deployments or cloud-hosted solutions, we provide a production-tuned stack with optimized PostgreSQL settings, queue-based execution with multiple workers, intelligent memory allocation, and high-availability architecture designed specifically for 32GB server constraints.

This results in reliable, scalable automation infrastructure that rivals professional deployments while maintaining complete personal ownership.

### Integrated AI/ML Capabilities
Unlike traditional n8n deployments, we include pre-configured Ollama for local LLM inference with GPU acceleration support and Qdrant vector database for embeddings. This enables experimentation with AI-powered workflows without external API costs or data privacy concerns.

This results in unlimited AI/ML experimentation using your own hardware, from document analysis to intelligent automation decisions.

### Built for Extensibility
Unlike locked-down platforms, we provide a foundation optimized for custom node development, integration testing, and workflow experimentation. The architecture supports hot-reloading, proper debugging capabilities, and isolated testing environments.

This results in a true laboratory environment where you can build, test, and deploy custom integrations without platform limitations.

## Key Features

### Core Infrastructure
- **Queue-Based Execution:** Three dedicated worker instances handle parallel workflow execution, ensuring responsive UI while processing complex automation tasks
- **Optimized Database Performance:** PostgreSQL 16 with 32GB-tuned settings (8GB shared buffers, 24GB cache size) delivers fast workflow execution and data retrieval
- **Intelligent Memory Management:** Carefully allocated resources (22GB total) with headroom for OS and experimentation prevent resource contention

### AI & Machine Learning Features
- **Local LLM Inference:** Ollama integration with CPU and GPU profiles enables private AI-powered workflows without external API dependencies
- **Vector Database:** Qdrant provides semantic search and embedding storage for intelligent document processing and similarity matching
- **Flexible AI Architecture:** Switch between CPU and GPU acceleration based on workload requirements

### Reliability & Operations
- **Automatic HTTPS:** Caddy reverse proxy provides zero-configuration SSL certificates and secure external access
- **Data Persistence:** Execution history retention (14 days, 10k executions) with automatic pruning maintains performance while preserving debugging data
- **Health Monitoring:** Built-in health checks for all services ensure system reliability and rapid issue detection
- **Redis-Backed Queuing:** AOF persistence prevents job loss while LRU eviction handles memory pressure gracefully

### Developer Experience
- **Instant Setup:** Environment-based configuration and Docker Compose orchestration enable deployment in minutes
- **Demo Workflows:** Pre-configured credentials and sample workflows accelerate learning and experimentation
- **Isolated Networking:** Dedicated bridge network prevents conflicts with other services while maintaining clean architecture
- **Version Control Ready:** Infrastructure-as-code approach enables tracking changes and rolling back configurations
