# Security Audit and Recommendations

This document outlines security findings and recommendations for the n8n deployment.

## 🔴 Critical Security Recommendations

### 1. Environment Variables and Secrets Management

**Current State:**
- Secrets stored in `.env` file
- Passwords visible via `docker inspect`
- No encryption at rest for environment files

**Recommendations:**
- **High Priority**: Use Docker secrets for production deployments
- Encrypt `.env` file at rest (e.g., using `ansible-vault`, `git-crypt`, or `sops`)
- Consider using external secrets management (HashiCorp Vault, AWS Secrets Manager)
- Rotate encryption keys and passwords regularly

**Implementation Example:**
```bash
# Using Docker Swarm secrets (requires swarm mode)
echo "your-db-password" | docker secret create postgres_password -
```

### 2. Container User Permissions

**Current State:**
- All containers run as root by default
- No `user:` directives specified

**Recommendations:**
- Run containers as non-root users where possible
- Add user directives to services:

```yaml
services:
  n8n:
    user: "1000:1000"  # Use appropriate UID:GID
```

**Exceptions:**
- PostgreSQL, Redis require specific users (handled by images)
- Caddy needs privileges for ports 80/443 (use capabilities)

### 3. Network Isolation

**Current State:**
- Single `web` network for all services
- All services can communicate with each other

**Recommendations:**
- Implement network segmentation:
  - **Frontend network**: Caddy ↔ n8n
  - **Backend network**: n8n ↔ PostgreSQL, Redis
  - **AI network**: n8n ↔ Ollama, Qdrant

```yaml
networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true  # No internet access
  ai:
    driver: bridge
    internal: true
```

### 4. Read-Only Filesystems

**Current State:**
- Containers have full filesystem write access

**Recommendations:**
- Enable read-only root filesystems where possible:

```yaml
services:
  caddy:
    read_only: true
    tmpfs:
      - /tmp
      - /var/run
```

**Services that can be read-only:**
- Caddy (with tmpfs for certs)
- n8n workers (with tmpfs for temp)

## ⚠️ High Priority Improvements

### 5. Resource Limits

**Current State:**
- Missing memory limits: Caddy, Qdrant, Ollama

**Recommendations:**
```yaml
services:
  caddy:
    deploy:
      resources:
        limits:
          memory: 512m
        reservations:
          memory: 256m

  qdrant:
    deploy:
      resources:
        limits:
          memory: 2g
        reservations:
          memory: 1g

  ollama-cpu:
    deploy:
      resources:
        limits:
          memory: 8g
        reservations:
          memory: 4g
```

### 6. Health Checks

**Current State:**
- Missing health checks: Caddy, Qdrant, Ollama

**Recommendations:**
```yaml
services:
  caddy:
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:2019/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  qdrant:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  ollama-cpu:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### 7. Service Restart Policies

**Current State:**
- `n8n-import` has default restart policy (should run once)

**Recommendations:**
```yaml
services:
  n8n-import:
    restart: "no"  # One-time import only
```

### 8. Logging Configuration

**Current State:**
- Default `json-file` logging driver (can fill disk)

**Recommendations:**
```yaml
services:
  n8n:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

Apply to all services to prevent disk exhaustion.

## 📋 Medium Priority Improvements

### 9. PostgreSQL Security Hardening

**Recommendations:**
- Enable SSL/TLS for database connections
- Use SSL certificates for PostgreSQL
- Restrict PostgreSQL to local network only
- Enable `pg_stat_statements` for query monitoring

### 10. Redis Security

**Recommendations:**
- Enable Redis authentication (requirepass)
- Disable dangerous commands:

```yaml
services:
  redis:
    command:
      - "redis-server"
      - "--requirepass"
      - "${REDIS_PASSWORD}"
      - "--rename-command"
      - "FLUSHDB"
      - ""
      - "--rename-command"
      - "FLUSHALL"
      - ""
```

### 11. Caddy Security Headers

**Current State:**
- Basic reverse proxy configuration

**Recommendations:**
Add security headers in `caddy/Caddyfile`:

```
{$SUBDOMAIN}.{$DOMAIN_NAME} {
    reverse_proxy n8n:5678 {
        flush_interval -1
    }

    header {
        # Security headers
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"

        # Remove server information
        -Server
    }

    # Rate limiting
    rate_limit {
        zone dynamic {
            key {remote_host}
            events 100
            window 1m
        }
    }
}
```

### 12. Volume Permissions

**Recommendations:**
- Set explicit permissions on volume directories
- Use named volumes with proper access controls
- Backup volumes regularly

## 🔒 Security Best Practices

### Regular Maintenance

1. **Update Images Regularly**
   ```bash
   docker compose pull
   docker compose up -d --remove-orphans
   ```

2. **Monitor Security Advisories**
   - Subscribe to n8n security announcements
   - Monitor PostgreSQL CVEs
   - Track Redis security updates

3. **Audit Container Logs**
   ```bash
   docker compose logs --tail=100 -f
   ```

4. **Scan for Vulnerabilities**
   ```bash
   docker scout cves n8n
   docker scout cves postgres:16
   ```

### Access Control

1. **Enable n8n Authentication**
   - Configure strong user passwords
   - Enable 2FA if available
   - Limit user permissions

2. **Firewall Rules**
   - Restrict ports 80/443 to trusted sources
   - Block direct access to PostgreSQL (5432), Redis (6379)
   - Use VPN or bastion host for administrative access

3. **SSH Hardening** (for host server)
   - Disable password authentication
   - Use SSH keys only
   - Enable fail2ban
   - Update SSH to latest version

## 🎯 Quick Wins (Implement First)

Priority order for implementation:

1. ✅ Add `.gitignore` to protect secrets
2. 🔧 Add resource limits to Caddy, Qdrant, Ollama
3. 🔧 Add health checks to all services
4. 🔧 Configure logging rotation
5. 🔧 Set `restart: "no"` on n8n-import
6. 🔧 Add security headers to Caddy
7. 🔐 Implement Docker secrets for production
8. 🔐 Enable Redis authentication
9. 🔐 Network segmentation
10. 🔐 Run containers as non-root

## Compliance Considerations

If deploying in regulated environments:

- **GDPR**: Ensure data encryption at rest and in transit
- **HIPAA**: Enable audit logging, encryption, access controls
- **SOC 2**: Implement monitoring, backups, disaster recovery
- **PCI-DSS**: Network segmentation, encryption, regular audits
