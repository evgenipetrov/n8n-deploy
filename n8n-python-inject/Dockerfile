# Inject Python into official n8n image using multi-stage build
# This copies Python binaries from a Python image without needing package managers

# Stage 1: Get Python from official Python Alpine image
FROM python:3.11-alpine AS python-source

# Install any Python packages we want
RUN pip install --no-cache-dir \
    requests \
    pandas \
    numpy \
    beautifulsoup4 \
    openpyxl \
    pillow \
    lxml

# Stage 2: Start with official n8n image and inject Python
ARG N8N_VERSION=latest
FROM docker.n8n.io/n8nio/n8n:${N8N_VERSION}

# Switch to root to copy files
USER root

# Copy Python binaries and libraries from python-source stage
COPY --from=python-source /usr/local/bin/python3 /usr/local/bin/python3
COPY --from=python-source /usr/local/bin/pip3 /usr/local/bin/pip3
COPY --from=python-source /usr/local/lib/python3.11 /usr/local/lib/python3.11
COPY --from=python-source /usr/lib/libpython3.11.so.1.0 /usr/lib/libpython3.11.so.1.0

# Create symbolic links
RUN ln -sf python3 /usr/local/bin/python && \
    ln -sf pip3 /usr/local/bin/pip && \
    ln -sf libpython3.11.so.1.0 /usr/lib/libpython3.11.so && \
    ln -sf libpython3.11.so.1.0 /usr/lib/libpython3.so

# Switch back to node user
USER node

# Verify Python works
RUN python3 --version && pip3 --version
