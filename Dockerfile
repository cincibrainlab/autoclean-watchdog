FROM python:3.9-slim

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
COPY autoclean_wrapper_test.sh .

RUN dos2unix autoclean_wrapper.sh
RUN dos2unix autoclean_wrapper_test.sh

# Make the scripts executable
RUN chmod +x autoclean_wrapper.sh
RUN chmod +x autoclean_wrapper_test.sh

# Create directories
RUN mkdir -p /data/input /data/output /config /autoclean_pipeline

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Command to run the application
ENTRYPOINT ["python", "eeg_watchdog.py"]

# Default arguments (can be overridden at runtime)
CMD ["--dir", "/data/input", "--extensions", "edf", "set", "vhdr", "bdf", "--script", "/app/autoclean_wrapper.sh", "--task", "RestingEyesOpen", "--config", "/config/autoclean_config.yaml", "--output", "/data/output", "--max-workers", "3"]