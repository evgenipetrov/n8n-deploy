# Extend n8n task runner with custom Python packages
ARG N8N_VERSION=latest
FROM n8nio/runners:${N8N_VERSION}

# Install Python packages (already running as appropriate user in base image)
RUN pip install --no-cache-dir \
    pandas \
    numpy \
    requests \
    beautifulsoup4 \
    openpyxl \
    pillow \
    lxml
