#!/usr/bin/env python3
"""
Transform policy-mapping.json from event_mapping dict to mappings array format.
This converts the structure from:
  {"event_mapping": {"EventName": [{"policy_name": "...", ...}]}}
To:
  {"mappings": [{"event_type": "EventName", "policy_name": "...", "enabled": true, "priority": 1, ...}]}
"""

import json
import sys
from pathlib import Path

def transform_policy_mapping(input_file: str, output_file: str = None):
    """Transform policy mapping from event_mapping to mappings structure."""
    
    # Read existing policy mapping
    with open(input_file, 'r') as f:
        data = json.load(f)
    
    print(f"Loaded policy mapping with {len(data.get('event_mapping', {}))} event types")
    
    # Create new mappings array
    mappings = []
    priority = 1
    
    # Transform event_mapping to mappings
    event_mapping = data.get('event_mapping', {})
    for event_type, policies in event_mapping.items():
        for policy in policies:
            mapping = {
                "event_type": event_type,
                "policy_name": policy.get("policy_name"),
                "resource": policy.get("resource"),
                "source_file": policy.get("source_file"),
                "policy_file": f"policies/{policy.get('source_file')}",
                "priority": priority,
                "enabled": True,
                "mode_type": policy.get("mode_type", "cloudtrail")
            }
            mappings.append(mapping)
            priority += 1
    
    print(f"Created {len(mappings)} mappings from event_mapping")
    
    # Create new structure
    new_data = {
        "version": data.get("version", "1.0"),
        "description": data.get("description", "Cloud Custodian Policy Event Mapping"),
        "generated_at": "auto-generated",
        "statistics": data.get("statistics", {}),
        "mappings": mappings,
        "policies": data.get("policies", {})
    }
    
    # Write to output file
    output_path = output_file or input_file
    with open(output_path, 'w') as f:
        json.dump(new_data, f, indent=2)
    
    print(f"Successfully transformed policy mapping to {output_path}")
    print(f"Total mappings: {len(mappings)}")
    print(f"Total policies: {len(new_data.get('policies', {}))}")
    
    # Show sample mappings
    print("\nSample mappings:")
    for mapping in mappings[:3]:
        print(f"  - {mapping['event_type']} -> {mapping['policy_name']}")

if __name__ == "__main__":
    script_dir = Path(__file__).parent
    project_dir = script_dir.parent
    config_file = project_dir / "config" / "policy-mapping.json"
    
    if not config_file.exists():
        print(f"ERROR: Policy mapping file not found: {config_file}")
        sys.exit(1)
    
    # Create backup
    backup_file = config_file.with_suffix('.json.backup')
    print(f"Creating backup: {backup_file}")
    with open(config_file, 'r') as src, open(backup_file, 'w') as dst:
        dst.write(src.read())
    
    # Transform the file
    transform_policy_mapping(str(config_file))
