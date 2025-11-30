#!/usr/bin/env python3
"""
Cloud Custodian Policy Validator
Validates YAML syntax and policy structure for all policy files
"""

import yaml
import os
import sys
from pathlib import Path

def validate_yaml_syntax(file_path):
    """Validate YAML syntax"""
    try:
        with open(file_path, 'r') as f:
            yaml.safe_load(f)
        return True, "YAML syntax valid"
    except yaml.YAMLError as e:
        return False, f"YAML syntax error: {e}"
    except Exception as e:
        return False, f"Error reading file: {e}"

def validate_policy_structure(file_path):
    """Validate Cloud Custodian policy structure"""
    try:
        with open(file_path, 'r') as f:
            data = yaml.safe_load(f)
        
        if not isinstance(data, dict):
            return False, "Root element must be a dictionary"
        
        if 'policies' not in data:
            return False, "Missing 'policies' key"
        
        policies = data['policies']
        if not isinstance(policies, list):
            return False, "'policies' must be a list"
        
        policy_count = len(policies)
        policy_names = []
        
        for idx, policy in enumerate(policies):
            if not isinstance(policy, dict):
                return False, f"Policy {idx} is not a dictionary"
            
            if 'name' not in policy:
                return False, f"Policy {idx} missing 'name'"
            
            policy_names.append(policy['name'])
            
            if 'resource' not in policy:
                return False, f"Policy '{policy['name']}' missing 'resource'"
            
            if 'description' not in policy:
                return False, f"Policy '{policy['name']}' missing 'description'"
        
        return True, f"Valid structure with {policy_count} policies: {', '.join(policy_names)}"
    
    except Exception as e:
        return False, f"Structure validation error: {e}"

def main():
    policy_dir = Path("../policies")
    
    if not policy_dir.exists():
        print("Error: policies directory not found")
        sys.exit(1)
    
    policy_files = sorted(policy_dir.glob("aws-*.yml"))
    
    if not policy_files:
        print("No policy files found")
        sys.exit(1)
    
    print("=" * 80)
    print("Cloud Custodian Policy Validation Report")
    print(f"Policy Directory: {policy_dir.absolute()}")
    print("=" * 80)
    print()
    
    total_files = 0
    valid_files = 0
    failed_files = 0
    total_policies = 0
    
    results = []
    
    for policy_file in policy_files:
        total_files += 1
        filename = policy_file.name
        
        print(f"Testing: {filename}")
        print("-" * 80)
        
        # Validate YAML syntax
        syntax_valid, syntax_msg = validate_yaml_syntax(policy_file)
        print(f"  YAML Syntax: {'✓ PASS' if syntax_valid else '✗ FAIL'} - {syntax_msg}")
        
        if not syntax_valid:
            failed_files += 1
            results.append({
                'file': filename,
                'status': 'FAILED',
                'reason': syntax_msg
            })
            print()
            continue
        
        # Validate policy structure
        structure_valid, structure_msg = validate_policy_structure(policy_file)
        print(f"  Structure: {'✓ PASS' if structure_valid else '✗ FAIL'} - {structure_msg}")
        
        if structure_valid:
            valid_files += 1
            # Count policies
            with open(policy_file, 'r') as f:
                data = yaml.safe_load(f)
                policy_count = len(data.get('policies', []))
                total_policies += policy_count
            
            results.append({
                'file': filename,
                'status': 'PASSED',
                'policies': policy_count
            })
        else:
            failed_files += 1
            results.append({
                'file': filename,
                'status': 'FAILED',
                'reason': structure_msg
            })
        
        print()
    
    # Summary
    print("=" * 80)
    print("VALIDATION SUMMARY")
    print("=" * 80)
    print(f"Total Policy Files: {total_files}")
    print(f"Valid Files: {valid_files}")
    print(f"Failed Files: {failed_files}")
    print(f"Total Policies: {total_policies}")
    
    if total_files > 0:
        success_rate = (valid_files / total_files) * 100
        print(f"Success Rate: {success_rate:.2f}%")
    
    print()
    
    # Detailed results
    if failed_files > 0:
        print("FAILED FILES:")
        print("-" * 80)
        for result in results:
            if result['status'] == 'FAILED':
                print(f"  ✗ {result['file']}: {result.get('reason', 'Unknown error')}")
        print()
    
    if valid_files > 0:
        print("PASSED FILES:")
        print("-" * 80)
        for result in results:
            if result['status'] == 'PASSED':
                print(f"  ✓ {result['file']}: {result['policies']} policies")
        print()
    
    sys.exit(0 if failed_files == 0 else 1)

if __name__ == "__main__":
    main()
