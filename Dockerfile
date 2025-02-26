FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    docker.io \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY eeg_watchdog.py .
COPY autoclean_wrapper.sh .

# Make the scripts executable
RUN chmod +x autoclean_wrapper.sh

# Create directories
RUN mkdir -p /data/input /data/output /config

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Command to run the application
ENTRYPOINT ["python", "eeg_watchdog.py"]

# Default arguments (can be overridden at runtime)
CMD ["--dir", "/data/input", "--extensions", "edf", "set", "vhdr", "bdf", "--script", "/app/autoclean_wrapper.sh", "--task", "RestingEyesOpen", "--config", "/config/autoclean_config.yaml", "--output", "/data/output"]
