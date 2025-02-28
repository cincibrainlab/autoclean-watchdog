FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Install system dependencies including Docker and Docker Compose
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    docker.io \
    curl \
    gnupg \
    lsb-release \
    dos2unix \
    && rm -rf /var/lib/apt/lists/*

# Install Docker Compose v2
RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -SL https://github.com/docker/compose/releases/download/v2.24.1/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose && \
    ln -s /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

# Verify Docker Compose installation
RUN docker-compose --version

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY eeg_watchdog.py .
COPY autoclean_wrapper.sh .
COPY review_wrapper.sh .

# Create entrypoint script
RUN echo '#!/bin/bash\n\
# Export environment variables for review_wrapper.sh\n\
export OUTPUT_PATH=${OUTPUT_DIR:-/data/output}\n\
export BOT_NAME=${BOT_NAME:-default}\n\
\n\
# Run review_wrapper.sh in the background\n\
bash /app/review_wrapper.sh &\n\
\n\
# Run the main application with passed arguments\n\
exec python eeg_watchdog.py "$@"\n\
' > /app/entrypoint.sh

RUN dos2unix autoclean_wrapper.sh
RUN dos2unix review_wrapper.sh
RUN dos2unix /app/entrypoint.sh

# Make the scripts executable
RUN chmod +x autoclean_wrapper.sh
RUN chmod +x review_wrapper.sh
RUN chmod +x /app/entrypoint.sh

# Create directories
RUN mkdir -p /data/input /data/output /config /autoclean_pipeline

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Use the new entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]

# Default arguments (can be overridden at runtime)
CMD ["--dir", "/data/input", "--extensions", "edf", "set", "vhdr", "bdf", "--script", "/app/autoclean_wrapper.sh", "--task", "RestingEyesOpen", "--config", "/config/autoclean_config.yaml", "--output", "/data/output", "--max-workers", "3"]