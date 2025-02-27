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

# Create a unique output subdirectory for this processing job
# This helps prevent file conflicts when multiple jobs run in parallel
# The final structure will be:
# OUTPUT_PATH/
# └── TIMESTAMP_FILENAME_TASK/
#     └── (processing results)

# Get filename without extension and path
FILE_BASE=$(basename "$DATA_PATH")
FILE_NAME="${FILE_BASE%.*}"
echo "DEBUG: File base name: $FILE_BASE, File name without extension: $FILE_NAME"

# Get current timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
echo "DEBUG: Timestamp: $TIMESTAMP"

JOB_DIR="${OUTPUT_PATH}/${TIMESTAMP}_${FILE_NAME}_${TASK}"
echo "DEBUG: Creating job directory: $JOB_DIR"
mkdir -p "$JOB_DIR"
log_dir_created=true

# Create a lockfile name for this specific file
LOCK_FILE="/tmp/autoclean_$(echo "${DATA_PATH}" | md5sum | cut -d' ' -f1).lock"
echo "DEBUG: Lock file path: $LOCK_FILE"

# Create a log file
LOG_FILE="${JOB_DIR}/process.log"
echo "DEBUG: Log file path: $LOG_FILE"

# Log function
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
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

# Path to the autoclean.sh script
AUTOCLEAN_SCRIPT="${AUTOCLEAN_PATH}/autoclean.sh"
echo "DEBUG: AutoClean script path: $AUTOCLEAN_SCRIPT"

# Extract config directory and filename
CONFIG_DIR=$(dirname "$CONFIG_PATH")
CONFIG_FILE=$(basename "$CONFIG_PATH")
echo "DEBUG: Config directory: $CONFIG_DIR, Config filename: $CONFIG_FILE"

# Update CONFIG_PATH to only use the directory
CONFIG_PATH="$CONFIG_DIR"
echo "DEBUG: Updated CONFIG_PATH to directory only: $CONFIG_PATH"


# Run autoclean.sh with the job directory as the output path
# This ensures each processing job has its own isolated output directory
log "Running autoclean.sh with output path: $JOB_DIR"
echo "DEBUG: Full command: $AUTOCLEAN_SCRIPT -DataPath \"$DATA_PATH\" -Task \"$TASK\" -ConfigPath \"$CONFIG_PATH\" -OutputPath \"$JOB_DIR\" -WorkDir \"$AUTOCLEAN_PATH\""

# Run with output redirected to log file but also capture to a variable for debugging
OUTPUT=$($AUTOCLEAN_SCRIPT \
    -DataPath "$DATA_PATH" \
    -Task "$TASK" \
    -ConfigPath "$CONFIG_PATH" \
    -OutputPath "$JOB_DIR" \
    -WorkDir "$AUTOCLEAN_PATH" 2>&1)

# Save the exit code immediately
EXIT_CODE=$?
echo "DEBUG: AutoClean exit code: $EXIT_CODE"
echo "DEBUG: AutoClean output: $OUTPUT"

# Also write the output to the log file
echo "$OUTPUT" >> "$LOG_FILE"

# Check the exit status
if [ $EXIT_CODE -eq 0 ]; then
    log "Processing completed successfully"
    
    # Only copy if JOB_DIR is different from OUTPUT_PATH
    if [ "$JOB_DIR" != "$OUTPUT_PATH" ]; then
        log "Copying results from job directory to main output directory"
        echo "DEBUG: Running: cp -r \"$JOB_DIR\"/* \"$OUTPUT_PATH\"/"
        cp -r "$JOB_DIR"/* "$OUTPUT_PATH"/ >> "$LOG_FILE" 2>&1
        CP_EXIT_CODE=$?
        echo "DEBUG: Copy exit code: $CP_EXIT_CODE"
        
        if [ $CP_EXIT_CODE -eq 0 ]; then
            log "Results copied to main output directory: $OUTPUT_PATH"
        else
            log "Error copying results to main output directory (exit code: $CP_EXIT_CODE)"
            echo "DEBUG: Contents of job directory:"
            ls -la "$JOB_DIR"
            echo "DEBUG: Contents of output directory:"
            ls -la "$OUTPUT_PATH"
        fi
        
        # Log the final directory structure
        log "Final directory structure:"
        log "- Job directory (contains processing results): $JOB_DIR"
        log "- Main output directory (contains copied results): $OUTPUT_PATH"
    else
        log "Job directory is the same as output directory, no need to copy"
    fi
else
    log "Error during processing (exit code: $EXIT_CODE)"
    echo "DEBUG: Error details from autoclean.sh:"
    echo "$OUTPUT"
    exit 1
fi

echo "DEBUG: Script completed successfully"
exit 0
