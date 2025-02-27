#!/bin/bash
#
# autoclean_wrapper.sh - Wrapper script for autoclean EEG data processing
#
# Usage: ./autoclean_wrapper.sh -DataPath <file_path> -Task <task_type> -ConfigPath <config_path> -OutputPath <output_dir> -WorkDir <autoclean_path>

# Enable debug mode to see all commands being executed
set -x

# Function to display usage information
usage() {
    echo "Usage: $0 -DataPath <path> -Task <task_type> -ConfigPath <config_path> [-OutputPath <output_dir>] [-WorkDir <autoclean_path>]"
    echo ""
    echo "Parameters:"
    echo "  -DataPath      Directory containing raw EEG data or path to single data file"
    echo "  -Task          Processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)"
    echo "  -ConfigPath    Path to configuration YAML file"
    echo "  -OutputPath    (Optional) Output directory, defaults to './output'"
    echo "  -WorkDir (Optional) Path to the AutoClean repository, defaults to '/mnt/srv2/eeg_dependencies/autoclean_pipeline/'"
    echo "  -Help          Display this help message"
    exit 1
}

# Default output path
OUTPUT_PATH="./output"

echo "DEBUG: Script started with arguments: $@"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    echo "DEBUG: Processing argument: $key"
    case $key in
        -DataPath)
            DATA_PATH="$2"
            echo "DEBUG: DATA_PATH set to: $DATA_PATH"
            shift 2
            ;;
        -Task)
            TASK="$2"
            echo "DEBUG: TASK set to: $TASK"
            shift 2
            ;;
        -ConfigPath)
            CONFIG_PATH="$2"
            echo "DEBUG: CONFIG_PATH set to: $CONFIG_PATH"
            shift 2
            ;;
        -OutputPath)
            OUTPUT_PATH="$2"
            echo "DEBUG: OUTPUT_PATH set to: $OUTPUT_PATH"
            shift 2
            ;;
        -WorkDir)
            AUTOCLEAN_PATH="$2"
            echo "DEBUG: AUTOCLEAN_PATH set to: $AUTOCLEAN_PATH"
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

# Get filename without extension and path
FILE_BASE=$(basename "$DATA_PATH")
FILE_NAME="${FILE_BASE%.*}"
echo "DEBUG: File base name: $FILE_BASE, File name without extension: $FILE_NAME"

# Get current timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
echo "DEBUG: Timestamp: $TIMESTAMP"

JOB_DIR="${OUTPUT_PATH}/${TIMESTAMP}_${FILE_NAME}_${TASK}"
echo "DEBUG: Job directory path: $JOB_DIR"

# Check if we're using host paths
if [ -n "$USING_HOST_PATHS" ] || [ -n "$HOST_INPUT_DIR" ] && [ -n "$HOST_OUTPUT_DIR" ] && [ -n "$HOST_CONFIG_DIR" ] && [ -n "$HOST_AUTOCLEAN_DIR" ]; then
    # When using host paths, we'll create directories on the host side, not in the container
    log_dir_created=false
    echo "DEBUG: Using host paths - skipping JOB_DIR creation in container"
else
    # Create the job directory in the container only if not using host paths
    mkdir -p "$JOB_DIR"
    log_dir_created=true
    echo "DEBUG: Created job directory in container: $JOB_DIR"
fi

# Create a lockfile name for this specific file
LOCK_FILE="/tmp/autoclean_$(echo "${DATA_PATH}" | md5sum | cut -d' ' -f1).lock"
echo "DEBUG: Lock file path: $LOCK_FILE"

# Create a log file
if [ "$log_dir_created" = "true" ]; then
    # If we created the job directory in the container, use it for logs
    LOG_FILE="${JOB_DIR}/process.log"
    echo "DEBUG: Log file path (container): $LOG_FILE"
else
    # When using host paths, use a temporary log file in the container
    LOG_FILE="/tmp/autoclean_$(echo "${DATA_PATH}" | md5sum | cut -d' ' -f1).log"
    echo "DEBUG: Using temporary log file in container: $LOG_FILE"
fi

# Log function
log() {
    local message="$(date +'%Y-%m-%d %H:%M:%S') - $1"
    echo "$message"
    
    # Only append to log file if it's accessible
    if [ -n "$LOG_FILE" ] && { [ -f "$LOG_FILE" ] || touch "$LOG_FILE" 2>/dev/null; }; then
        echo "$message" >> "$LOG_FILE"
    fi
}

# Initial log entry to create the log file
log "Starting autoclean wrapper script"

# Create the lock file
touch "$LOCK_FILE"
echo "DEBUG: Created lock file: $LOCK_FILE"

# Ensure the lock file is removed when the script exits
trap 'rm -f "$LOCK_FILE"; log "Processing ended (lock released)."' EXIT

# Log the execution
log "Processing EEG data: $DATA_PATH"
log "Task: $TASK"
log "Config: $CONFIG_PATH"
log "Output directory: $JOB_DIR"
log "AutoClean repository path: $AUTOCLEAN_PATH"
log "Lock file: $LOCK_FILE"

# Check if we have host path environment variables
if [ -n "$HOST_INPUT_DIR" ] && [ -n "$HOST_OUTPUT_DIR" ] && [ -n "$HOST_CONFIG_DIR" ] && [ -n "$HOST_AUTOCLEAN_DIR" ]; then
    log "Using host paths for Docker-in-Docker"
    log "Host input directory: $HOST_INPUT_DIR"
    log "Host output directory: $HOST_OUTPUT_DIR"
    log "Host config directory: $HOST_CONFIG_DIR"
    log "Host autoclean directory: $HOST_AUTOCLEAN_DIR"
    log "Host file path: $HOST_FILE_PATH"
    
    # Create a relative path for the job directory
    if [[ "$JOB_DIR" == /data/output/* ]]; then
        REL_JOB_DIR="${JOB_DIR#/data/output/}"
        HOST_JOB_DIR="${HOST_OUTPUT_DIR}/${REL_JOB_DIR}"
        log "Converted job directory to host path: $HOST_JOB_DIR"
    else
        HOST_JOB_DIR="$JOB_DIR"
        log "Could not convert job directory to host path, using as is: $HOST_JOB_DIR"
    fi
    
    # When using host paths, we don't need to create directories in the container
    # The directories should already exist on the host or will be created there
    log "Using host paths - skipping directory creation in container"
    
    # Instead of using the host path directly, use the container's mounted path
    # The autoclean.sh script should be in the mounted autoclean directory
    AUTOCLEAN_SCRIPT="/autoclean_pipeline/autoclean.sh"
    log "Using autoclean script from container path: $AUTOCLEAN_SCRIPT"
    
    # Check if the script exists in the container
    if [ ! -f "$AUTOCLEAN_SCRIPT" ]; then
        log "ERROR: autoclean.sh script not found at $AUTOCLEAN_SCRIPT"
        log "Checking directory contents:"
        ls -la /autoclean_pipeline/
        exit 1
    fi

    # Convert the script to Unix format
    dos2unix "$AUTOCLEAN_SCRIPT"
    log "Converted autoclean script to Unix format"
    
    # Make sure the script is executable
    chmod +x "$AUTOCLEAN_SCRIPT"
    log "Made autoclean script executable"
    
    # Convert Windows paths to Unix format for the command
    HOST_FILE_PATH_UNIX=$(echo "$HOST_FILE_PATH" | sed 's/\\/\//g')
    HOST_CONFIG_DIR_UNIX=$(echo "$HOST_CONFIG_DIR" | sed 's/\\/\//g')
    HOST_JOB_DIR_UNIX=$(echo "$HOST_JOB_DIR" | sed 's/\\/\//g')

    # Append the config filename to the config directory path
    HOST_CONFIG_PATH_UNIX="${HOST_CONFIG_DIR_UNIX}/autoclean_config.yaml"
    log "Created config file path: $HOST_CONFIG_PATH_UNIX"

    log "Converted paths for command:"
    log "  File path: $HOST_FILE_PATH_UNIX"
    log "  Config dir: $HOST_CONFIG_DIR_UNIX"
    log "  Config file path: $HOST_CONFIG_PATH_UNIX"
    log "  Job dir: $HOST_JOB_DIR_UNIX"
    
    # Set environment variable to tell autoclean.sh to skip path validation for host paths
    export AUTOCLEAN_SKIP_PATH_VALIDATION=1
    log "Setting AUTOCLEAN_SKIP_PATH_VALIDATION=1 to skip path validation for host paths"
    
    # Check if docker is running
    log "Checking Docker status:"
    docker info > "${LOG_FILE}.docker_info" 2>&1 || log "WARNING: Docker may not be running properly"
    
    # Check if docker-compose.yml exists in the autoclean directory
    log "Checking for docker-compose.yml in autoclean directory:"
    if [ -f "/autoclean_pipeline/docker-compose.yml" ]; then
        log "docker-compose.yml found in /autoclean_pipeline/"
        log "Contents of docker-compose.yml:"
        cat "/autoclean_pipeline/docker-compose.yml" >> "${LOG_FILE}" 2>&1
    else
        log "ERROR: docker-compose.yml not found in /autoclean_pipeline/"
        log "Directory contents:"
        ls -la "/autoclean_pipeline/" >> "${LOG_FILE}" 2>&1
    fi
    
    # Run the script with output capture
    log "Running autoclean.sh script with arguments:"
    log "  -DataPath: $HOST_FILE_PATH_UNIX"
    log "  -Task: $TASK"
    log "  -ConfigPath: $HOST_CONFIG_PATH_UNIX"
    log "  -OutputPath: $HOST_JOB_DIR_UNIX"
    
    # Capture both stdout and stderr
    OUTPUT=$("$AUTOCLEAN_SCRIPT" \
        -DataPath "$HOST_FILE_PATH_UNIX" \
        -Task "$TASK" \
        -ConfigPath "$HOST_CONFIG_PATH_UNIX" \
        -OutputPath "$HOST_JOB_DIR_UNIX" \
        -WorkDir "/autoclean_pipeline" \
        -Debug 2>&1)
    
    # Save the exit code immediately
    EXIT_CODE=$?
    log "autoclean.sh script exit code: $EXIT_CODE"
    
    # Log the output
    log "===== BEGIN autoclean.sh output ====="
    echo "$OUTPUT" >> "${LOG_FILE}"
    log "===== END autoclean.sh output ====="
else
    # Error: Host paths are required
    log "ERROR: Host path environment variables are not set. This script requires Docker-in-Docker functionality."
    log "Please ensure the following environment variables are set:"
    log "  - HOST_INPUT_DIR"
    log "  - HOST_OUTPUT_DIR"
    log "  - HOST_CONFIG_DIR"
    log "  - HOST_AUTOCLEAN_DIR"
    log "  - HOST_FILE_PATH"
    exit 1
fi

# Check the exit status
if [ $EXIT_CODE -eq 0 ]; then
    log "Processing completed successfully"
    
    # Log the final output location
    log "Processing results are available in: $JOB_DIR"
    
    # No longer copying results to avoid duplication
    log "NOTE: Results are only stored in the job directory to prevent duplication"
else
    log "Error during processing (exit code: $EXIT_CODE)"
    echo "DEBUG: Error details from autoclean.sh:"
    echo "$OUTPUT"
    exit 1
fi

echo "DEBUG: Script completed successfully"
exit 0
