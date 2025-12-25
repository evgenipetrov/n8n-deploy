# Python Task Runner for n8n
# External mode - provides Python execution environment
FROM python:3.11-slim

# Install your Python packages here
RUN pip install --no-cache-dir \
    requests \
    pandas \
    numpy \
    beautifulsoup4 \
    openpyxl \
    pillow \
    lxml

# Create non-root user
RUN useradd -m -u 1000 taskrunner
USER taskrunner
WORKDIR /home/taskrunner

# Keep container running and ready to execute Python code
CMD ["python3", "-c", "import time; print('Python task runner ready'); time.sleep(infinity)"]
