#!/bin/bash
# Post-deployment fix for c7n-mailer Lambda PyJWT dependency

LAMBDA_FUNCTION_NAME="cloud-custodian-mailer"
REGION="us-west-2"

echo "🔧 Post-deployment fix for c7n-mailer Lambda..."

# Create a temporary directory for dependency packaging
temp_dir=$(mktemp -d)
echo "📁 Using temporary directory: $temp_dir"

# Download the current Lambda function
echo "⬇️ Downloading current Lambda function..."
aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $REGION --query 'Code.Location' --output text > lambda_url.txt
curl -o $temp_dir/function.zip $(cat lambda_url.txt)

# Extract the function
echo "📦 Extracting Lambda function..."
cd $temp_dir
unzip -q function.zip

# Install PyJWT and other missing dependencies
echo "📦 Installing missing dependencies..."
pip install --target . PyJWT>=2.0.0 cryptography>=3.0.0 requests>=2.25.0

# Verify PyJWT is installed
echo "🔍 Verifying PyJWT installation..."
python -c "import jwt; print(f'✅ PyJWT {jwt.__version__} installed')" || echo "❌ PyJWT not available"

# Repackage the function
echo "📦 Repackaging Lambda function..."
zip -rq function-updated.zip .

# Update the Lambda function
echo "⬆️ Updating Lambda function..."
aws lambda update-function-code --function-name $LAMBDA_FUNCTION_NAME --region $REGION --zip-file fileb://function-updated.zip

# Test the function
echo "🧪 Testing Lambda function..."
aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME --region $REGION --payload '{}' response.json
cat response.json

# Cleanup
echo "🧹 Cleaning up..."
cd - > /dev/null
rm -rf $temp_dir
rm -f lambda_url.txt

echo "✅ Post-deployment fix complete"