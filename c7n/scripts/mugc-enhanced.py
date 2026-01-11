#!/usr/bin/env python3
"""
Enhanced Multi-Account Garbage Collection for Cloud Custodian
Properly handles cleanup of Lambda functions, CloudWatch Events rules, 
and their targets for removed policies.
"""

import argparse
import boto3
import json
import sys
import re
from datetime import datetime

# ANSI color codes
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    MAGENTA = '\033[0;35m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

def print_info(msg):
    print(f"{Colors.BLUE}[INFO]{Colors.NC} {msg}")

def print_success(msg):
    print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {msg}")

def print_warning(msg):
    print(f"{Colors.YELLOW}[WARNING]{Colors.NC} {msg}")

def print_error(msg):
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}")

def parse_policy_files(policy_files):
    """Parse policy YAML files to get list of active policy names."""
    import yaml
    
    active_policies = set()
    
    for policy_file in policy_files:
        try:
            with open(policy_file, 'r') as f:
                data = yaml.safe_load(f)
                if data and 'policies' in data:
                    for policy in data['policies']:
                        if 'name' in policy:
                            active_policies.add(policy['name'])
        except Exception as e:
            print_error(f"Failed to parse {policy_file}: {e}")
    
    return active_policies

def get_custodian_lambdas(lambda_client):
    """Get all Lambda functions created by Cloud Custodian."""
    custodian_functions = []
    
    try:
        paginator = lambda_client.get_paginator('list_functions')
        for page in paginator.paginate():
            for func in page['Functions']:
                # Cloud Custodian functions start with 'custodian-'
                if func['FunctionName'].startswith('custodian-'):
                    custodian_functions.append(func)
    except Exception as e:
        print_error(f"Failed to list Lambda functions: {e}")
    
    return custodian_functions

def get_custodian_event_rules(events_client):
    """Get all CloudWatch Events rules created by Cloud Custodian."""
    custodian_rules = []
    
    try:
        paginator = events_client.get_paginator('list_rules')
        for page in paginator.paginate():
            for rule in page['Rules']:
                # Cloud Custodian rules start with 'custodian-' or match pattern
                if rule['Name'].startswith('custodian-') or 'cloud-custodian' in rule.get('Description', '').lower():
                    custodian_rules.append(rule)
    except Exception as e:
        print_error(f"Failed to list CloudWatch Events rules: {e}")
    
    return custodian_rules

def remove_event_rule_targets(events_client, rule_name, dry_run=False):
    """Remove all targets from a CloudWatch Events rule before deleting it."""
    try:
        # List targets for the rule
        response = events_client.list_targets_by_rule(Rule=rule_name)
        targets = response.get('Targets', [])
        
        if not targets:
            print_info(f"  No targets found for rule: {rule_name}")
            return True
        
        target_ids = [target['Id'] for target in targets]
        print_info(f"  Found {len(target_ids)} target(s) for rule: {rule_name}")
        
        if dry_run:
            print_info(f"  [DRY RUN] Would remove {len(target_ids)} target(s)")
            return True
        
        # Remove targets
        events_client.remove_targets(Rule=rule_name, Ids=target_ids)
        print_success(f"  Removed {len(target_ids)} target(s) from rule: {rule_name}")
        return True
        
    except Exception as e:
        print_error(f"  Failed to remove targets from rule {rule_name}: {e}")
        return False

def delete_lambda_function(lambda_client, function_name, dry_run=False):
    """Delete a Lambda function."""
    try:
        if dry_run:
            print_info(f"  [DRY RUN] Would delete Lambda function: {function_name}")
            return True
        
        lambda_client.delete_function(FunctionName=function_name)
        print_success(f"  Deleted Lambda function: {function_name}")
        return True
    except lambda_client.exceptions.ResourceNotFoundException:
        print_warning(f"  Lambda function not found: {function_name}")
        return False
    except Exception as e:
        print_error(f"  Failed to delete Lambda function {function_name}: {e}")
        return False

def delete_event_rule(events_client, rule_name, dry_run=False):
    """Delete a CloudWatch Events rule after removing its targets."""
    try:
        # First remove all targets
        if not remove_event_rule_targets(events_client, rule_name, dry_run):
            print_warning(f"  Could not remove targets for rule: {rule_name}")
            # Continue anyway to try to delete the rule
        
        if dry_run:
            print_info(f"  [DRY RUN] Would delete CloudWatch Events rule: {rule_name}")
            return True
        
        # Delete the rule
        events_client.delete_rule(Name=rule_name)
        print_success(f"  Deleted CloudWatch Events rule: {rule_name}")
        return True
    except events_client.exceptions.ResourceNotFoundException:
        print_warning(f"  CloudWatch Events rule not found: {rule_name}")
        return False
    except Exception as e:
        print_error(f"  Failed to delete CloudWatch Events rule {rule_name}: {e}")
        return False

def cleanup_resources(region, active_policies, present_mode=False, dry_run=False, verbose=False):
    """Clean up Lambda functions and CloudWatch Events rules for removed policies."""
    
    print_info(f"\n{'='*60}")
    print_info(f"Cleaning up resources in region: {region}")
    print_info(f"{'='*60}")
    
    if verbose:
        print_info(f"Active policies count: {len(active_policies)}")
        if active_policies:
            print_info(f"Active policies: {', '.join(sorted(active_policies))}")
    
    session = boto3.Session(region_name=region)
    lambda_client = session.client('lambda')
    events_client = session.client('events')
    
    # Get all Custodian resources
    print_info("\n📋 Discovering Cloud Custodian resources...")
    custodian_lambdas = get_custodian_lambdas(lambda_client)
    custodian_rules = get_custodian_event_rules(events_client)
    
    print_info(f"Found {len(custodian_lambdas)} Lambda function(s)")
    print_info(f"Found {len(custodian_rules)} CloudWatch Events rule(s)")
    
    # Track what we're doing
    deleted_lambdas = []
    deleted_rules = []
    kept_lambdas = []
    kept_rules = []
    
    # Process Lambda functions
    print_info("\n🔍 Processing Lambda functions...")
    for func in custodian_lambdas:
        func_name = func['FunctionName']
        # Extract policy name from function name (custodian-<policy-name>)
        policy_name = func_name.replace('custodian-', '', 1)
        
        # Determine if we should delete
        should_delete = False
        if present_mode:
            # In present mode, delete functions for policies that ARE in the config (for redeployment)
            should_delete = policy_name in active_policies
            reason = "present in config (redeployment mode)"
        else:
            # In normal mode, delete functions for policies that are NOT in the config
            should_delete = policy_name not in active_policies
            reason = "not in active policies"
        
        if should_delete:
            if verbose or dry_run:
                print_warning(f"🗑️  {func_name} - {reason}")
            if delete_lambda_function(lambda_client, func_name, dry_run):
                deleted_lambdas.append(func_name)
        else:
            if verbose:
                print_success(f"✅ {func_name} - keeping (active policy)")
            kept_lambdas.append(func_name)
    
    # Process CloudWatch Events rules
    print_info("\n🔍 Processing CloudWatch Events rules...")
    for rule in custodian_rules:
        rule_name = rule['Name']
        # Extract policy name from rule name (custodian-<policy-name>)
        policy_name = rule_name.replace('custodian-', '', 1)
        
        # Determine if we should delete
        should_delete = False
        if present_mode:
            should_delete = policy_name in active_policies
            reason = "present in config (redeployment mode)"
        else:
            should_delete = policy_name not in active_policies
            reason = "not in active policies"
        
        if should_delete:
            if verbose or dry_run:
                print_warning(f"🗑️  {rule_name} - {reason}")
            if delete_event_rule(events_client, rule_name, dry_run):
                deleted_rules.append(rule_name)
        else:
            if verbose:
                print_success(f"✅ {rule_name} - keeping (active policy)")
            kept_rules.append(rule_name)
    
    # Summary
    print_info(f"\n{'='*60}")
    print_info("Cleanup Summary")
    print_info(f"{'='*60}")
    print_success(f"Lambda functions {'would be ' if dry_run else ''}deleted: {len(deleted_lambdas)}")
    print_success(f"CloudWatch Events rules {'would be ' if dry_run else ''}deleted: {len(deleted_rules)}")
    print_info(f"Lambda functions kept: {len(kept_lambdas)}")
    print_info(f"CloudWatch Events rules kept: {len(kept_rules)}")
    
    if verbose and deleted_lambdas:
        print_info("\nDeleted Lambda functions:")
        for func in deleted_lambdas:
            print_info(f"  - {func}")
    
    if verbose and deleted_rules:
        print_info("\nDeleted CloudWatch Events rules:")
        for rule in deleted_rules:
            print_info(f"  - {rule}")
    
    return {
        'deleted_lambdas': len(deleted_lambdas),
        'deleted_rules': len(deleted_rules),
        'kept_lambdas': len(kept_lambdas),
        'kept_rules': len(kept_rules)
    }

def main():
    parser = argparse.ArgumentParser(
        description='Enhanced Multi-Account Garbage Collection for Cloud Custodian',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run to see what would be deleted
  python mugc-enhanced.py -c policies/*.yml --dryrun --verbose

  # Delete resources for removed policies
  python mugc-enhanced.py -c policies/*.yml --verbose

  # Clean up resources for specific region
  python mugc-enhanced.py -c policies/*.yml -r us-west-2

  # Present mode - delete resources for policies that ARE in config (for redeployment)
  python mugc-enhanced.py -c policies/*.yml --present --dryrun
        """
    )
    
    parser.add_argument('-c', '--config', nargs='+', required=True,
                        help='Policy files to check for active policies')
    parser.add_argument('-r', '--region', default='us-east-1',
                        help='AWS region (default: us-east-1)')
    parser.add_argument('--present', action='store_true',
                        help='Delete resources for policies PRESENT in config (for redeployment)')
    parser.add_argument('--dryrun', action='store_true',
                        help='Dry run - show what would be deleted without deleting')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Verbose output')
    parser.add_argument('--profile', help='AWS profile to use')
    
    args = parser.parse_args()
    
    # Set AWS profile if specified
    if args.profile:
        boto3.setup_default_session(profile_name=args.profile)
    
    # Parse policy files to get active policies
    print_info("📁 Parsing policy configuration files...")
    active_policies = parse_policy_files(args.config)
    print_success(f"Found {len(active_policies)} active policy/policies")
    
    # Run cleanup
    try:
        results = cleanup_resources(
            region=args.region,
            active_policies=active_policies,
            present_mode=args.present,
            dry_run=args.dryrun,
            verbose=args.verbose
        )
        
        print_info("\n" + "="*60)
        print_success("✅ Cleanup completed successfully!")
        print_info("="*60)
        
        return 0
        
    except Exception as e:
        print_error(f"\n❌ Cleanup failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == '__main__':
    sys.exit(main())
