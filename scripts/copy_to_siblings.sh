#!/bin/bash

relpath() {
    local pos="${1%%/}"
    local ref="${2%%/}"
    local down=''
    while :; do
        test "$pos" = '/' && break
        case "$ref" in
            "$pos"/*) break;;
        esac
        down="../$down"
        pos=${pos%/*}
    done
    echo "$down${ref##"$pos"/}"
}

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Base directory (parent of scripts)
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Config file
CONFIG_FILE="$SCRIPT_DIR/config.txt"

# Read config
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Determine source directory
if [[ "$SOURCE" =~ ^[A-Za-z]: ]] || [[ "$SOURCE" =~ ^/ ]]; then
    SOURCE_DIR="$SOURCE"
else
    SOURCE_DIR="$BASE_DIR/$SOURCE"
fi

# Check if source exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

# Copy to each target
for target in "${TARGETS[@]}"; do
    if [[ "$target" =~ ^[A-Za-z]: ]] || [[ "$target" =~ ^/ ]]; then
        TARGET_DIR="$target"
    else
        TARGET_DIR="$BASE_DIR/$target"
    fi
    if [ ! -d "$TARGET_DIR" ]; then
        echo "Target directory does not exist: $TARGET_DIR"
        continue
    fi

    /usr/bin/find "$SOURCE_DIR" -name "*.lua" -type f | while read -r file; do
        rel_path="$(relpath "$SOURCE_DIR" "$file")"
        target_file="$TARGET_DIR/$rel_path"
        if [ ! -f "$target_file" ] || [ "$file" -nt "$target_file" ]; then
            mkdir -p "$TARGET_DIR/$(dirname "$rel_path")"
            cp "$file" "$target_file"
        fi
    done    

    echo "Contents copied successfully to: $TARGET_DIR"
done
