# 🎤 Voxtral Transcription Server

A high-performance transcription server powered by the Voxtral-Mini-3B model, optimized for NVIDIA GPUs including the RTX 5090.

## 🚀 Features

- **GPU-Accelerated**: Optimized for NVIDIA RTX 5090 and other CUDA-capable GPUs
- **FastAPI Backend**: Modern, async web framework with automatic API documentation
- **Real-time Transcription**: Low-latency audio transcription
- **RESTful API**: Clean HTTP endpoints for easy integration
- **Multiple Audio Formats**: Support for WAV, MP3, and FLAC files
- **Health Monitoring**: Built-in health checks and performance metrics
- **Production Ready**: Systemd service configuration and logging

## 🛠️ Requirements

### Hardware
- **GPU**: NVIDIA RTX 5090 recommended (24GB+ VRAM)
- **RAM**: 32GB+ system memory
- **Storage**: 10GB+ free space for model and dependencies

### Software
- **OS**: Linux (Ubuntu 20.04+ recommended)
- **Python**: 3.8+
- **CUDA**: 12.1+ (for RTX 5090)
- **NVIDIA Driver**: 535+ 

## 📦 Installation

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd VoxtralServer
```

### 2. Install Dependencies

**Option A: Automated Setup (Recommended)**
```bash
chmod +x start_server.sh
./start_server.sh
```

**Option B: Manual Setup**
```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install PyTorch with CUDA 12.1 support
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# Install other dependencies
pip install -r requirements.txt
```

### 3. Verify Installation

```bash
# Test the server
python3 test_client.py

# Or check health endpoint
curl http://localhost:8080/health
```

## 🚀 Running the Server

### Development Mode
```bash
source venv/bin/activate
python3 server.py --host 0.0.0.0 --port 8080 --reload
```

### Production Mode
```bash
source venv/bin/activate
python3 server.py --host 0.0.0.0 --port 8080 --log-level info
```

### Using Startup Script
```bash
./start_server.sh
```

### Systemd Service (Production)
```bash
# Install the service
sudo cp voxtral.service /etc/systemd/system/
sudo systemctl daemon-reload

# Edit the service file to update paths
sudo nano /etc/systemd/system/voxtral.service

# Enable and start the service
sudo systemctl enable voxtral
sudo systemctl start voxtral

# Check status
sudo systemctl status voxtral

# View logs
sudo journalctl -u voxtral -f
```

## 📡 API Endpoints

### Health Check
```bash
GET /health
```

Response:
```json
{
  "status": "healthy",
  "model_loaded": true,
  "device": "cuda",
  "gpu_available": true
}
```

### Transcription (JSON Response)
```bash
POST /transcribe
Content-Type: multipart/form-data

file: <audio_file>
language: en (optional)
model_id: mistralai/Voxtral-Mini-3B-2507 (optional)
```

Response:
```json
{
  "text": "Transcribed text here",
  "language": "en",
  "processing_time": 2.45
}
```

### Simple JSON Response
```bash
POST /transcribe-json
```

Response:
```json
{
  "text": "Transcribed text here"
}
```

### API Documentation
Visit `http://localhost:8080/docs` for interactive API documentation.

## 🔧 Configuration

Edit `config.json` to customize server settings:

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 8080,
    "log_level": "info"
  },
  "model": {
    "repo_id": "mistralai/Voxtral-Mini-3B-2507",
    "device": "cuda",
    "dtype": "bfloat16"
  }
}
```

## 📊 Performance Optimization

### RTX 5090 Specific Optimizations

The server is optimized for the RTX 5090 with:

- **CUDA 12.1**: Latest CUDA toolkit support
- **bfloat16 Precision**: Optimal balance of speed and accuracy
- **Memory Management**: Efficient GPU memory usage
- **Async Processing**: Non-blocking transcription requests

### Environment Variables

```bash
# GPU settings
export CUDA_VISIBLE_DEVICES=0
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export TOKENIZERS_PARALLELISM=false

# Performance tuning
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8
```

## 🧪 Testing

### Run Test Suite
```bash
python3 test_client.py
```

### Test with Custom Server URL
```bash
python3 test_client.py http://your-server:8080
```

### Manual Testing with curl
```bash
# Health check
curl http://localhost:8080/health

# Transcribe audio file
curl -X POST \
  -F "file=@test.wav" \
  -F "language=en" \
  http://localhost:8080/transcribe
```

## 🔗 Integration with macOS App

Your Voxtral Mini macOS app is configured to work with this server:

1. **Default URL**: `http://localhost:8080/transcribe`
2. **Audio Format**: WAV files
3. **Response Format**: JSON with `text` field

### macOS App Configuration

In the Voxtral Mini app, set the server URL to:
```
http://your-linux-server-ip:8080/transcribe
```

## 📝 Logging

Logs are written to both console and file:
- **Console**: Real-time logging output
- **File**: `logs/voxtral_server.log`
- **Rotation**: 10MB max size, 5 backup files

### Log Levels
- `DEBUG`: Detailed debugging information
- `INFO`: General operational information
- `WARNING`: Warning messages
- `ERROR`: Error conditions

## 🔍 Troubleshooting

### GPU Not Detected
```bash
# Check CUDA installation
nvidia-smi
nvcc --version

# Check PyTorch CUDA support
python3 -c "import torch; print(torch.cuda.is_available())"
```

### Model Loading Issues
```bash
# Check disk space
df -h

# Check model download progress
python3 -c "
from transformers import AutoProcessor
processor = AutoProcessor.from_pretrained('mistralai/Voxtral-Mini-3B-2507')
"
```

### Memory Issues
```bash
# Monitor GPU memory
watch -n 1 nvidia-smi

# Clear GPU cache
python3 -c "
import torch
torch.cuda.empty_cache()
"
```

### Port Already in Use
```bash
# Find process using port 8080
sudo lsof -i :8080

# Kill process
sudo kill -9 <PID>
```

## 📈 Performance Monitoring

### GPU Monitoring
```bash
# Real-time GPU stats
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv -l 1

# Temperature monitoring
nvidia-smi --query-gpu=temperature.gpu --format=csv -l 1
```

### Server Monitoring
```bash
# Check server health
curl http://localhost:8080/health

# Monitor logs
tail -f logs/voxtral_server.log

# System resources
htop
```

## 🛡️ Security

### Production Security Recommendations

1. **Firewall Configuration**:
```bash
# Allow only necessary ports
sudo ufw allow 22    # SSH
sudo ufw allow 8080  # Voxtral Server
sudo ufw enable
```

2. **Reverse Proxy (nginx)**:
```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

3. **SSL/TLS**:
```bash
# Use Let's Encrypt for HTTPS
sudo certbot --nginx -d your-domain.com
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- **Mistral AI** for the Voxtral-Mini-3B model
- **Hugging Face** for the Transformers library
- **NVIDIA** for CUDA and GPU acceleration
- **FastAPI** team for the excellent web framework

## 📞 Support

For issues and questions:
1. Check the troubleshooting section
2. Review the logs
3. Open an issue on GitHub
4. Check the API documentation at `/docs`

---

🎉 **Happy Transcribing!** 🎉
