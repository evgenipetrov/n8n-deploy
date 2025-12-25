# Self-built n8n with Python support
# Based on Node.js Alpine with full control over dependencies
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-alpine AS base

# Install system dependencies and Python
RUN apk add --update --no-cache \
    ca-certificates \
    git \
    curl \
    tzdata \
    su-exec \
    tini \
    # Python and build tools
    python3 \
    py3-pip \
    python3-dev \
    gcc \
    g++ \
    make \
    musl-dev \
    linux-headers \
    && ln -sf python3 /usr/bin/python

# Install n8n globally
ARG N8N_VERSION=latest
RUN if [ "$N8N_VERSION" = "latest" ]; then \
      npm install -g --omit=dev n8n; \
    else \
      npm install -g --omit=dev n8n@${N8N_VERSION}; \
    fi

# Install Python packages
RUN pip3 install --no-cache-dir --break-system-packages \
    requests \
    pandas \
    numpy \
    beautifulsoup4 \
    openpyxl \
    pillow \
    lxml

# Create n8n user and directories
RUN addgroup -g 1000 node && \
    adduser -D -u 1000 -G node node && \
    mkdir -p /home/node/.n8n && \
    chown -R node:node /home/node

# Set working directory
WORKDIR /home/node

# Switch to node user
USER node

# Expose n8n port
EXPOSE 5678

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:5678/healthz || exit 1

# Use tini as init system
ENTRYPOINT ["tini", "--"]

# Start n8n
CMD ["n8n"]
