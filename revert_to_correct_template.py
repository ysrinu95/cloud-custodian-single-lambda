#!/usr/bin/env python3
"""
Script to update email template references in Cloud Custodian policy files.
Changes 'default.html' and 'default' back to 'aws-basic_email.html' 
which is the correct template name based on config/mailer-templates/.
"""

import os
import re

def fix_template_references(directory):
    """Fix template references in all YAML files in the given directory."""
    fixed_files = []
    
    # Patterns to match and replace
    patterns = [
        (r'template:\s*default\.html', 'template: aws-basic_email.html'),
        (r'template:\s*default\s*$', 'template: aws-basic_email.html'),
        (r'template:\s*default\s*\n', 'template: aws-basic_email.html\n')
    ]
    
    for root, dirs, files in os.walk(directory):
        for filename in files:
            if filename.endswith('.yml') or filename.endswith('.yaml'):
                filepath = os.path.join(root, filename)
                
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    # Check if the file contains template reference that needs updating
                    if 'template: default' in content:
                        # Replace all occurrences using all patterns
                        new_content = content
                        for pattern, replacement in patterns:
                            new_content = re.sub(pattern, replacement, new_content, flags=re.MULTILINE)
                        
                        # Only write if changes were made
                        if new_content != content:
                            # Write back to file
                            with open(filepath, 'w', encoding='utf-8') as f:
                                f.write(new_content)
                            
                            fixed_files.append(filepath)
                            print(f"Fixed: {filename}")
                
                except Exception as e:
                    print(f"Error processing {filepath}: {e}")
    
    return fixed_files

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Fix policies in both directories
    directories = [
        os.path.join(base_dir, 'policies'),
        os.path.join(base_dir, 'policies-event-driven')
    ]
    
    all_fixed_files = []
    
    for directory in directories:
        if os.path.exists(directory):
            print(f"\nFixing policies in: {os.path.basename(directory)}")
            print("=" * 80)
            fixed_files = fix_template_references(directory)
            all_fixed_files.extend(fixed_files)
    
    print("\n" + "=" * 80)
    print(f"Fixed {len(all_fixed_files)} policy files")
    print("Changed template from 'default.html' or 'default' to 'aws-basic_email.html'")
    print("=" * 80)

if __name__ == '__main__':
    main()
