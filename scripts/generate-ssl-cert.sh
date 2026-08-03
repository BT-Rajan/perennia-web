#!/bin/bash

# Generate self-signed SSL certificates for Perennia Web HTTPS

CERT_DIR="certs"
CERT_FILE="$CERT_DIR/server.crt"
KEY_FILE="$CERT_DIR/server.key"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Generate Self-Signed SSL Certificate for HTTPS (Port 443) ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Create certs directory
mkdir -p "$CERT_DIR"
echo "✓ Created $CERT_DIR directory"

# Check if certificates already exist
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo ""
    echo "⚠️  SSL certificates already exist:"
    echo "  Certificate: $CERT_FILE"
    echo "  Key: $KEY_FILE"
    echo ""
    read -p "Regenerate? (y/N): " regenerate
    if [ "$regenerate" != "y" ] && [ "$regenerate" != "Y" ]; then
        echo "Keeping existing certificates."
        exit 0
    fi
fi

echo ""
echo "Generating 4096-bit RSA key and self-signed certificate..."
echo "Certificate valid for 365 days (1 year)"
echo ""

# Generate self-signed certificate (valid for 1 year)
openssl req -x509 \
    -newkey rsa:4096 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days 365 \
    -nodes \
    -subj "/CN=perennia.local/O=Perennia/C=US"

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ SSL Certificate generated successfully!"
    echo ""
    echo "Certificate: $CERT_FILE"
    echo "Key: $KEY_FILE"
    echo ""
    echo "Certificate Details:"
    openssl x509 -in "$CERT_FILE" -noout -text | grep -E "Subject:|Issuer:|Not Before|Not After|Public-Key"
    echo ""
    echo "To verify:"
    echo "  openssl x509 -in $CERT_FILE -noout -text"
    echo ""
    echo "⚠️  Self-signed certificate warning:"
    echo "  Browsers will show security warnings for self-signed certificates."
    echo "  This is normal for development. Use a trusted CA in production."
    echo ""
    echo "Ready to start HTTPS server:"
    echo "  python3 start-https.py"
    echo ""
else
    echo "❌ Failed to generate SSL certificate"
    exit 1
fi
