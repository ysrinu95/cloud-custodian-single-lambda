#!/bin/bash
# Alternative mailer deployment with custom Lambda packaging

config=config/mailer.yml
templates_dir=config/mailer-templates

echo "🔧 Alternative mailer deployment with custom packaging..."

# Create a temporary directory for custom packaging
temp_dir=$(mktemp -d)
echo "📁 Using temporary directory: $temp_dir"

# Install dependencies in a clean environment
echo "📦 Installing dependencies in isolated environment..."
pip install --target $temp_dir PyJWT>=2.0.0 cryptography>=3.0.0 requests>=2.25.0
pip install --target $temp_dir c7n-mailer>=0.6.20 --no-deps

# Verify the installation
echo "🔍 Verifying PyJWT in package..."
PYTHONPATH=$temp_dir python -c "import jwt; print(f'✅ PyJWT {jwt.__version__} available in package')" || echo "❌ PyJWT not available in package"

# Try standard deployment first
echo "📧 Attempting standard c7n-mailer deployment..."
c7n-mailer --config $config -t $templates_dir --update-lambda

# If that fails, we may need to manually update the Lambda
if [ $? -ne 0 ]; then
    echo "⚠️ Standard deployment failed, manual Lambda update may be required"
    echo "💡 Consider manually updating the Lambda function with the required dependencies"
fi

# Cleanup
echo "🧹 Cleaning up temporary directory..."
rm -rf $temp_dir

echo "✅ Alternative deployment attempt complete"