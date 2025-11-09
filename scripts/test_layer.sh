#!/bin/bash

# Test script for Cloud Custodian Lambda Layer
# This script tests the layer locally before deployment

set -e

echo "======================================"
echo "Testing Cloud Custodian Lambda Layer"
echo "======================================"

# Check if layer exists
if [ ! -f "layers/cloud-custodian-layer.zip" ]; then
    echo "Error: Layer file not found. Run ./scripts/build_layer.sh first"
    exit 1
fi

# Create test environment
TEST_DIR="test_env"
echo "Creating test environment..."
rm -rf ${TEST_DIR}
mkdir -p ${TEST_DIR}

# Extract layer
echo "Extracting layer..."
unzip -q layers/cloud-custodian-layer.zip -d ${TEST_DIR}

# Test imports
echo "Testing Cloud Custodian imports..."
PYTHONPATH="${TEST_DIR}/python/lib/python3.11/site-packages:$PYTHONPATH" python3 << EOF
import sys
try:
    import c7n
    print(f"✓ c7n imported successfully (version: {c7n.__version__})")
    
    from c7n.config import Config
    print("✓ c7n.config imported")
    
    from c7n.policy import PolicyCollection
    print("✓ c7n.policy imported")
    
    import yaml
    print("✓ yaml imported")
    
    print("\nAll imports successful!")
    sys.exit(0)
except ImportError as e:
    print(f"✗ Import failed: {e}")
    sys.exit(1)
EOF

# Test simple policy execution
echo ""
echo "Testing policy execution..."
cat > ${TEST_DIR}/test_policy.yml << 'EOF'
policies:
  - name: test-policy
    resource: ec2
    description: Test policy for local validation
    filters:
      - type: value
        key: State.Name
        value: running
EOF

PYTHONPATH="${TEST_DIR}/python/lib/python3.11/site-packages:$PYTHONPATH" python3 << 'EOF'
import sys
import tempfile
import yaml
from c7n.config import Config
from c7n.policy import PolicyCollection

try:
    # Load test policy
    with open('test_env/test_policy.yml', 'r') as f:
        policy_data = yaml.safe_load(f)
    
    # Create config
    with tempfile.TemporaryDirectory() as output_dir:
        config = Config.empty(
            region='us-east-1',
            output_dir=output_dir,
            dryrun=True
        )
        
        # Load policies
        policies = PolicyCollection.from_data(policy_data, config)
        print(f"✓ Loaded {len(policies)} policies")
        
        for p in policies:
            print(f"  - {p.name}: {p.resource_type}")
    
    print("\nPolicy validation successful!")
    sys.exit(0)
except Exception as e:
    print(f"✗ Policy test failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF

# Clean up
echo ""
echo "Cleaning up test environment..."
rm -rf ${TEST_DIR}

echo ""
echo "======================================"
echo "All tests passed successfully! ✓"
echo "======================================"
echo "Layer is ready for deployment"
