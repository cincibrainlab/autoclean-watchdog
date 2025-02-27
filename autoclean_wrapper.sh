#!/bin/bash
# Simple autoclean_wrapper.sh for Docker-in-Docker
set -e  # Exit immediately if a command fails

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -DataPath)
            DATA_PATH="$2"
            shift 2
            echo "WRAPPER DATA_PATH: $DATA_PATH"
            ;;
        -Task)
            TASK="$2"
            shift 2
            echo "WRAPPER TASK: $TASK"
            ;;
        -ConfigPath)
            CONFIG_PATH="$2"
            shift 2
            echo "WRAPPER CONFIG_PATH: $CONFIG_PATH"
            ;;
        -OutputPath)
            OUTPUT_PATH="$2"
            shift 2
            echo "WRAPPER OUTPUT_PATH: $OUTPUT_PATH"
            ;;
        -WorkDir)
            AUTOCLEAN_PATH="$2"
            shift 2
            echo "WRAPPER AUTOCLEAN_PATH: $AUTOCLEAN_PATH"
            ;;
        *)
            echo "Unknown parameter: $1"
            shift
            ;;
    esac
done

# Validate required parameters
if [ -z "$DATA_PATH" ] || [ -z "$TASK" ] || [ -z "$CONFIG_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
    echo "Error: Missing required parameters"
    echo "Usage: $0 -DataPath <path> -Task <task_type> -ConfigPath <config_path> [-OutputPath <output_dir>] [-WorkDir <autoclean_path>]"
    exit 1
fi

# Make sure autoclean script is executable
AUTOCLEAN_SCRIPT="/autoclean_pipeline/autoclean.sh"
if [ -f "$AUTOCLEAN_SCRIPT" ]; then
    dos2unix "$AUTOCLEAN_SCRIPT"
    chmod +x "$AUTOCLEAN_SCRIPT"
else
    echo "Error: autoclean.sh not found at $AUTOCLEAN_SCRIPT"
    exit 1
fi

# Make sure autoclean script is executable
chmod +x "$AUTOCLEAN_SCRIPT" || echo "Warning: Could not make script executable"

# Run the autoclean script with host paths
echo "Running autoclean with:"
echo "  Data path: $DATA_PATH"
echo "  Task: $TASK"
echo "  Config path: $CONFIG_PATH" 
echo "  Output path: $OUTPUT_PATH"
echo "  Work directory: /autoclean_pipeline"

# Set environment variable to skip path validation
export AUTOCLEAN_SKIP_PATH_VALIDATION=1

# Extract config filename from path for docker-compose
CONFIG_DIR=$(dirname "$CONFIG_PATH")
CONFIG_FILENAME=$(basename "$CONFIG_PATH")
echo "Config directory: $CONFIG_DIR"
echo "Config filename: $CONFIG_FILENAME"

# Run the script and capture output
OUTPUT=$("$AUTOCLEAN_SCRIPT" \
    -DataPath "$DATA_PATH" \
    -Task "$TASK" \
    -ConfigPath "$CONFIG_PATH" \
    -OutputPath "$OUTPUT_PATH" \
    -WorkDir /autoclean_pipeline \
    # -Debug 
    2>&1)

# Return the exit code from autoclean
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    echo "Processing completed successfully"
    echo "===== BEGIN autoclean.sh output ====="
    echo "$OUTPUT"
    echo "===== END autoclean.sh output ====="
else
    echo "Error during processing (exit code: $EXIT_CODE)"
    echo "===== BEGIN autoclean.sh output ====="
    echo "$OUTPUT"
    echo "===== END autoclean.sh output ====="
fi

exit $EXIT_CODE