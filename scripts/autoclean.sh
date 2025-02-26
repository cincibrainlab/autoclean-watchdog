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
