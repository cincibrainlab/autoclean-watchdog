#!/bin/bash
REVIEW_SCRIPT="/autoclean_pipeline/review.sh"

# Get OUTPUT_PATH from environment if not already set
if [ -z "$OUTPUT_PATH" ]; then
    # Use the host output directory if available
    if [ -n "$OUTPUT_DIR" ]; then
        OUTPUT_PATH="$OUTPUT_DIR"
    else
        OUTPUT_PATH="/data/output"
    fi
fi

# Get BOT_NAME from environment or use default
if [ -z "$BOT_NAME" ]; then
    BOT_NAME="default"
fi

# Convert to unix format
dos2unix "$REVIEW_SCRIPT"

# Make sure review script is executable
chmod +x "$REVIEW_SCRIPT"

# Run the review script with host paths
echo "Running review with:"
echo "  Output path: $OUTPUT_PATH"
echo "  Bot name: $BOT_NAME"

# Export BOT_NAME so review.sh can access it
export BOT_NAME

# Run the review script
"$REVIEW_SCRIPT" "$OUTPUT_PATH"
