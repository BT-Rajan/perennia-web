#!/usr/bin/env python3
"""
Perennia Web - HTTPS Startup Script
Runs on port 443 with SSL/TLS certificates
"""
import os
import sys
import uvicorn
from pathlib import Path

# Ensure we're in the right directory
PROJECT_DIR = Path(__file__).resolve().parent
os.chdir(PROJECT_DIR)

# Import app
from app.main import app
from app.config import settings

# Get settings from config
SSL_CERT_FILE = settings.SSL_CERT_FILE
SSL_KEY_FILE = settings.SSL_KEY_FILE
PORT = settings.PORT
HOST = settings.HOST

# Check if SSL certificates exist
if not os.path.exists(SSL_CERT_FILE):
    print(f"❌ SSL certificate not found: {SSL_CERT_FILE}")
    print("Generate certificates with:")
    print("  mkdir -p certs")
    print("  openssl req -x509 -newkey rsa:4096 -keyout certs/server.key -out certs/server.crt -days 365 -nodes")
    sys.exit(1)

if not os.path.exists(SSL_KEY_FILE):
    print(f"❌ SSL key not found: {SSL_KEY_FILE}")
    print("Generate certificates with:")
    print("  mkdir -p certs")
    print("  openssl req -x509 -newkey rsa:4096 -keyout certs/server.key -out certs/server.crt -days 365 -nodes")
    sys.exit(1)

print("=" * 70)
print("PERENNIA WEB - HTTPS Server")
print("=" * 70)
print(f"Host: {HOST}")
print(f"Port: {PORT}")
print(f"SSL Certificate: {SSL_CERT_FILE}")
print(f"SSL Key: {SSL_KEY_FILE}")
print(f"URL: https://{HOST if HOST != '0.0.0.0' else 'localhost'}:{PORT}")
print("=" * 70)
print("")

# Run uvicorn with HTTPS
uvicorn.run(
    app,
    host=HOST,
    port=PORT,
    ssl_keyfile=SSL_KEY_FILE,
    ssl_certfile=SSL_CERT_FILE,
    ssl_version=17,  # TLS 1.2+
    log_level="info",
)
