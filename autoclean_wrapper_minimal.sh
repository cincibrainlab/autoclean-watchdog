#!/bin/bash
# Simple autoclean_wrapper.sh for Docker-in-Docker

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
        -WorkDir)
            AUTOCLEAN_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            shift
            ;;
    esac
done

# Validate required parameters
if [ -z "$DATA_PATH" ] || [ -z "$TASK" ] || [ -z "$CONFIG_PATH" ]; then
    echo "Error: Missing required parameters"
    echo "Usage: $0 -DataPath <path> -Task <task_type> -ConfigPath <config_path> [-OutputPath <output_dir>] [-WorkDir <autoclean_path>]"
    exit 1
fi

# Map container paths to host paths for Docker-in-Docker
if [ -n "$INPUT_DIR" ] && [[ "$DATA_PATH" == /data/input/* ]]; then
    # Extract relative path from container input path
    REL_PATH=${DATA_PATH#/data/input/}
    # Convert to host path
    HOST_FILE_PATH="${INPUT_DIR}/${REL_PATH}"
    echo "Converted container path $DATA_PATH to host path $HOST_FILE_PATH"
else
    HOST_FILE_PATH="$DATA_PATH"
    echo "Using original path: $HOST_FILE_PATH"
fi

if [ -n "$CONFIG_DIR" ] && [[ "$CONFIG_PATH" == /app/configs/* ]]; then
    # Extract filename from config path
    CONFIG_FILE=${CONFIG_PATH##*/}
    # Convert to host path
    HOST_CONFIG_PATH="${CONFIG_DIR}/${CONFIG_FILE}"
    echo "Converted container config path $CONFIG_PATH to host path $HOST_CONFIG_PATH"
else
    HOST_CONFIG_PATH="$CONFIG_PATH"
    echo "Using original config path: $HOST_CONFIG_PATH"
fi

if [ -n "$OUTPUT_DIR" ] && [[ "$OUTPUT_PATH" == /data/output* ]]; then
    # For output directory, use the host output directory directly
    HOST_OUTPUT_PATH="$OUTPUT_DIR"
    echo "Using host output path: $HOST_OUTPUT_PATH"
else
    HOST_OUTPUT_PATH="$OUTPUT_PATH"
    echo "Using original output path: $HOST_OUTPUT_PATH"
fi

# Make sure autoclean script is executable
AUTOCLEAN_SCRIPT="${AUTOCLEAN_PATH}/autoclean.sh"
if [ -f "$AUTOCLEAN_SCRIPT" ]; then
    chmod +x "$AUTOCLEAN_SCRIPT"
else
    echo "Error: autoclean.sh not found at $AUTOCLEAN_SCRIPT"
    exit 1
fi

# Run the autoclean script with host paths
echo "Running autoclean with:"
echo "  Data path: $HOST_FILE_PATH"
echo "  Task: $TASK"
echo "  Config path: $HOST_CONFIG_PATH" 
echo "  Output path: $HOST_OUTPUT_PATH"
echo "  Work directory: $AUTOCLEAN_PATH"

"$AUTOCLEAN_SCRIPT" \
    -DataPath "$HOST_FILE_PATH" \
    -Task "$TASK" \
    -ConfigPath "$HOST_CONFIG_PATH" \
    -OutputPath "$HOST_OUTPUT_PATH" \
    -WorkDir "$AUTOCLEAN_PATH"

# Return the exit code from autoclean
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    echo "Processing completed successfully"
else
    echo "Error during processing (exit code: $EXIT_CODE)"
fi

exit $EXIT_CODE