#!/bin/bash

# Build script for Cloud Custodian Lambda Layer
# This script creates a Lambda layer with Cloud Custodian and its dependencies

set -e

# Configuration
PYTHON_VERSION="3.11"
LAYER_NAME="cloud-custodian-layer"
LAYER_DIR="layers"
BUILD_DIR="${LAYER_DIR}/python/lib/python${PYTHON_VERSION}/site-packages"

echo "======================================"
echo "Building Cloud Custodian Lambda Layer"
echo "======================================"

# Clean up previous builds
echo "Cleaning up previous builds..."
rm -rf ${LAYER_DIR}
rm -f ${LAYER_NAME}.zip

# Create layer directory structure
echo "Creating layer directory structure..."
mkdir -p ${BUILD_DIR}

# Install dependencies
echo "Installing Cloud Custodian and dependencies..."
pip install --upgrade pip
pip install -r requirements.txt -t ${BUILD_DIR}

# Remove unnecessary files to reduce size
echo "Removing unnecessary files..."
cd ${BUILD_DIR}

# Remove test files
find . -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# Remove Python cache files
find . -name "*.pyc" -delete
find . -name "*.pyo" -delete

# Remove distribution info
find . -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

# Remove boto3 and botocore (already in Lambda runtime)
rm -rf boto3* botocore* 2>/dev/null || true

# Remove documentation and examples
find . -name "*.md" -delete 2>/dev/null || true
find . -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true

cd ../../../../../../

# Create zip file
echo "Creating layer zip file..."
cd ${LAYER_DIR}
zip -r ../${LAYER_NAME}.zip python/ -q
cd ..

mv ${LAYER_NAME}.zip ${LAYER_DIR}/

# Check size
SIZE=$(du -h ${LAYER_DIR}/${LAYER_NAME}.zip | cut -f1)
SIZE_MB=$(du -m ${LAYER_DIR}/${LAYER_NAME}.zip | cut -f1)

echo ""
echo "======================================"
echo "Build completed successfully!"
echo "======================================"
echo "Layer file: ${LAYER_DIR}/${LAYER_NAME}.zip"
echo "Size: ${SIZE} (${SIZE_MB}MB)"
echo ""

if [ ${SIZE_MB} -gt 250 ]; then
    echo "⚠️  WARNING: Layer size exceeds 250MB!"
    echo "    Lambda has a 250MB limit for unzipped layers."
    echo "    Consider further optimization or use a container image."
else
    echo "✓ Layer size is within Lambda limits"
fi

echo ""
echo "Next steps:"
echo "1. Test the layer locally (see scripts/test_layer.sh)"
echo "2. Deploy with Terraform: cd terraform && terraform apply"
echo "3. Or upload manually to AWS Lambda"
