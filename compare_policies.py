import csv
import re

# Read CloudCustodian_Policies.txt
with open('c7n/policies/CloudCustodian_Policies.txt', 'r', encoding='utf-8') as f:
    cc_content = f.read()

# Extract policy names from CloudCustodian_Policies.txt
cc_policies = []
for line in cc_content.strip().split('\n'):
    if ' - realtime/periodic' in line or ' - periodic' in line:
        policy = line.split(' - ')[0].strip()
        if policy:
            cc_policies.append(policy)
    elif line and not line.startswith('Access Query:') and not line.startswith('config from'):
        # Handle policies without the suffix
        stripped = line.strip()
        if stripped:
            cc_policies.append(stripped)

# Remove duplicates and filter out empty strings
cc_policies = [p for p in list(set(cc_policies)) if p]
print(f'Found {len(cc_policies)} unique policies in CloudCustodian_Policies.txt')

# Read prisma-cloud-aws-policies.csv
prisma_policies = []
with open('c7n/policies/prisma-cloud-aws-policies.csv', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        prisma_policies.append(row)

print(f'Found {len(prisma_policies)} policies in prisma-cloud-aws-policies.csv')

# Compare and find non-matched policies
matched = []
non_matched = []

for prisma_policy in prisma_policies:
    prisma_name = prisma_policy['Policy']
    
    # Check if any CloudCustodian policy name is similar to the Prisma policy name
    is_matched = False
    for cc_policy in cc_policies:
        # Normalize strings for comparison
        cc_lower = cc_policy.lower()
        prisma_lower = prisma_name.lower()
        
        # Check for keyword matches
        keywords = ['s3', 'rds', 'ebs', 'ec2', 'iam', 'eks', 'elb', 'cloudfront', 'security group', 
                   'encryption', 'public', 'kms', 'ssl', 'tls', 'snapshot', 'cloudtrail', 'cloudwatch',
                   'elasticsearch', 'redshift', 'kinesis', 'lambda', 'sns', 'sqs', 'waf', 'elasticache',
                   'guardduty', 'acl', 'vpc', 'ami', 'emr', 'neptune']
        
        # Check if both policies contain common AWS service keywords
        common_keywords = [kw for kw in keywords if kw in cc_lower and kw in prisma_lower]
        
        if common_keywords:
            # More detailed matching - check for significant word overlap
            cc_words = set(cc_lower.split())
            prisma_words = set(prisma_lower.split())
            common_words = cc_words.intersection(prisma_words)
            
            # If they share 3+ significant words, consider them matched
            if len(common_words) >= 3:
                is_matched = True
                break
    
    if is_matched:
        matched.append(prisma_policy)
    else:
        non_matched.append(prisma_policy)

print(f'\nMatched policies: {len(matched)}')
print(f'Non-matched policies: {len(non_matched)}')

# Create a new CSV file with non-matched policies
output_file = 'c7n/policies/prisma-cloud-aws-policies-with-non-matched.csv'

# Read original CSV content
with open('c7n/policies/prisma-cloud-aws-policies.csv', 'r', encoding='utf-8') as f:
    original_content = f.read()

# Write the combined output
with open(output_file, 'w', encoding='utf-8', newline='') as f:
    # Write original content
    f.write(original_content)
    
    # Add non-matched section
    f.write('\n\n')
    f.write('="NON-MATCHED POLICIES (Not found in CloudCustodian_Policies.txt)"\n')
    f.write('Policy,Severity,Category,Checkov ID\n')
    
    writer = csv.DictWriter(f, fieldnames=['Policy', 'Severity', 'Category', 'Checkov ID'])
    for policy in non_matched:
        writer.writerow(policy)

print(f'\nComparison complete!')
print(f'Output saved to: {output_file}')
print(f'\nSummary:')
print(f'- Total Prisma policies: {len(prisma_policies)}')
print(f'- Matched policies: {len(matched)}')
print(f'- Non-matched policies: {len(non_matched)}')
