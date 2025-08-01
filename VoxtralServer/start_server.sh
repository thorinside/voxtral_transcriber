#!/bin/bash

# Voxtral Server Startup Script
# Optimized for NVIDIA RTX 5090

set -e  # Exit on any error

echo "🎤 Voxtral Transcription Server Startup"
echo "========================================="

# Check if Python 3.8+ is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed."
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo "🐍 Python version: $PYTHON_VERSION"

# Check if pip is available
if ! command -v pip3 &> /dev/null; then
    echo "❌ pip3 is required but not installed."
    exit 1
fi

# Check if CUDA is available
if command -v nvidia-smi &> /dev/null; then
    echo "🎮 NVIDIA GPU detected:"
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits | head -1
else
    echo "⚠️  No NVIDIA GPU detected. Server will run on CPU (not recommended)."
fi

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔄 Activating virtual environment..."
source venv/bin/activate

# Upgrade pip
echo "⬆️  Upgrading pip..."
pip install --upgrade pip

# Install PyTorch with CUDA support first (for RTX 5090)
echo "🔥 Installing PyTorch with CUDA 12.1 support..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# Install other requirements
echo "📚 Installing Python dependencies..."
pip install -r requirements.txt

# Check if model download is needed
echo "🧠 Checking Voxtral model availability..."
python3 -c "
try:
    from transformers import AutoProcessor, VoxtralForConditionalGeneration
    processor = AutoProcessor.from_pretrained('mistralai/Voxtral-Mini-3B-2507', local_files_only=True)
    print('✅ Model already downloaded locally')
except:
    print('📥 Model needs to be downloaded (will happen on first run)')
"

# Create logs directory
mkdir -p logs

# Set environment variables for optimal performance
export CUDA_VISIBLE_DEVICES=0
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export TOKENIZERS_PARALLELISM=false

echo "🚀 Starting Voxtral server..."
echo "🌐 Server will be available at: http://localhost:8080"
echo "📖 API documentation: http://localhost:8080/docs"
echo "🛑 Press Ctrl+C to stop the server"
echo ""

# Start the server
python3 server.py --host 0.0.0.0 --port 8080 --log-level info
