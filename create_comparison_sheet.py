import csv

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
        stripped = line.strip()
        if stripped:
            cc_policies.append(stripped)

# Remove duplicates and filter out empty strings
cc_policies = [p for p in list(set(cc_policies)) if p]
print(f'Found {len(cc_policies)} unique policies in CloudCustodian_Policies.txt')

# Read prisma-cloud-aws-policies.csv (original backup)
prisma_policies = []
with open('c7n/policies/prisma-cloud-aws-policies.csv.backup', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        prisma_policies.append(row)

print(f'Found {len(prisma_policies)} policies in prisma-cloud-aws-policies.csv')

# Create comparison data
comparison_data = []

# Function to find best matching CC policy
def find_best_match(prisma_name, cc_policies):
    best_match = ""
    best_score = 0
    
    prisma_lower = prisma_name.lower()
    keywords = ['s3', 'rds', 'ebs', 'ec2', 'iam', 'eks', 'elb', 'cloudfront', 'security group', 
               'encryption', 'public', 'kms', 'ssl', 'tls', 'snapshot', 'cloudtrail', 'cloudwatch',
               'elasticsearch', 'redshift', 'kinesis', 'lambda', 'sns', 'sqs', 'waf', 'elasticache',
               'guardduty', 'acl', 'vpc', 'ami', 'emr', 'neptune']
    
    for cc_policy in cc_policies:
        cc_lower = cc_policy.lower()
        
        # Check for common keywords
        common_keywords = [kw for kw in keywords if kw in cc_lower and kw in prisma_lower]
        
        if common_keywords:
            # Calculate word overlap
            cc_words = set(cc_lower.split())
            prisma_words = set(prisma_lower.split())
            common_words = cc_words.intersection(prisma_words)
            
            score = len(common_words)
            
            if score > best_score:
                best_score = score
                best_match = cc_policy
    
    # Consider matched if score >= 3
    is_matched = best_score >= 3
    return best_match, is_matched

# Process each Prisma policy
for prisma_policy in prisma_policies:
    prisma_name = prisma_policy['Policy']
    best_cc_match, is_matched = find_best_match(prisma_name, cc_policies)
    
    comparison_data.append({
        'Cloud_Custodian_Policy': best_cc_match if is_matched else '',
        'Prisma_Cloud_Policy': prisma_name,
        'Matched': 'TRUE' if is_matched else 'FALSE',
        'Severity': prisma_policy['Severity'],
        'Category': prisma_policy['Category'],
        'Checkov_ID': prisma_policy['Checkov ID']
    })

# Write comparison CSV
output_file = 'c7n/policies/policy-comparison-detailed.csv'
with open(output_file, 'w', encoding='utf-8', newline='') as f:
    fieldnames = ['Cloud_Custodian_Policy', 'Prisma_Cloud_Policy', 'Matched', 'Severity', 'Category', 'Checkov_ID']
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    
    writer.writeheader()
    writer.writerows(comparison_data)

# Create summary statistics
matched_count = sum(1 for row in comparison_data if row['Matched'] == 'TRUE')
not_matched_count = len(comparison_data) - matched_count

print(f'\nComparison complete!')
print(f'Output saved to: {output_file}')
print(f'\nSummary:')
print(f'- Total Prisma policies: {len(comparison_data)}')
print(f'- Matched policies: {matched_count}')
print(f'- Non-matched policies: {not_matched_count}')

# Also create a sheet with only non-matched for easy review
non_matched_file = 'c7n/policies/non-matched-policies.csv'
with open(non_matched_file, 'w', encoding='utf-8', newline='') as f:
    fieldnames = ['Prisma_Cloud_Policy', 'Severity', 'Category', 'Checkov_ID']
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    
    writer.writeheader()
    for row in comparison_data:
        if row['Matched'] == 'FALSE':
            writer.writerow({
                'Prisma_Cloud_Policy': row['Prisma_Cloud_Policy'],
                'Severity': row['Severity'],
                'Category': row['Category'],
                'Checkov_ID': row['Checkov_ID']
            })

print(f'Non-matched policies saved to: {non_matched_file}')
