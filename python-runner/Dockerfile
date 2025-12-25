# Python Task Runner for n8n
# External mode (recommended for production)
FROM python:3.11-slim

# Install n8n task runner package
RUN pip install --no-cache-dir n8n-task-runner

# Install your Python packages here
RUN pip install --no-cache-dir \
    requests \
    pandas \
    numpy \
    beautifulsoup4 \
    openpyxl

# Create non-root user
RUN useradd -m -u 1000 taskrunner
USER taskrunner

# Expose default port for task runner
EXPOSE 5679

# Start the Python task runner
CMD ["n8n-task-runner"]
