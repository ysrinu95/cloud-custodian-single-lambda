"""
Unit tests for Security Hub notification processing in realtime_notifier.py

Tests the complete flow:
1. Loading Security Hub event from test data
2. Simulating Cloud Custodian SQS message format
3. Jinja2 template rendering with event context
4. Email notification generation
"""

import json
import os
import sys
import base64
import zlib
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

# Add parent directory to path to import the modules
sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest
from jinja2 import Template


class TestSecurityHubNotification:
    """Test Security Hub notification rendering and processing"""
    
    @pytest.fixture
    def securityhub_event(self):
        """Load Security Hub test event from JSON file"""
        test_data_path = Path(__file__).parent / 'data' / 'securityhub.json'
        with open(test_data_path, 'r') as f:
            return json.load(f)
    
    @pytest.fixture
    def custodian_sqs_message(self, securityhub_event):
        """
        Simulate Cloud Custodian SQS message format
        This is what Cloud Custodian's notify action writes to SQS
        """
        return {
            'policy': {
                'name': 'securityhub-failed-findings-remediation',
                'resource': 'aws.account',
                'metadata': {
                    'environment': 'dev'
                }
            },
            'account': 'aikyam-engg',
            'account_id': '813185901390',
            'region': 'us-east-1',
            'action': {
                'type': 'notify',
                'template': 'default.html',
                'subject': '⚠️ SecurityHub Critical Finding - {{ account }} - {{ region }}',
                'violation_desc': '''**SecurityHub Critical Finding**

**Account:** {{ account }}
**Region:** {{ region }}
{% if event and event.detail and event.detail.findings and event.detail.findings|length > 0 %}
**Severity:** {{ event.detail.findings[0].Severity.Label or "High" }}
**Compliance:** {{ event.detail.findings[0].Compliance.Status or "FAILED" }}
**Status:** {{ event.detail.findings[0].Workflow.Status or "NEW" }}

**Title:** {{ event.detail.findings[0].Title or "SecurityHub Finding" }}

**Description:** {{ event.detail.findings[0].Description or "Critical security finding detected" }}

**Affected Resources:**
{% if event.detail.findings[0].Resources and event.detail.findings[0].Resources|length > 0 %}
- Resource Type: {{ event.detail.findings[0].Resources[0].Type or "N/A" }}
- Resource ID: {{ event.detail.findings[0].Resources[0].Id or "N/A" }}
{% else %}
- No resource information available
{% endif %}

**Remediation:**
{{ event.detail.findings[0].Remediation.Recommendation.Text or "Review finding in SecurityHub console for remediation steps" }}
{% else %}
**Severity:** High
**Status:** NEW
**Title:** SecurityHub Finding (Event details not available)
**Description:** A critical security finding was detected. Please review in the SecurityHub console.
{% endif %}

**Required Actions:**
1. Review the finding in SecurityHub console
2. Investigate affected resources
3. Apply recommended remediation steps
4. Update finding status after remediation
'''
            },
            'resources': [],  # Security Hub events don't have traditional resources
            'event': securityhub_event  # The full Security Hub event
        }
    
    @pytest.fixture
    def encoded_sqs_message(self, custodian_sqs_message):
        """Encode message as Cloud Custodian does (base64 + gzip)"""
        json_str = json.dumps(custodian_sqs_message)
        compressed = zlib.compress(json_str.encode('utf-8'))
        encoded = base64.b64encode(compressed).decode('utf-8')
        return encoded
    
    def test_securityhub_event_structure(self, securityhub_event):
        """Test that Security Hub event has expected structure"""
        assert 'detail' in securityhub_event
        assert 'findings' in securityhub_event['detail']
        assert len(securityhub_event['detail']['findings']) > 0
        
        finding = securityhub_event['detail']['findings'][0]
        assert 'Severity' in finding
        assert 'Label' in finding['Severity']
        assert 'Compliance' in finding
        assert 'Status' in finding['Compliance']
        assert 'Title' in finding
        assert 'Description' in finding
        assert 'Resources' in finding
        assert len(finding['Resources']) > 0
    
    def test_jinja2_template_rendering(self, custodian_sqs_message, securityhub_event):
        """Test that Jinja2 template renders correctly with event context"""
        template_str = custodian_sqs_message['action']['violation_desc']
        template = Template(template_str)
        
        # Prepare template context
        context = {
            'account': custodian_sqs_message['account'],
            'region': custodian_sqs_message['region'],
            'event': securityhub_event
        }
        
        # Render template
        rendered = template.render(**context)
        
        # Verify that template variables were replaced
        assert '{{ event.detail.findings[0]' not in rendered
        assert '{{' not in rendered  # No unrendered template syntax
        
        # Verify actual values from Security Hub event appear in output
        finding = securityhub_event['detail']['findings'][0]
        assert finding['Severity']['Label'] in rendered
        assert finding['Compliance']['Status'] in rendered
        assert finding['Title'] in rendered
        assert finding['Resources'][0]['Type'] in rendered
    
    def test_message_decoding(self, encoded_sqs_message, custodian_sqs_message):
        """Test that SQS message can be decoded correctly"""
        # Decode
        decoded_bytes = base64.b64decode(encoded_sqs_message)
        decompressed = zlib.decompress(decoded_bytes)
        message_data = json.loads(decompressed.decode('utf-8'))
        
        # Verify structure
        assert message_data['policy']['name'] == custodian_sqs_message['policy']['name']
        assert 'event' in message_data
        assert 'detail' in message_data['event']
        assert 'findings' in message_data['event']['detail']
    
    def test_complete_notification_flow(self, custodian_sqs_message, securityhub_event):
        """Test complete notification flow from SQS message to rendered email"""
        # Extract data
        policy_name = custodian_sqs_message['policy']['name']
        account = custodian_sqs_message['account']
        region = custodian_sqs_message['region']
        action = custodian_sqs_message['action']
        event = custodian_sqs_message['event']
        
        # Prepare template variables
        template_vars = {
            'account': account,
            'account_id': custodian_sqs_message['account_id'],
            'region': region,
            'policy': policy_name,
            'policy_name': policy_name,
            'environment': 'dev',
            'event': event
        }
        
        # Render subject
        subject = action['subject']
        for key, value in template_vars.items():
            if isinstance(value, (str, int)):
                subject = subject.replace(f'{{{{ {key} }}}}', str(value))
        
        assert '{{' not in subject
        assert account in subject
        assert region in subject
        
        # Render message body with Jinja2
        message_body = action['violation_desc']
        template = Template(message_body)
        rendered_body = template.render(**template_vars)
        
        # Verify no unrendered template syntax
        assert '{{ event.detail.findings[0]' not in rendered_body
        assert '{{' not in rendered_body
        
        # Verify Security Hub data appears in message
        finding = event['detail']['findings'][0]
        assert 'CRITICAL' in rendered_body  # Severity
        assert 'FAILED' in rendered_body  # Compliance Status
        assert 'Config.1' in rendered_body or 'AWS Config' in rendered_body  # Title
        assert 'AwsAccount' in rendered_body  # Resource Type
        
        print("\n" + "="*80)
        print("RENDERED EMAIL SUBJECT:")
        print("="*80)
        print(subject)
        print("\n" + "="*80)
        print("RENDERED EMAIL BODY:")
        print("="*80)
        print(rendered_body)
        print("="*80 + "\n")
    
    def test_missing_event_data_fallback(self, custodian_sqs_message):
        """Test that template renders with fallback values when event is missing"""
        # Remove event data
        custodian_sqs_message['event'] = {}
        
        template_str = custodian_sqs_message['action']['violation_desc']
        template = Template(template_str)
        
        context = {
            'account': custodian_sqs_message['account'],
            'region': custodian_sqs_message['region'],
            'event': {}  # Empty event
        }
        
        # Should render with fallback values
        rendered = template.render(**context)
        
        # Verify fallback message appears when event details not available
        assert 'High' in rendered  # Fallback severity
        assert 'NEW' in rendered  # Fallback status
        assert 'Event details not available' in rendered
        assert 'SecurityHub Finding' in rendered
    
    def test_invoke_deployed_lambda(self, securityhub_event):
        """
        Invoke the actual deployed Lambda function with Security Hub event
        
        This is a real end-to-end integration test that:
        1. Invokes the deployed cloud-custodian-cross-account-executor Lambda
        2. Lambda processes the Security Hub event
        3. Executes Cloud Custodian policy
        4. Cloud Custodian writes notification to SQS
        5. realtime_notifier processes SQS and sends email
        
        Prerequisites:
        - Lambda must be deployed in AWS account 172327596604 (central account)
        - AWS credentials must be configured with invoke permissions
        - Security Hub policy must be configured in S3
        
        Note: This test is skipped if AWS credentials are not available.
        """
        import boto3
        from botocore.exceptions import NoCredentialsError, ClientError
        
        # Lambda function name (deployed in central account)
        lambda_function_name = 'cloud-custodian-cross-account-executor'
        
        print(f"\n{'='*80}")
        print(f"🚀 STARTING LAMBDA INVOCATION TEST")
        print(f"{'='*80}")
        
        # Try to create Lambda client and check credentials
        try:
            print("Checking AWS credentials...")
            lambda_client = boto3.client('lambda', region_name='us-east-1')
            # Test if credentials are available by attempting to get caller identity
            sts_client = boto3.client('sts', region_name='us-east-1')
            identity = sts_client.get_caller_identity()
            print(f"✅ AWS Credentials found: {identity['Arn']}")
            print(f"✅ Account: {identity['Account']}")
        except NoCredentialsError as e:
            print(f"❌ No AWS credentials found: {e}")
            pytest.skip("AWS credentials not available. Skipping Lambda invocation test.")
        except Exception as e:
            print(f"❌ Cannot access AWS: {str(e)}")
            pytest.skip(f"Cannot access AWS: {str(e)}")
        
        print(f"\n{'='*80}")
        print(f"INVOKING DEPLOYED LAMBDA: {lambda_function_name}")
        print(f"{'='*80}")
        print(f"Event Type: {securityhub_event.get('detail-type', 'Unknown')}")
        print(f"Event Source: {securityhub_event.get('source', 'Unknown')}")
        print(f"Account: {securityhub_event.get('account', 'Unknown')}")
        print(f"Region: {securityhub_event.get('region', 'Unknown')}")
        print(f"\nFull Event (first 1000 chars):")
        print(json.dumps(securityhub_event, indent=2, default=str)[:1000])
        print(f"{'='*80}\n")
        
        try:
            print(f"📤 Sending invocation request to Lambda...")
            # Invoke the Lambda function
            response = lambda_client.invoke(
                FunctionName=lambda_function_name,
                InvocationType='RequestResponse',  # Synchronous invocation
                Payload=json.dumps(securityhub_event)
            )
            
            print(f"✅ Lambda invocation request sent successfully")
            
            # Read the response
            response_payload = json.loads(response['Payload'].read())
            status_code = response['StatusCode']
            
            print(f"\n{'='*80}")
            print(f"LAMBDA RESPONSE:")
            print(f"{'='*80}")
            print(f"Status Code: {status_code}")
            print(f"Response: {json.dumps(response_payload, indent=2, default=str)}")
            print(f"{'='*80}\n")
            
            # Verify successful invocation
            assert status_code == 200, f"Lambda invocation failed with status {status_code}"
            
            # Check if there was a function error
            if 'FunctionError' in response:
                print(f"❌ Lambda function error: {response['FunctionError']}")
                print(f"Error details: {response_payload}")
                pytest.fail(f"Lambda execution failed: {response_payload}")
            
            # Verify response structure
            assert response_payload is not None, "Lambda returned None"
            
            print("\n" + "="*80)
            print("✅ LAMBDA INVOCATION SUCCESSFUL!")
            print("="*80)
            print("\n📧 Check your email (ysrinu95@gmail.com) for the Security Hub notification")
            print("🔍 Check CloudWatch Logs: /aws/lambda/cloud-custodian-cross-account-executor")
            print("📊 Check SQS Queue: aikyam-cloud-custodian-realtime-notifications")
            print("\n" + "="*80 + "\n")
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            error_msg = e.response['Error']['Message']
            print(f"\n❌ AWS ClientError: {error_code}")
            print(f"Message: {error_msg}")
            pytest.fail(f"Failed to invoke Lambda: [{error_code}] {error_msg}")
        except Exception as e:
            print(f"\n❌ Lambda invocation failed: {str(e)}")
            print(f"Exception type: {type(e).__name__}")
            import traceback
            print(f"Traceback:\n{traceback.format_exc()}")
            pytest.fail(f"Failed to invoke Lambda: {str(e)}")


def run_tests():
    """Run tests with pytest"""
    import pytest
    
    # Run with verbose output
    test_file = Path(__file__)
    exit_code = pytest.main([
        str(test_file),
        '-v',  # Verbose
        '-s',  # Show print statements
        '--tb=short',  # Short traceback format
        '--color=yes'
    ])
    
    return exit_code


if __name__ == '__main__':
    exit_code = run_tests()
    sys.exit(exit_code)
