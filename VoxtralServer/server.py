#!/usr/bin/env python3
"""
Voxtral Transcription Server

A FastAPI-based web server that provides transcription services
using the Voxtral-Mini-3B model. Optimized for NVIDIA GPUs.
"""

import os
import sys
import logging
import tempfile
import traceback
from typing import Optional, Dict, Any
from pathlib import Path

import torch
from fastapi import FastAPI, HTTPException, UploadFile, File, Request
from fastapi.responses import JSONResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

# Import Voxtral components
try:
    from transformers import VoxtralForConditionalGeneration, AutoProcessor
    print("✅ Successfully imported Voxtral components")
except ImportError as e:
    print(f"❌ Failed to import Voxtral components: {e}")
    print("Please install required packages with: pip install transformers torch fastapi uvicorn")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('voxtral_server.log')
    ]
)
logger = logging.getLogger(__name__)

# Global variables for model and processor
model = None
processor = None
device = None

class TranscriptionRequest(BaseModel):
    """Request model for transcription"""
    language: Optional[str] = "en"
    model_id: Optional[str] = "mistralai/Voxtral-Mini-3B-2507"

class TranscriptionResponse(BaseModel):
    """Response model for transcription"""
    text: str
    language: str
    processing_time: float

class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    model_loaded: bool
    device: str
    gpu_available: bool

# Initialize FastAPI app
app = FastAPI(
    title="Voxtral Transcription Server",
    description="High-performance transcription server using Voxtral-Mini-3B",
    version="1.0.0"
)

# Add CORS middleware for web app access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for local development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def initialize_model():
    """Initialize the Voxtral model and processor"""
    global model, processor, device
    
    try:
        logger.info("🚀 Initializing Voxtral model...")
        
        # Check for CUDA availability
        if torch.cuda.is_available():
            device = "cuda"
            gpu_name = torch.cuda.get_device_name(0)
            gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3  # GB
            logger.info(f"🎮 GPU detected: {gpu_name} with {gpu_memory:.1f}GB VRAM")
        else:
            device = "cpu"
            logger.warning("⚠️ No CUDA GPU detected, using CPU (will be slow)")
        
        repo_id = "mistralai/Voxtral-Mini-3B-2507"
        
        logger.info(f"📥 Loading processor from {repo_id}...")
        processor = AutoProcessor.from_pretrained(repo_id)
        
        logger.info(f"🧠 Loading model from {repo_id}...")
        model = VoxtralForConditionalGeneration.from_pretrained(
            repo_id, 
            torch_dtype=torch.bfloat16, 
            device_map=device
        )
        
        logger.info("✅ Model and processor loaded successfully!")
        return True
        
    except Exception as e:
        logger.error(f"❌ Failed to initialize model: {e}")
        logger.error(traceback.format_exc())
        return False

@app.on_event("startup")
async def startup_event():
    """Initialize model on server startup"""
    logger.info("🌟 Starting Voxtral Transcription Server...")
    
    if not initialize_model():
        logger.error("Failed to initialize model on startup")
        # Don't exit, allow health checks to report the issue
    
    logger.info("🚀 Server startup complete!")

@app.get("/", response_class=PlainTextResponse)
async def root():
    """Root endpoint with server info"""
    return """Voxtral Transcription Server v1.0.0

Endpoints:
- GET  /health          - Health check
- POST /transcribe     - Transcribe audio (WAV file)
- GET  /docs           - API documentation

Send POST requests to /transcribe with WAV audio data for transcription."""

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    try:
        return HealthResponse(
            status="healthy" if model is not None else "unhealthy",
            model_loaded=model is not None,
            device=device or "unknown",
            gpu_available=torch.cuda.is_available()
        )
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/transcribe", response_model=TranscriptionResponse)
async def transcribe_audio(
    request: Request,
    file: UploadFile = File(...),
    language: str = "en",
    model_id: str = "mistralai/Voxtral-Mini-3B-2507"
):
    """
    Transcribe audio file using Voxtral model
    
    Accepts WAV audio data and returns transcription
    """
    import time
    start_time = time.time()
    
    if model is None or processor is None:
        logger.error("Model not initialized")
        raise HTTPException(status_code=503, detail="Model not loaded. Please check server logs.")
    
    try:
        logger.info(f"🎵 Received transcription request for file: {file.filename}")
        logger.info(f"🌍 Language: {language}, Model: {model_id}")
        
        # Read uploaded file
        audio_data = await file.read()
        logger.info(f"📊 Received {len(audio_data)} bytes of audio data")
        
        # Save to temporary file for processing
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_file:
            temp_file.write(audio_data)
            temp_file_path = temp_file.name
        
        try:
            logger.info("🔄 Processing audio with Voxtral...")
            
            # Prepare transcription request
            inputs = processor.apply_transcription_request(
                language=language,
                audio=temp_file_path,
                model_id=model_id
            )
            
            # Move to device and set dtype
            inputs = inputs.to(device, dtype=torch.bfloat16)
            
            logger.info("🧠 Generating transcription...")
            
            # Generate transcription
            with torch.no_grad():
                outputs = model.generate(**inputs, max_new_tokens=500)
            
            # Decode the outputs
            decoded_outputs = processor.batch_decode(
                outputs[:, inputs.input_ids.shape[1]:], 
                skip_special_tokens=True
            )
            
            # Extract the transcription text
            if decoded_outputs:
                transcription = decoded_outputs[0].strip()
            else:
                transcription = ""
            
            processing_time = time.time() - start_time
            
            logger.info(f"✅ Transcription completed in {processing_time:.2f}s")
            logger.info(f"📝 Transcription: {transcription[:100]}...")
            
            return TranscriptionResponse(
                text=transcription,
                language=language,
                processing_time=processing_time
            )
            
        finally:
            # Clean up temporary file
            if os.path.exists(temp_file_path):
                os.unlink(temp_file_path)
                
    except Exception as e:
        logger.error(f"❌ Transcription failed: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

@app.post("/transcribe-json")
async def transcribe_audio_json(
    request: Request,
    file: UploadFile = File(...),
    language: str = "en",
    model_id: str = "mistralai/Voxtral-Mini-3B-2507"
):
    """
    Alternative endpoint that returns simple JSON format
    """
    try:
        result = await transcribe_audio(request, file, language, model_id)
        return JSONResponse(content={"text": result.text})
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"JSON transcription failed: {e}")
        return JSONResponse(content={"error": str(e)}, status_code=500)

if __name__ == "__main__":
    # Parse command line arguments
    import argparse
    
    parser = argparse.ArgumentParser(description="Voxtral Transcription Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=8080, help="Port to bind to")
    parser.add_argument("--reload", action="store_true", help="Enable auto-reload for development")
    parser.add_argument("--log-level", default="info", choices=["debug", "info", "warning", "error"])
    
    args = parser.parse_args()
    
    # Set log level
    logging.getLogger().setLevel(getattr(logging, args.log_level.upper()))
    
    logger.info(f"🚀 Starting Voxtral server on {args.host}:{args.port}")
    logger.info(f"🔧 Settings: reload={args.reload}, log_level={args.log_level}")
    
    # Run the server
    uvicorn.run(
        "server:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level=args.log_level
    )
