#!/bin/bash

# Build script for Voxtral Mini

echo "🎤 Building Voxtral Mini..."

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode command line tools not found. Please install Xcode."
    exit 1
fi

# Navigate to project directory
cd "$(dirname "$0")"

# Build the project
echo "🔨 Building project..."
xcodebuild -project VoxtralMini.xcodeproj \
           -scheme VoxtralMini \
           -configuration Debug \
           -derivedDataPath build \
           build

# Check if build was successful
if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Find the built app
    APP_PATH="build/Build/Products/Debug/VoxtralMini.app"
    
    if [ -d "$APP_PATH" ]; then
        echo "🚀 Launching Voxtral Mini..."
        open "$APP_PATH"
    else
        echo "❌ Built app not found at expected location: $APP_PATH"
        exit 1
    fi
else
    echo "❌ Build failed. Please check for errors above."
    exit 1
fi
