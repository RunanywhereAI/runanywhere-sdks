#!/bin/bash

# This script copies the appropriate RunAnywhereConfig plist based on build configuration
# Add this as a "Run Script" build phase in your Xcode project

# Get the configuration
CONFIGURATION="${CONFIGURATION}"
RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

echo "Build configuration: ${CONFIGURATION}"
echo "Resources directory: ${RESOURCES_DIR}"

# Determine which config file to use
if [ "${CONFIGURATION}" == "Debug" ]; then
    CONFIG_FILE="RunAnywhereConfig-Debug.plist"
else
    CONFIG_FILE="RunAnywhereConfig-Release.plist"
fi

# Source path
SOURCE_PATH="${SRCROOT}/RunAnywhereAI/Resources/${CONFIG_FILE}"
DESTINATION_PATH="${RESOURCES_DIR}/RunAnywhereConfig.plist"

echo "Copying ${CONFIG_FILE} to RunAnywhereConfig.plist"

# Check if source exists
if [ ! -f "${SOURCE_PATH}" ]; then
    echo "Warning: ${SOURCE_PATH} does not exist"
    exit 0
fi

# Create resources directory if it doesn't exist
mkdir -p "${RESOURCES_DIR}"

# Copy the file
cp "${SOURCE_PATH}" "${DESTINATION_PATH}"

echo "Environment config copied successfully"
