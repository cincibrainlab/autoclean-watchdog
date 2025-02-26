#!/bin/bash
# setup-eeg-watchdog.sh - Creates the complete EEG Watchdog repository structure
# 
# Usage: chmod +x setup-eeg-watchdog.sh && ./setup-eeg-watchdog.sh [destination_directory]
#
# This script creates all files needed for the EEG Watchdog repository in one go.
# It includes the main Python watchdog script, Docker files, client scripts, 
# documentation, and sample configuration.

set -e # Exit on any error

# Set destination directory (default to current directory if not specified)
DEST_DIR="${1:-.}"

# Create destination directory if it doesn't exist
mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

echo "🔧 Creating EEG Watchdog repository in $(pwd)..."

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p input output config scripts docs/images

# Create placeholder file in input directory (for demonstration only)
echo "# This is a placeholder file to demonstrate where to place EEG data files." > input/README.txt
echo "# Place your EEG data files (.edf, .set, .vhdr, etc.) in this directory." >> input/README.txt
echo "# The watchdog will automatically process them based on your configuration." >> input/README.txt

# Create eeg_watchdog.py
echo "📝 Creating eeg_watchdog.py..."
cat > eeg_watchdog.py << 'EOL'
"""
EEG Data Watchdog Monitor

This script monitors a directory for new EEG data files and processes them using the
autoclean pipeline with the specified parameters. It handles multiple files concurrently
with a configurable maximum number of simultaneous processes.
"""

import os
import sys
import time
import argparse
import subprocess
import logging
import shutil
import threading
import queue
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Global file processing queue
file_queue = queue.Queue()

class EEGFileHandler(FileSystemEventHandler):
    def __init__(self, extensions, script_path, task, config_path, output_dir):
        """
        Initialize the EEG file handler.
        
        Args:
            extensions (list): List of file extensions to monitor (EEG data file types)
            script_path (str): Path to the autoclean script
            task (str): EEG processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)
            config_path (str): Path to configuration YAML file
            output_dir (str): Output directory for processed files
        """
        self.extensions = [ext.lower() if ext.startswith('.') else f'.{ext.lower()}' for ext in extensions]
        self.script_path = script_path
        self.task = task
        self.config_path = config_path
        self.output_dir = output_dir
        
        # Ensure the output directory exists
        if not os.path.exists(self.output_dir):
            os.makedirs(self.output_dir)
            logger.info(f"Created output directory: {self.output_dir}")
    
    def on_created(self, event):
        """Handle file creation events."""
        if not event.is_directory:
            file_path = event.src_path
            file_ext = os.path.splitext(file_path)[1].lower()
            
            if file_ext in self.extensions:
                logger.info(f"New EEG data file detected: {file_path}")
                
                # Add the file to the processing queue with its processing parameters
                file_queue.put({
                    'file_path': file_path,
                    'script_path': self.script_path,
                    'task': self.task,
                    'config_path': self.config_path,
                    'output_dir': self.output_dir
                })


def process_file(params):
    """
    Process an EEG data file using the autoclean script.
    
    Args:
        params (dict): Dictionary containing processing parameters
    
    Returns:
        bool: True if processing was successful, False otherwise
    """
    file_path = params['file_path']
    script_path = params['script_path']
    task = params['task']
    config_path = params['config_path']
    output_dir = params['output_dir']
    
    try:
        # Make sure the script is executable
        if not os.access(script_path, os.X_OK):
            subprocess.run(['chmod', '+x', script_path], check=True)
            logger.info(f"Made autoclean script executable: {script_path}")
        
        # Run the autoclean script with the appropriate parameters
        command = [
            script_path,
            "-DataPath", file_path,
            "-Task", task,
            "-ConfigPath", config_path,
            "-OutputPath", output_dir
        ]
        
        logger.info(f"Processing file: {file_path}")
        logger.info(f"Command: {' '.join(command)}")
        
        result = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        logger.info(f"EEG data processing completed successfully for: {file_path}")
        logger.debug(f"Script output: {result.stdout}")
        return True
        
    except subprocess.CalledProcessError as e:
        logger.error(f"Error processing file {file_path}: {e}")
        logger.error(f"Script stderr: {e.stderr}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error processing file {file_path}: {str(e)}")
        return False


def worker_thread(max_workers):
    """
    Worker thread that manages the ThreadPoolExecutor for processing files.
    
    Args:
        max_workers (int): Maximum number of concurrent processing tasks
    """
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        while True:
            try:
                # Get file processing parameters from the queue
                params = file_queue.get(block=True, timeout=1)
                
                # Submit the processing task to the thread pool
                executor.submit(process_file, params)
                
                # Mark the task as done
                file_queue.task_done()
                
            except queue.Empty:
                # Queue is empty, continue waiting
                continue
            except Exception as e:
                logger.error(f"Error in worker thread: {str(e)}")
                # Mark the task as done even if there was an error
                file_queue.task_done()


def main():
    """Main entry point of the script."""
    parser = argparse.ArgumentParser(description='Monitor a directory for new EEG data files and process them with autoclean')
    parser.add_argument('--dir', '-d', required=True, help='Directory to monitor for new EEG data files')
    parser.add_argument('--extensions', '-e', required=True, nargs='+', help='EEG data file extensions to monitor (e.g., edf set vhdr)')
    parser.add_argument('--script', '-s', required=True, help='Path to the autoclean script')
    parser.add_argument('--task', '-t', required=True, help='EEG processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)')
    parser.add_argument('--config', '-c', required=True, help='Path to configuration YAML file')
    parser.add_argument('--output', '-o', required=True, help='Output directory for processed files')
    parser.add_argument('--max-workers', '-w', type=int, default=3, help='Maximum number of concurrent processing tasks (default: 3)')
    
    args = parser.parse_args()
    
    # Ensure the input directory exists
    if not os.path.exists(args.dir):
        logger.error(f"Input directory does not exist: {args.dir}")
        sys.exit(1)
    
    # Ensure the script exists
    if not os.path.exists(args.script):
        logger.error(f"Autoclean script does not exist: {args.script}")
        sys.exit(1)
    
    # Ensure the config file exists
    if not os.path.exists(args.config):
        logger.error(f"Configuration file does not exist: {args.config}")
        sys.exit(1)
    
    logger.info(f"Starting EEG data file monitoring in {args.dir}")
    logger.info(f"Watching for files with extensions: {', '.join(args.extensions)}")
    logger.info(f"Using autoclean script: {args.script}")
    logger.info(f"Task: {args.task}")
    logger.info(f"Config: {args.config}")
    logger.info(f"Output directory: {args.output}")
    logger.info(f"Maximum concurrent processes: {args.max_workers}")
    
    # Start the worker thread for processing files
    worker = threading.Thread(target=worker_thread, args=(args.max_workers,), daemon=True)
    worker.start()
    
    # Initialize the event handler and observer
    event_handler = EEGFileHandler(args.extensions, args.script, args.task, args.config, args.output)
    observer = Observer()
    observer.schedule(event_handler, args.dir, recursive=True)
    observer.start()
    
    try:
        # Process existing files in the monitored directory
        for file in os.listdir(args.dir):
            file_path = os.path.join(args.dir, file)
            if os.path.isfile(file_path):
                file_ext = os.path.splitext(file_path)[1].lower()
                if file_ext in event_handler.extensions:
                    logger.info(f"Found existing EEG data file: {file_path}")
                    file_queue.put({
                        'file_path': file_path,
                        'script_path': args.script,
                        'task': args.task,
                        'config_path': args.config,
                        'output_dir': args.output
                    })
        
        # Keep the main thread alive
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        logger.info("Stopping EEG data file monitoring")
        observer.stop()
        
        # Wait for the file queue to be processed
        logger.info("Waiting for remaining files to be processed...")
        file_queue.join()
        logger.info("All processing complete, exiting.")
        
    observer.join()


if __name__ == "__main__":
    main()
EOL

# Create autoclean_wrapper.sh
echo "📝 Creating autoclean_wrapper.sh..."
cat > autoclean_wrapper.sh << 'EOL'
#!/bin/bash
#
# autoclean_wrapper.sh - Wrapper script for autoclean EEG data processing
#
# Usage: ./autoclean_wrapper.sh -DataPath <file_path> -Task <task_type> -ConfigPath <config_path> -OutputPath <output_dir>

# Function to display usage information
usage() {
    echo "Usage: $0 -DataPath <path> -Task <task_type> -ConfigPath <config_path> [-OutputPath <output_dir>]"
    echo ""
    echo "Parameters:"
    echo "  -DataPath    Directory containing raw EEG data or path to single data file"
    echo "  -Task        Processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)"
    echo "  -ConfigPath  Path to configuration YAML file"
    echo "  -OutputPath  (Optional) Output directory, defaults to './output'"
    echo "  -Help        Display this help message"
    exit 1
}

# Default output path
OUTPUT_PATH="./output"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -DataPath)
            DATA_PATH="$2"
            shift 2
            ;;
        -Task)
            TASK="$2"
            shift 2
            ;;
        -ConfigPath)
            CONFIG_PATH="$2"
            shift 2
            ;;
        -OutputPath)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        -Help|--help)
            usage
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            ;;
    esac
done

# Check if all required parameters are provided
if [ -z "$DATA_PATH" ] || [ -z "$TASK" ] || [ -z "$CONFIG_PATH" ]; then
    echo "Error: Missing required parameters."
    usage
fi

# Ensure the data path exists
if [ ! -e "$DATA_PATH" ]; then
    echo "Error: Data path does not exist: $DATA_PATH"
    exit 1
fi

# Ensure the config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Configuration file does not exist: $CONFIG_PATH"
    exit 1
fi

# Ensure the output directory exists
mkdir -p "$OUTPUT_PATH"

# Get filename without extension and path
FILE_BASE=$(basename "$DATA_PATH")
FILE_NAME="${FILE_BASE%.*}"

# Get current timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create a unique output subdirectory for this processing job
JOB_DIR="${OUTPUT_PATH}/${TIMESTAMP}_${FILE_NAME}_${TASK}"
mkdir -p "$JOB_DIR"

# Create a lockfile name for this specific file
LOCK_FILE="/tmp/autoclean_$(echo "${DATA_PATH}" | md5sum | cut -d' ' -f1).lock"

# Create a log file
LOG_FILE="${JOB_DIR}/process.log"

# Log function
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Try to acquire a lock for this file
if [ -e "$LOCK_FILE" ]; then
    log "Another process is already processing $DATA_PATH (lock file exists: $LOCK_FILE)"
    exit 1
fi

# Create the lock file
touch "$LOCK_FILE"

# Ensure the lock file is removed when the script exits
trap 'rm -f "$LOCK_FILE"; log "Processing ended (lock released)."' EXIT

# Log the execution
log "Processing EEG data: $DATA_PATH"
log "Task: $TASK"
log "Config: $CONFIG_PATH"
log "Output directory: $JOB_DIR"
log "Lock file: $LOCK_FILE"

# Execute autoclean within Docker with a unique container name
CONTAINER_NAME="autoclean_$(echo "${DATA_PATH}" | md5sum | cut -d' ' -f1)"

log "Starting Docker container: $CONTAINER_NAME"
docker run \
    --rm \
    --name "$CONTAINER_NAME" \
    -v "$(dirname "$DATA_PATH"):/data" \
    -v "$(dirname "$CONFIG_PATH"):/config" \
    -v "$JOB_DIR:/output" \
    autoclean-image \
    -DataPath "/data/$(basename "$DATA_PATH")" \
    -Task "$TASK" \
    -ConfigPath "/config/$(basename "$CONFIG_PATH")" \
    -OutputPath "/output" >> "$LOG_FILE" 2>&1

# Check the exit status
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    log "Processing completed successfully"
    
    # Copy the results to the main output directory
    cp -r "$JOB_DIR"/* "$OUTPUT_PATH"/ >> "$LOG_FILE" 2>&1
    log "Results copied to main output directory: $OUTPUT_PATH"
else
    log "Error during processing (exit code: $EXIT_CODE)"
    exit 1
fi

exit 0
EOL

# Make script executable
chmod +x autoclean_wrapper.sh

# Create Dockerfile
echo "📝 Creating Dockerfile..."
cat > Dockerfile << 'EOL'
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
EOL

# Create docker-compose.yml
echo "📝 Creating docker-compose.yml..."
cat > docker-compose.yml << 'EOL'
version: '3.8'

services:
  eeg-watchdog:
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - ./input:/data/input
      - ./output:/data/output
      - ./config:/config
      - /var/run/docker.sock:/var/run/docker.sock  # Allow Docker-in-Docker
    environment:
      - TZ=UTC
    command: 
      - "--dir"
      - "/data/input"
      - "--extensions"
      - "edf"
      - "set"
      - "vhdr"
      - "bdf"
      - "cnt"
      - "--script"
      - "/app/autoclean_wrapper.sh"
      - "--task"
      - "RestingEyesOpen"
      - "--config"
      - "/config/autoclean_config.yaml"
      - "--output"
      - "/data/output"
      - "--max-workers"
      - "3"  # Set the maximum number of concurrent processes
    restart: unless-stopped
    privileged: true  # Required for Docker-in-Docker functionality
EOL

# Create requirements.txt
echo "📝 Creating requirements.txt..."
cat > requirements.txt << 'EOL'
watchdog==2.3.1
pyyaml==6.0
EOL

# Create PowerShell script
echo "📝 Creating PowerShell script..."
mkdir -p scripts
cat > scripts/autoclean.ps1 << 'EOL'
# autoclean.ps1 - PowerShell function for running the autoclean EEG processing pipeline

function autoclean {
    param(
        [Parameter()]
        [string]$DataPath,
        
        [Parameter()]
        [string]$Task,
        
        [Parameter()]
        [string]$ConfigPath,
        
        [Parameter()]
        [string]$OutputPath = "./output",
        
        [Parameter()]
        [switch]$Help
    )
    
    # Show help if requested or if no parameters are provided
    if ($Help -or (!$DataPath -and !$Task -and !$ConfigPath)) {
        Write-Host "EEG Data Autoclean Pipeline"
        Write-Host ""
        Write-Host "USAGE:"
        Write-Host "  autoclean -DataPath <path> -Task <task_type> -ConfigPath <config_path> [-OutputPath <output_dir>]"
        Write-Host ""
        Write-Host "PARAMETERS:"
        Write-Host "  -DataPath    Directory containing raw EEG data or path to single data file"
        Write-Host "  -Task        Processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)"
        Write-Host "  -ConfigPath  Path to configuration YAML file"
        Write-Host "  -OutputPath  (Optional) Output directory, defaults to './output'"
        Write-Host "  -Help        Display this help message"
        return
    }
    
    # Validate parameters
    if (-not $DataPath) {
        Write-Host "Error: DataPath parameter is required." -ForegroundColor Red
        return
    }
    
    if (-not $Task) {
        Write-Host "Error: Task parameter is required." -ForegroundColor Red
        return
    }
    
    if (-not $ConfigPath) {
        Write-Host "Error: ConfigPath parameter is required." -ForegroundColor Red
        return
    }
    
    # Check if paths exist
    if (-not (Test-Path $DataPath)) {
        Write-Host "Error: Data path does not exist: $DataPath" -ForegroundColor Red
        return
    }
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Error: Configuration file does not exist: $ConfigPath" -ForegroundColor Red
        return
    }
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
        Write-Host "Created output directory: $OutputPath"
    }
    
    # Convert Windows paths to Docker-compatible paths
    $dataPathAbs = (Resolve-Path $DataPath).Path
    $configPathAbs = (Resolve-Path $ConfigPath).Path
    $outputPathAbs = (Resolve-Path $OutputPath).Path
    
    $dataDir = Split-Path -Parent $dataPathAbs
    $dataFile = Split-Path -Leaf $dataPathAbs
    $configDir = Split-Path -Parent $configPathAbs
    $configFile = Split-Path -Leaf $configPathAbs
    
    # Replace Windows backslashes with forward slashes for Docker
    $dataDirDocker = $dataDir.Replace('\', '/').Replace(':', '')
    $configDirDocker = $configDir.Replace('\', '/').Replace(':', '')
    $outputPathDocker = $outputPathAbs.Replace('\', '/').Replace(':', '')
    
    # Run the Docker command
    Write-Host "Processing EEG data: $dataPathAbs"
    Write-Host "Task: $Task"
    Write-Host "Config: $configPathAbs"
    Write-Host "Output directory: $outputPathAbs"
    
    try {
        # Check if Docker is running
        $dockerStatus = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Docker is not running. Please start Docker Desktop and try again." -ForegroundColor Red
            return
        }
        
        # Run the Docker command
        docker run --rm `
            -v "${dataDirDocker}:/data" `
            -v "${configDirDocker}:/config" `
            -v "${outputPathDocker}:/output" `
            autoclean-image `
            -DataPath "/data/$dataFile" `
            -Task $Task `
            -ConfigPath "/config/$configFile" `
            -OutputPath "/output"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Processing completed successfully" -ForegroundColor Green
        } else {
            Write-Host "Error during processing" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

# Export the function to make it available in the PowerShell session
Export-ModuleMember -Function autoclean
EOL

# Create Bash script
echo "📝 Creating Bash script..."
cat > scripts/autoclean.sh << 'EOL'
#!/bin/bash
#
# autoclean - Bash script for running the autoclean EEG processing pipeline
#

# Function to display usage information
show_help() {
    echo "EEG Data Autoclean Pipeline"
    echo ""
    echo "USAGE:"
    echo "  autoclean -DataPath <path> -Task <task_type> -ConfigPath <config_path> [-OutputPath <output_dir>]"
    echo ""
    echo "PARAMETERS:"
    echo "  -DataPath    Directory containing raw EEG data or path to single data file"
    echo "  -Task        Processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)"
    echo "  -ConfigPath  Path to configuration YAML file"
    echo "  -OutputPath  (Optional) Output directory, defaults to './output'"
    echo "  -Help        Display this help message"
}

# Default output path
OUTPUT_PATH="./output"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -DataPath)
            DATA_PATH="$2"
            shift 2
            ;;
        -Task)
            TASK="$2"
            shift 2
            ;;
        -ConfigPath)
            CONFIG_PATH="$2"
            shift 2
            ;;
        -OutputPath)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        -Help|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Show help if no parameters are provided
if [ -z "$DATA_PATH" ] && [ -z "$TASK" ] && [ -z "$CONFIG_PATH" ]; then
    show_help
    exit 0
fi

# Check if all required parameters are provided
if [ -z "$DATA_PATH" ] || [ -z "$TASK" ] || [ -z "$CONFIG_PATH" ]; then
    echo "Error: Missing required parameters."
    show_help
    exit 1
fi

# Ensure the data path exists
if [ ! -e "$DATA_PATH" ]; then
    echo "Error: Data path does not exist: $DATA_PATH"
    exit 1
fi

# Ensure the config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Configuration file does not exist: $CONFIG_PATH"
    exit 1
fi

# Ensure the output directory exists
mkdir -p "$OUTPUT_PATH"

# Convert paths to absolute paths
DATA_PATH=$(realpath "$DATA_PATH")
CONFIG_PATH=$(realpath "$CONFIG_PATH")
OUTPUT_PATH=$(realpath "$OUTPUT_PATH")

# Extract directory and filename for mounting in Docker
DATA_DIR=$(dirname "$DATA_PATH")
DATA_FILE=$(basename "$DATA_PATH")
CONFIG_DIR=$(dirname "$CONFIG_PATH")
CONFIG_FILE=$(basename "$CONFIG_PATH")

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker and try again."
    exit 1
fi

# Run the Docker command
echo "Processing EEG data: $DATA_PATH"
echo "Task: $TASK"
echo "Config: $CONFIG_PATH"
echo "Output directory: $OUTPUT_PATH"

docker run --rm \
    -v "$DATA_DIR:/data" \
    -v "$CONFIG_DIR:/config" \
    -v "$OUTPUT_PATH:/output" \
    autoclean-image \
    -DataPath "/data/$DATA_FILE" \
    -Task "$TASK" \
    -ConfigPath "/config/$CONFIG_FILE" \
    -OutputPath "/output"

# Check the exit status
if [ $? -eq 0 ]; then
    echo "Processing completed successfully"
else
    echo "Error during processing"
    exit 1
fi

exit 0
EOL
chmod +x scripts/autoclean.sh

# Create TROUBLESHOOTING.md
echo "📝 Creating TROUBLESHOOTING.md..."
cat > TROUBLESHOOTING.md << 'EOL'
# Troubleshooting Guide

This document contains solutions for common issues you might encounter when using the EEG Data Processing Watchdog.

## Docker Issues

### Docker Not Running

**Symptoms:**
- Error messages containing "Cannot connect to the Docker daemon"
- "Docker daemon not running" errors

**Solutions:**
1. **For Windows/Mac:** Ensure Docker Desktop is running
   - Check for the Docker icon in the system tray/menu bar
   - Start Docker Desktop from your applications if it's not running

2. **For Linux:** Start the Docker service
   ```bash
   sudo systemctl start docker
   ```

3. **Check Docker status:**
   ```bash
   docker info
   ```

### Docker Permission Issues

**Symptoms:**
- "Permission denied" errors when interacting with Docker
- Container fails to start with permission-related errors

**Solutions:**
1. **Add your user to the docker group (Linux):**
   ```bash
   sudo usermod -aG docker $USER
   # Log out and log back in for changes to take effect
   ```

2. **Run with sudo (temporary solution):**
   ```bash
   sudo docker-compose up -d
   ```

### Container Build Failures

**Symptoms:**
- `docker-compose build` fails
- Error messages during the build process

**Solutions:**
1. **Check your internet connection**

2. **View detailed build logs:**
   ```bash
   docker-compose build --progress=plain
   ```

3. **Cleanup Docker:**
   ```bash
   docker system prune -a
   docker-compose build --no-cache
   ```

## Watchdog Issues

### No Files Being Processed

**Symptoms:**
- Files are placed in the input directory but nothing happens
- No error messages in the logs

**Solutions:**
1. **Check file extensions:**
   - Ensure the file extensions match those specified in `docker-compose.yml`
   - File extensions are case-sensitive

2. **Check file permissions:**
   - Ensure the files in the input directory are readable

3. **Check watchdog logs:**
   ```bash
   docker-compose logs -f
   ```

4. **Restart the container:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### Files Processed But No Output

**Symptoms:**
- Container logs show successful processing
- No files appear in the output directory

**Solutions:**
1. **Check output directory permissions:**
   - Ensure the output directory is writable by Docker

2. **Check container output logs:**
   ```bash
   docker-compose logs -f | grep "Processing completed"
   ```

3. **Check if processing actually failed:**
   - Look for error messages in the logs
   - Examine individual job logs in `output/[timestamp]_[filename]_[task]/process.log`

## Concurrent Processing Issues

### Too Many Processes Running

**Symptoms:**
- System performance degrades significantly
- High CPU/memory usage

**Solutions:**
1. **Reduce max workers:**
   - Edit `docker-compose.yml` and reduce the `--max-workers` parameter
   ```yaml
   command:
     # ... other parameters ...
     - "--max-workers"
     - "2"  # Reduced from default 3
   ```

2. **Restart the container with new settings:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### Processing Queue Gets Stuck

**Symptoms:**
- Some files never get processed
- Processing seems to stop after some files

**Solutions:**
1. **Check for orphaned lock files:**
   - These may be in `/tmp/autoclean_*.lock` inside the container

2. **Access the container and check processes:**
   ```bash
   docker exec -it eeg-watchdog_eeg-watchdog_1 bash
   ps aux
   ```

3. **Restart the container:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

## Autoclean Processing Issues

### Processing Errors

**Symptoms:**
- Container logs show errors during processing
- Error messages in job logs

**Solutions:**
1. **Check your configuration file:**
   - Ensure your autoclean configuration YAML is valid
   - Check for typos or missing parameters

2. **Verify file validity:**
   - Ensure your EEG data files are in the correct format
   - Try processing a known good file as a test

3. **Examine detailed logs:**
   - Check the specific job log at `output/[timestamp]_[filename]_[task]/process.log`

4. **Test with Docker directly:**
   ```bash
   docker run --rm \
     -v "$(pwd)/input:/data" \
     -v "$(pwd)/config:/config" \
     -v "$(pwd)/output:/output" \
     autoclean-image \
     -DataPath "/data/your_file.edf" \
     -Task "RestingEyesOpen" \
     -ConfigPath "/config/autoclean_config.yaml" \
     -OutputPath "/output"
   ```

## Advanced Troubleshooting

### Debug Mode

Enable detailed debug logging by modifying the logging level in `eeg_watchdog.py`:

```python
# Change this line
logging.basicConfig(
    level=logging.INFO,
    ...
)

# To:
logging.basicConfig(
    level=logging.DEBUG,
    ...
)
```

Then rebuild and restart the container:
```bash
docker-compose down
docker-compose build
docker-compose up -d
```

### Accessing Container Shell

Access the running container to debug from inside:

```bash
docker exec -it eeg-watchdog_eeg-watchdog_1 bash
```

### Checking Container Logs

View all container logs:

```bash
docker-compose logs -f
```

View logs for specific containers:

```bash
docker-compose logs -f eeg-watchdog
```

### Checking Docker Resource Usage

```bash
docker stats
```

If you're experiencing issues not covered by this guide, please check the container logs for more details and consider filing an issue on the repository with your log outputs.
EOL

# Create sample config.yaml
echo "📝 Creating sample config file..."
mkdir -p config
cat > config/sample_config.yaml << 'EOL'
# Sample autoclean configuration
# Replace this with your actual configuration

processing:
  task: RestingEyesOpen
  parameters:
    threshold: 0.75
    filter:
      lowcut: 1
      highcut: 40
    artifacts:
      remove: true
      method: 'ICA'

output:
  format: 'EDF'
  include_raw: false
  include_filtered: true
  include_report: true
EOL

# Create system architecture SVG
echo "📝 Creating system architecture diagram..."
mkdir -p docs/images
cat > docs/images/system-architecture.svg << 'EOL'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 600">
  <!-- Background -->
  <rect width="1000" height="600" fill="#f8f9fa" />

  <!-- Title -->
  <text x="500" y="40" font-family="Arial, sans-serif" font-size="24" text-anchor="middle" font-weight="bold">EEG Data Processing Watchdog - System Architecture</text>

  <!-- Host System Box -->
  <rect x="50" y="80" width="900" height="480" rx="10" fill="#e9ecef" stroke="#6c757d" stroke-width="2" />
  <text x="100" y="110" font-family="Arial, sans-serif" font-size="18" fill="#212529">Host System</text>

  <!-- Docker Container Box -->
  <rect x="100" y="130" width="800" height="380" rx="10" fill="#ffffff" stroke="#0366d6" stroke-width="2" stroke-dasharray="5,5" />
  <text x="150" y="160" font-family="Arial, sans-serif" font-size="16" fill="#0366d6">Docker Environment</text>

  <!-- EEG Watchdog Container -->
  <rect x="150" y="180" width="700" height="280" rx="8" fill="#dff0d8" stroke="#28a745" stroke-width="2" />
  <text x="300" y="210" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="#28a745">EEG Watchdog Container</text>

  <!-- Watchdog Script Component -->
  <rect x="180" y="230" width="260" height="100" rx="5" fill="#ffffff" stroke="#28a745" stroke-width="1" />
  <text x="310" y="260" font-family="Arial, sans-serif" font-size="14" text-anchor="middle" font-weight="bold">EEG Watchdog Script</text>
  <text x="310" y="280" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">File Monitoring</text>
  <text x="310" y="300" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">ThreadPool Management</text>
  <text x="310" y="320" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">Queue Processing</text>

  <!-- Autoclean Wrapper Component -->
  <rect x="560" y="230" width="260" height="100" rx="5" fill="#ffffff" stroke="#28a745" stroke-width="1" />
  <text x="690" y="260" font-family="Arial, sans-serif" font-size="14" text-anchor="middle" font-weight="bold">Autoclean Wrapper</text>
  <text x="690" y="280" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">Parameter Handling</text>
  <text x="690" y="300" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">Docker Execution</text>
  <text x="690" y="320" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">Lock File Management</text>

  <!-- Autoclean Container -->
  <rect x="300" y="350" width="400" height="80" rx="5" fill="#d1ecf1" stroke="#17a2b8" stroke-width="1" />
  <text x="500" y="380" font-family="Arial, sans-serif" font-size="14" text-anchor="middle" font-weight="bold">Autoclean Container</text>
  <text x="500" y="400" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">EEG Data Processing Pipeline</text>
  
  <!-- Connection Lines -->
  <!-- Watchdog to Wrapper -->
  <path d="M 440 280 L 560 280" stroke="#6c757d" stroke-width="2" stroke-dasharray="5,3" />
  <!-- Arrow tip -->
  <polygon points="550,276 560,280 550,284" fill="#6c757d" />
  
  <!-- Wrapper to Autoclean -->
  <path d="M 690 330 L 690 350" stroke="#6c757d" stroke-width="2" stroke-dasharray="5,3" />
  <!-- Arrow tip -->
  <polygon points="686,340 690,350 694,340" fill="#6c757d" />
  
  <!-- Directory Mounting -->
  <!-- Input Directory -->
  <rect x="100" y="480" width="180" height="60" rx="5" fill="#fff3cd" stroke="#ffc107" stroke-width="1" />
  <text x="190" y="510" font-family="Arial, sans-serif" font-size="14" text-anchor="middle" font-weight="bold">Input Directory</text>
  <text x="190" y="530" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">/data/input</text>
  
  <!-- Config Directory -->
  <rect x="310" y="480" width="180" height="60" rx="5" fill="#f8d7da" stroke="#dc3545" stroke-width="1" />
  <text x="400" y="510" font-family="Arial, sans-serif" font-size="14" text-anchor="middle" font-weight="bold">Config Directory</text>
  <text x="400" y="530" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">/config</text>
  
  <!-- Output Directory -->
  <rect x="520" y="480" width="180" height="60" rx="5" fill="#cce5ff" stroke="#007bff" stroke-width="1" />
  <text x="610" y="510" font-family="Arial, sans-serif" font-size="14" text-anchor="middle" font-weight="bold">Output Directory</text>
  <text x="610" y="530" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">/data/output</text>
  
  <!-- Docker Socket -->
  <rect x="730" y="480" width="180" height="60" rx="5" fill="#e2e3e5" stroke="#6c757d" stroke-width="1" />
  <text x="820" y="510" font-family="Arial, sans-serif" font-size="14" text-anchor="middle" font-weight="bold">Docker Socket</text>
  <text x="820" y="530" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">/var/run/docker.sock</text>
  
  <!-- Directory Connection Lines -->
  <path d="M 190 480 L 190 420 L 230 420" stroke="#ffc107" stroke-width="2" />
  <path d="M 400 480 L 400 450 L 450 450" stroke="#dc3545" stroke-width="2" />
  <path d="M 610 480 L 610 420 L 560 420" stroke="#007bff" stroke-width="2" />
  <path d="M 820 480 L 820 420 L 760 420" stroke="#6c757d" stroke-width="2" />
  
  <!-- CLI Components -->
  <rect x="780" y="110" width="150" height="40" rx="5" fill="#ffffff" stroke="#6c757d" stroke-width="1" />
  <text x="855" y="135" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">PowerShell/Bash Scripts</text>
  
  <!-- Legend -->
  <rect x="100" y="550" width="800" height="40" rx="5" fill="#ffffff" stroke="#6c757d" stroke-width="1" />
  <circle cx="130" cy="570" r="6" fill="#dff0d8" stroke="#28a745" stroke-width="1" />
  <text x="145" y="574" font-family="Arial, sans-serif" font-size="12">Watchdog</text>
  
  <circle cx="230" cy="570" r="6" fill="#d1ecf1" stroke="#17a2b8" stroke-width="1" />
  <text x="245" y="574" font-family="Arial, sans-serif" font-size="12">Autoclean</text>
  
  <circle cx="330" cy="570" r="6" fill="#fff3cd" stroke="#ffc107" stroke-width="1" />
  <text x="345" y="574" font-family="Arial, sans-serif" font-size="12">Input</text>
  
  <circle cx="420" cy="570" r="6" fill="#f8d7da" stroke="#dc3545" stroke-width="1" />
  <text x="435" y="574" font-family="Arial, sans-serif" font-size="12">Config</text>
  
  <circle cx="510" cy="570" r="6" fill="#cce5ff" stroke="#007bff" stroke-width="1" />
  <text x="525" y="574" font-family="Arial, sans-serif" font-size="12">Output</text>
  
  <line x1="580" y1="570" x2="610" y2="570" stroke="#6c757d" stroke-width="2" stroke-dasharray="5,3" />
  <text x="625" y="574" font-family="Arial, sans-serif" font-size="12">Data Flow</text>
  
  <line x1="670" y1="570" x2="700" y2="570" stroke="#6c757d" stroke-width="2" />
  <text x="715" y="574" font-family="Arial, sans-serif" font-size="12">Volume Mounting</text>
</svg>
EOL

# Create LICENSE file
echo "📝 Creating LICENSE file..."
cat > LICENSE << 'EOL'
MIT License

Copyright (c) 2025 

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOL

# Create .gitignore
echo "📝 Creating .gitignore..."
cat > .gitignore << 'EOL'
# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*$py.class

# Environment
.env
.venv
env/
venv/
ENV/

# Logs
*.log

# Data directories (usually large files)
input/*
!input/.gitkeep
output/*
!output/.gitkeep

# Docker
.docker-volumes/

# OS specific
.DS_Store
Thumbs.db

# IDEs and editors
.idea/
.vscode/
*.swp
*.swo
EOL

# Create empty .gitkeep files to preserve empty directories
touch input/.gitkeep
touch output/.gitkeep
touch config/.gitkeep

# Final message
echo ""
echo "✅ EEG Watchdog repository successfully created in $(pwd)"
echo ""
echo "Next steps:"
echo "1. Add your autoclean configuration in the config directory"
echo "2. Build the Docker image: docker-compose build"
echo "3. Start the watchdog: docker-compose up -d"
echo "4. Place EEG data files in the input directory for automatic processing"
echo ""
echo "For more information, see the README.md and TROUBLESHOOTING.md files."
echo ""

# Create README.md
echo "📝 Creating README.md..."
cat > README.md << 'EOL'
# EEG Data Processing Watchdog

A containerized solution for automatic monitoring and processing of EEG data files using the autoclean pipeline.

## System Overview

This system provides an automated way to process EEG data files with the following features:

- **Automatic Monitoring**: Watches directories for new EEG data files
- **Concurrent Processing**: Handles multiple files simultaneously with configurable limits
- **Docker Containerization**: Ensures consistent processing environment
- **Cross-Platform Support**: Works on Windows, Mac, and Linux
- **Command-Line Tools**: Provides easy-to-use scripts for manual processing

![System Architecture](./docs/images/system-architecture.svg)

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- For Windows: PowerShell 5.1+
- For Linux/Mac: Bash shell

### Installation

1. Clone this repository:
```bash
git clone https://github.com/yourusername/eeg-watchdog.git
cd eeg-watchdog
```

2. Create the required directories:
```bash
mkdir -p input output config
```

3. Add your autoclean configuration:
```bash
cp /path/to/your/autoclean_config.yaml ./config/
```

4. Build the Docker image:
```bash
docker-compose build
```

### Starting the Watchdog

Start the automatic file monitoring system:

```bash
docker-compose up -d
```

View the logs:

```bash
docker-compose logs -f
```

### Processing Files

#### Automatic Processing

Simply place EEG data files in the `input` directory. The system will automatically detect and process them according to your configuration.

#### Manual Processing

**Windows:**

```powershell
# Import the autoclean function
. ./scripts/autoclean.ps1

# Process a file
autoclean -DataPath "C:\path\to\data.edf" -Task "RestingEyesOpen" -ConfigPath "C:\path\to\config.yaml"
```

**Linux/Mac:**

```bash
# Make the script executable
chmod +x ./scripts/autoclean.sh

# Process a file
./scripts/autoclean.sh -DataPath "/path/to/data.edf" -Task "RestingEyesOpen" -ConfigPath "/path/to/config.yaml"
```

## Configuration Options

### Maximum Concurrent Processes

Adjust the `--max-workers` parameter in `docker-compose.yml` to control how many files can be processed simultaneously:

```yaml
command: 
  # ... other parameters ...
  - "--max-workers"
  - "5"  # Process up to 5 files simultaneously
```

### File Extensions

Modify the `--extensions` parameter in `docker-compose.yml` to specify which file types to monitor:

```yaml
command:
  # ... other parameters ...
  - "--extensions"
  - "edf"
  - "set"
  - "vhdr"
  - "bdf"
  - "cnt"
```

### Processing Task

Change the `--task` parameter to specify a different processing task:

```yaml
command:
  # ... other parameters ...
  - "--task"
  - "ASSR"  # Change from default "RestingEyesOpen"
```

## Directory Structure

```
eeg-watchdog/
├── eeg_watchdog.py           # Main watchdog script
├── autoclean_wrapper.sh      # Wrapper for autoclean command
├── Dockerfile                # Container definition
├── docker-compose.yml        # Container orchestration
├── requirements.txt          # Python dependencies
├── scripts/
│   ├── autoclean.ps1         # Windows PowerShell script
│   └── autoclean.sh          # Linux/Mac Bash script
├── input/                    # Place EEG data files here
├── output/                   # Processed results appear here
├── config/                   # Configuration files
└── docs/
    └── images/
        └── system-architecture.svg
```

## Command-Line Parameters

### Watchdog Script

The `eeg_watchdog.py` script accepts the following parameters:

- `--dir`, `-d`: Directory to monitor for new EEG data files
- `--extensions`, `-e`: EEG data file extensions to monitor
- `--script`, `-s`: Path to the autoclean script
- `--task`, `-t`: EEG processing task type
- `--config`, `-c`: Path to configuration YAML file
- `--output`, `-o`: Output directory for processed files
- `--max-workers`, `-w`: Maximum number of concurrent processing tasks (default: 3)

### Command-Line Tools

Both the PowerShell and Bash scripts accept the same parameters:

- `-DataPath`: Directory containing raw EEG data or path to single data file
- `-Task`: Processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)
- `-ConfigPath`: Path to configuration YAML file
- `-OutputPath`: (Optional) Output directory, defaults to "./output"
- `-Help`: Display help information

## Troubleshooting

### Logs

- **Container Logs**: `docker-compose logs -f`
- **Processing Logs**: Check the `output/[timestamp]_[filename]_[task]/process.log` files
- **Debug Mode**: Modify the logging level in `eeg_watchdog.py` to DEBUG for more details

### Common Issues

1. **Docker not running**:
   - Ensure Docker Desktop (Windows/Mac) or Docker daemon (Linux) is running

2. **Permission issues**:
   - Ensure the input, output, and config directories have appropriate permissions

3. **No files being processed**:
   - Check that the file extensions match the ones specified in `docker-compose.yml`

4. **Processing errors**:
   - Check the logs for the specific error message
   - Ensure your configuration file is correct
   - Verify that the EEG data files are valid

## License

[MIT License](LICENSE)

## Acknowledgments

This tool was created to work with the autoclean EEG processing pipeline.