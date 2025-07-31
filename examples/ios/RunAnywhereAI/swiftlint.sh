#!/bin/bash

# SwiftLint build phase script for Xcode

# Check if SwiftLint is installed
if which swiftlint >/dev/null; then
    swiftlint
else
    echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
    echo "Install using: brew install swiftlint"
fi
