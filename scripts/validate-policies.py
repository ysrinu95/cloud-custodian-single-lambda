#!/usr/bin/env python3
"""
Cloud Custodian Policy Validator
Validates policy files for correct structure and common issues
"""

import yaml
import json
import sys
from pathlib import Path

def validate_yaml_file(file_path):
    """Validate YAML syntax"""
    try:
        with open(file_path, 'r') as f:
            data = yaml.safe_load(f)
        return True, data, None
    except yaml.YAMLError as e:
        return False, None, str(e)

def validate_json_file(file_path):
    """Validate JSON syntax"""
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
        return True, data, None
    except json.JSONDecodeError as e:
        return False, None, str(e)

def validate_policy_structure(policy_data):
    """Validate Cloud Custodian policy structure"""
    issues = []
    
    if not isinstance(policy_data, dict):
        issues.append("Root element must be a dictionary")
        return issues
    
    if 'policies' not in policy_data:
        issues.append("Missing 'policies' key at root level")
        return issues
    
    policies = policy_data['policies']
    if not isinstance(policies, list):
        issues.append("'policies' must be a list")
        return issues
    
    for idx, policy in enumerate(policies):
        policy_name = policy.get('name', f'policy-{idx}')
        
        # Check required fields
        required_fields = ['name', 'resource']
        for field in required_fields:
            if field not in policy:
                issues.append(f"Policy '{policy_name}': Missing required field '{field}'")
        
        # Check resource format
        if 'resource' in policy:
            resource = policy['resource']
            if not resource.startswith('aws.'):
                issues.append(f"Policy '{policy_name}': Resource should start with 'aws.' (got: {resource})")
        
        # Check actions structure
        if 'actions' in policy:
            actions = policy['actions']
            if not isinstance(actions, list):
                issues.append(f"Policy '{policy_name}': 'actions' must be a list")
            else:
                for action_idx, action in enumerate(actions):
                    if isinstance(action, dict):
                        if 'type' not in action:
                            issues.append(f"Policy '{policy_name}': Action {action_idx} missing 'type' field")
                        
                        # Check notify action structure
                        if action.get('type') == 'notify':
                            notify_required = ['template', 'subject', 'to', 'transport']
                            for field in notify_required:
                                if field not in action:
                                    issues.append(f"Policy '{policy_name}': notify action missing '{field}'")
                            
                            if 'transport' in action:
                                transport = action['transport']
                                if isinstance(transport, dict):
                                    if 'type' not in transport:
                                        issues.append(f"Policy '{policy_name}': notify transport missing 'type'")
                                    if transport.get('type') == 'sqs' and 'queue' not in transport:
                                        issues.append(f"Policy '{policy_name}': SQS transport missing 'queue' URL")
        
        # Check filters structure
        if 'filters' in policy:
            filters = policy['filters']
            if not isinstance(filters, list):
                issues.append(f"Policy '{policy_name}': 'filters' must be a list")
            else:
                for filter_idx, filt in enumerate(filters):
                    if isinstance(filt, dict) and 'type' not in filt and not any(k in filt for k in ['or', 'and', 'not']):
                        # Only issue warning if it's not a logical operator
                        issues.append(f"Policy '{policy_name}': Filter {filter_idx} missing 'type' field")
        
        # Warn if mode is present (not needed in event-driven architecture)
        if 'mode' in policy:
            issues.append(f"Policy '{policy_name}': WARNING - 'mode' field present but not needed for event-driven execution")
    
    return issues

def validate_event_mapping(mapping_data):
    """Validate account-policy-mapping.json structure"""
    issues = []
    
    if 'account_mapping' not in mapping_data:
        issues.append("Missing 'account_mapping' key")
        return issues
    
    account_mapping = mapping_data['account_mapping']
    
    for account_id, account_data in account_mapping.items():
        if 'event_mapping' not in account_data:
            issues.append(f"Account {account_id}: Missing 'event_mapping'")
            continue
        
        event_mapping = account_data['event_mapping']
        
        for event_name, policies in event_mapping.items():
            if not isinstance(policies, list):
                issues.append(f"Account {account_id}, Event {event_name}: Must be a list")
                continue
            
            for policy in policies:
                required_fields = ['policy_name', 'resource', 'source_file']
                for field in required_fields:
                    if field not in policy:
                        issues.append(f"Account {account_id}, Event {event_name}: Policy missing '{field}'")
    
    return issues

def main():
    print("=" * 70)
    print("Cloud Custodian Policy Validation")
    print("=" * 70)
    print()
    
    base_path = Path(__file__).parent.parent
    all_valid = True
    
    # Validate ransomware protection policies
    print("📝 Validating aws-s3-ransomware-protection.yml...")
    file_path = base_path / 'c7n' / 'policies' / 'aws-s3-ransomware-protection.yml'
    valid, data, error = validate_yaml_file(file_path)
    
    if not valid:
        print(f"  ❌ YAML Syntax Error: {error}")
        all_valid = False
    else:
        print("  ✅ Valid YAML syntax")
        issues = validate_policy_structure(data)
        if issues:
            print(f"  ⚠️  Found {len(issues)} issue(s):")
            for issue in issues:
                print(f"     - {issue}")
            all_valid = False
        else:
            print("  ✅ Policy structure valid")
    
    print()
    
    # Validate ransomware metrics policies
    print("📝 Validating aws-s3-ransomware-metrics.yml...")
    file_path = base_path / 'c7n' / 'policies' / 'aws-s3-ransomware-metrics.yml'
    valid, data, error = validate_yaml_file(file_path)
    
    if not valid:
        print(f"  ❌ YAML Syntax Error: {error}")
        all_valid = False
    else:
        print("  ✅ Valid YAML syntax")
        issues = validate_policy_structure(data)
        if issues:
            print(f"  ⚠️  Found {len(issues)} issue(s):")
            for issue in issues:
                print(f"     - {issue}")
            all_valid = False
        else:
            print("  ✅ Policy structure valid")
    
    print()
    
    # Validate account-policy-mapping.json
    print("📝 Validating account-policy-mapping.json...")
    file_path = base_path / 'c7n' / 'config' / 'account-policy-mapping.json'
    valid, data, error = validate_json_file(file_path)
    
    if not valid:
        print(f"  ❌ JSON Syntax Error: {error}")
        all_valid = False
    else:
        print("  ✅ Valid JSON syntax")
        issues = validate_event_mapping(data)
        if issues:
            print(f"  ⚠️  Found {len(issues)} issue(s):")
            for issue in issues:
                print(f"     - {issue}")
            # Don't fail on mapping issues, just warn
        else:
            print("  ✅ Event mapping structure valid")
    
    print()
    print("=" * 70)
    
    if all_valid:
        print("✅ All validations passed!")
        return 0
    else:
        print("❌ Some validations failed. Please fix the issues above.")
        return 1

if __name__ == '__main__':
    sys.exit(main())
