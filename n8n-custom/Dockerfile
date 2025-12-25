# Custom n8n image with Python 3 support
# Based on official n8n image
ARG N8N_VERSION=latest
FROM docker.n8n.io/n8nio/n8n:${N8N_VERSION}

# Switch to root to install packages
USER root

# Install Python 3 and pip
RUN apk add --no-cache \
    python3 \
    py3-pip \
    && ln -sf python3 /usr/bin/python

# Install common Python packages (optional, add what you need)
RUN pip3 install --no-cache-dir --break-system-packages \
    requests \
    pandas \
    numpy

# Switch back to node user (security best practice)
USER node

# Verify Python installation
RUN python3 --version && pip3 --version
