"""
Simplified Lambda handler using Cloud Custodian packages directly
This demonstrates the most straightforward way to execute policies using c7n library
"""

import json
import logging
import tempfile
import yaml
from c7n.config import Config
from c7n.policy import PolicyCollection

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """
    Simple Lambda handler that executes Cloud Custodian policies directly
    using the c7n Python packages - NO CLI needed!
    """
    
    # Define policy inline (or load from file/S3)
    policy_config = {
        'policies': [
            {
                'name': 'find-running-ec2',
                'resource': 'ec2',
                'description': 'Find all running EC2 instances',
                'filters': [
                    {'type': 'value', 'key': 'State.Name', 'value': 'running'}
                ]
            },
            {
                'name': 's3-without-encryption',
                'resource': 's3',
                'description': 'Find S3 buckets without encryption',
                'filters': [
                    {'type': 'bucket-encryption', 'state': False}
                ]
            }
        ]
    }
    
    # Can also load from file packaged with Lambda
    # with open('/var/task/policies/sample-policies.yml', 'r') as f:
    #     policy_config = yaml.safe_load(f)
    
    try:
        # Create temporary output directory
        with tempfile.TemporaryDirectory() as output_dir:
            
            # Create Cloud Custodian configuration
            config = Config.empty(
                region=event.get('region', 'us-east-1'),
                output_dir=output_dir,
                dryrun=event.get('dryrun', False),
                log_group=None,
                metrics_enabled=False
            )
            
            # Load policies from configuration
            policies = PolicyCollection.from_data(policy_config, config)
            
            logger.info(f"Loaded {len(policies)} policies")
            
            # Execute each policy directly using c7n library
            results = {}
            for policy in policies:
                logger.info(f"Executing policy: {policy.name}")
                
                # Run the policy - this calls c7n's Python code directly!
                resources = policy.run()
                
                results[policy.name] = {
                    'resource_count': len(resources),
                    'resources': [r.get('id', r.get('InstanceId', 'unknown')) for r in resources[:10]]  # First 10
                }
                
                logger.info(f"Policy '{policy.name}' found {len(resources)} resources")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Policies executed successfully using c7n library',
                    'results': results
                })
            }
    
    except Exception as e:
        logger.error(f"Error executing policies: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }


# Example of executing a single policy directly
def execute_single_policy_example():
    """
    Example: Execute a single policy programmatically
    This shows how simple it is to use c7n as a library!
    """
    
    # Define your policy
    policy_yaml = """
    policies:
      - name: my-ec2-policy
        resource: ec2
        filters:
          - type: value
            key: State.Name
            value: running
        actions:
          - type: tag
            key: Scanned
            value: CloudCustodian
    """
    
    policy_data = yaml.safe_load(policy_yaml)
    
    with tempfile.TemporaryDirectory() as output_dir:
        # Create config
        config = Config.empty(
            region='us-east-1',
            output_dir=output_dir,
            dryrun=True  # Safe mode - no actual changes
        )
        
        # Load and execute
        policies = PolicyCollection.from_data(policy_data, config)
        
        for p in policies:
            resources = p.run()  # Direct execution - no CLI!
            print(f"Found {len(resources)} resources")
            
            # Access resources directly
            for resource in resources:
                print(f"  - {resource.get('InstanceId')}")


if __name__ == '__main__':
    # Test locally
    test_event = {
        'region': 'us-east-1',
        'dryrun': True
    }
    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))
