#!/usr/bin/env python3
"""
Test client for Voxtral Transcription Server
"""

import requests
import json
import sys
import time
from pathlib import Path

def test_server_health(base_url="http://localhost:8080"):
    """Test server health endpoint"""
    print("🏥 Testing server health...")
    try:
        response = requests.get(f"{base_url}/health", timeout=10)
        if response.status_code == 200:
            health_data = response.json()
            print(f"✅ Server is healthy!")
            print(f"   Status: {health_data['status']}")
            print(f"   Model loaded: {health_data['model_loaded']}")
            print(f"   Device: {health_data['device']}")
            print(f"   GPU available: {health_data['gpu_available']}")
            return True
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Health check failed: {e}")
        return False

def create_test_wav():
    """Create a simple silent WAV file for testing"""
    import struct
    import tempfile
    
    # Create a minimal silent WAV file (44.1kHz, 16-bit, mono, 1 second)
    sample_rate = 44100
    duration = 1.0
    channels = 1
    bits_per_sample = 16
    
    num_samples = int(sample_rate * duration)
    data_size = num_samples * channels * bits_per_sample // 8
    byte_rate = sample_rate * channels * bits_per_sample // 8
    block_align = channels * bits_per_sample // 8
    
    # WAV header
    header = struct.pack('<4sL4s', b'RIFF', 36 + data_size, b'WAVE')
    fmt_chunk = struct.pack('<4sLHHLLHH', 
                           b'fmt ', 16, 1, channels, sample_rate, 
                           byte_rate, block_align, bits_per_sample)
    data_header = struct.pack('<4sL', b'data', data_size)
    
    # Silent audio data (zeros)
    audio_data = b'\x00' * data_size
    
    wav_data = header + fmt_chunk + data_header + audio_data
    
    # Save to temporary file
    temp_file = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
    temp_file.write(wav_data)
    temp_file.close()
    
    return temp_file.name

def test_transcription(base_url="http://localhost:8080"):
    """Test transcription endpoint"""
    print("\n🎵 Testing transcription endpoint...")
    
    # Create test WAV file
    wav_file = create_test_wav()
    
    try:
        with open(wav_file, 'rb') as f:
            files = {'file': ('test.wav', f, 'audio/wav')}
            data = {'language': 'en'}
            
            print("📤 Sending test audio file...")
            start_time = time.time()
            
            response = requests.post(
                f"{base_url}/transcribe",
                files=files,
                data=data,
                timeout=60  # Longer timeout for transcription
            )
            
            elapsed_time = time.time() - start_time
            
            if response.status_code == 200:
                result = response.json()
                print(f"✅ Transcription successful!")
                print(f"   Processing time: {result['processing_time']:.2f}s")
                print(f"   Language: {result['language']}")
                print(f"   Transcription: '{result['text']}'")
                return True
            else:
                print(f"❌ Transcription failed: {response.status_code}")
                print(f"   Response: {response.text}")
                return False
                
    except Exception as e:
        print(f"❌ Transcription test failed: {e}")
        return False
    finally:
        # Clean up temporary file
        try:
            Path(wav_file).unlink()
        except:
            pass

def test_json_endpoint(base_url="http://localhost:8080"):
    """Test the JSON transcription endpoint"""
    print("\n📝 Testing JSON transcription endpoint...")
    
    wav_file = create_test_wav()
    
    try:
        with open(wav_file, 'rb') as f:
            files = {'file': ('test.wav', f, 'audio/wav')}
            data = {'language': 'en'}
            
            print("📤 Sending test audio file to JSON endpoint...")
            
            response = requests.post(
                f"{base_url}/transcribe-json",
                files=files,
                data=data,
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                print(f"✅ JSON transcription successful!")
                print(f"   Response: {result}")
                return True
            else:
                print(f"❌ JSON transcription failed: {response.status_code}")
                print(f"   Response: {response.text}")
                return False
                
    except Exception as e:
        print(f"❌ JSON transcription test failed: {e}")
        return False
    finally:
        try:
            Path(wav_file).unlink()
        except:
            pass

def main():
    base_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"
    
    print("🧪 Voxtral Server Test Suite")
    print("=" * 40)
    print(f"🌐 Testing server at: {base_url}")
    print("")
    
    # Test server health
    if not test_server_health(base_url):
        print("\n❌ Server health check failed. Please ensure the server is running.")
        sys.exit(1)
    
    # Wait a moment for model to be fully loaded
    print("\n⏳ Waiting for model to be ready...")
    time.sleep(2)
    
    # Test transcription endpoints
    success_count = 0
    total_tests = 2
    
    if test_transcription(base_url):
        success_count += 1
    
    if test_json_endpoint(base_url):
        success_count += 1
    
    print("\n" + "=" * 40)
    print(f"📊 Test Results: {success_count}/{total_tests} tests passed")
    
    if success_count == total_tests:
        print("🎉 All tests passed! Server is ready to use.")
        print("\n🚀 You can now use the Voxtral Mini macOS app to transcribe audio!")
    else:
        print("❌ Some tests failed. Please check the server logs.")
        sys.exit(1)

if __name__ == "__main__":
    main()
