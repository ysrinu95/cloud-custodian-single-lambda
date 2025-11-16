"""
Fix SQS queue region from us-west-2 to us-east-1 in all policies
"""

import os
import re
from pathlib import Path

def fix_sqs_region(file_path):
    """Fix SQS queue region in a policy file"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        
        # Replace us-west-2 with us-east-1 in SQS queue URLs
        content = re.sub(
            r'https://sqs\.us-west-2\.amazonaws\.com/172327596604/custodian-mailer-queue',
            r'https://sqs.us-east-1.amazonaws.com/172327596604/custodian-mailer-queue',
            content
        )
        
        if content != original_content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            return True
        
        return False
            
    except Exception as e:
        print(f"Error processing {file_path.name}: {str(e)}")
        return False

def main():
    directories = [
        Path(__file__).parent / 'policies',
        Path(__file__).parent / 'policies-event-driven'
    ]
    
    total_fixed = 0
    
    for directory in directories:
        if not directory.exists():
            continue
        
        print(f"\nFixing policies in: {directory.name}")
        print(f"{'='*80}\n")
        
        yml_files = sorted(directory.glob('*.yml'))
        
        for yml_file in yml_files:
            if fix_sqs_region(yml_file):
                print(f"Fixed: {yml_file.name}")
                total_fixed += 1
    
    print(f"\n{'='*80}")
    print(f"Fixed {total_fixed} policy files")
    print(f"Changed region from us-west-2 to us-east-1")
    print(f"{'='*80}")

if __name__ == '__main__':
    main()
