#!/bin/bash
#
# autoclean_wrapper.sh - Wrapper script for autoclean EEG data processing
#
# Usage: ./autoclean_wrapper.sh -DataPath <file_path> -Task <task_type> -ConfigPath <config_path> -OutputPath <output_dir> -AutoCleanPath <autoclean_path>

# Function to display usage information
usage() {
    echo "Usage: $0 -DataPath <path> -Task <task_type> -ConfigPath <config_path> [-OutputPath <output_dir>] [-AutoCleanPath <autoclean_path>]"
    echo ""
    echo "Parameters:"
    echo "  -DataPath      Directory containing raw EEG data or path to single data file"
    echo "  -Task          Processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)"
    echo "  -ConfigPath    Path to configuration YAML file"
    echo "  -OutputPath    (Optional) Output directory, defaults to './output'"
    echo "  -AutoCleanPath (Optional) Path to the AutoClean repository, defaults to '/mnt/srv2/eeg_dependencies/autoclean_pipeline/'"
    echo "  -Help          Display this help message"
    exit 1
}

# Default output path
OUTPUT_PATH="./output"
# Default AutoClean repository path
AUTOCLEAN_PATH="/mnt/srv2/eeg_dependencies/autoclean_pipeline/"

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
        -AutoCleanPath)
            AUTOCLEAN_PATH="$2"
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
log "AutoClean repository path: $AUTOCLEAN_PATH"
log "Lock file: $LOCK_FILE"

# Path to the autoclean.sh script
AUTOCLEAN_SCRIPT="${AUTOCLEAN_PATH}/autoclean.sh"

log "TEST MODE: Would run autoclean.sh with the following parameters:"
echo "DataPath: $DATA_PATH"
echo "Task: $TASK"
echo "ConfigPath: $CONFIG_PATH"
echo "WorkDir: $AUTOCLEAN_PATH"
echo "Output would be logged to: $LOG_FILE"
# Comment out actual execution for test mode
# $AUTOCLEAN_SCRIPT \
#    -DataPath "$DATA_PATH" \
#    -Task "$TASK" \
#    -ConfigPath "$CONFIG_PATH" \
#    -WorkDir "$AUTOCLEAN_PATH" >> "$LOG_FILE" 2>&1

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
