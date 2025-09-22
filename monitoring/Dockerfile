# PostgreSQL HA Monitor Dockerfile
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy monitoring files
COPY pg_ha_monitor.py .
COPY config.yaml .
COPY README.md .

# Create log directory
RUN mkdir -p logs

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash monitor
RUN chown -R monitor:monitor /app
USER monitor

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python pg_ha_monitor.py health > /dev/null 2>&1 || exit 1

# Default command
CMD ["python", "pg_ha_monitor.py", "monitor"]