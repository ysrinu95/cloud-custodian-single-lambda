#!/usr/bin/env python3
"""
Fix for Cloud Custodian c7n-mailer PyJWT issue
Based on community solution from GitHub Issue #10282
"""

import os
import sys
import shutil
from pathlib import Path

def find_deploy_py():
    """Find the c7n_mailer deploy.py file"""
    try:
        import c7n_mailer.deploy
        return Path(c7n_mailer.deploy.__file__)
    except ImportError:
        print("ERROR: c7n_mailer not found. Please install it first.")
        return None

def backup_file(file_path):
    """Create a backup of the original file"""
    backup_path = file_path.with_suffix(file_path.suffix + '.backup')
    shutil.copy2(file_path, backup_path)
    print(f"✅ Backup created: {backup_path}")
    return backup_path

def fix_core_deps(deploy_py_path):
    """Fix CORE_DEPS to include 'jwt' package"""
    print(f"📝 Reading file: {deploy_py_path}")
    
    with open(deploy_py_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Check if jwt is already in CORE_DEPS
    if '"jwt"' in content or "'jwt'" in content:
        print("✅ 'jwt' already exists in CORE_DEPS - no changes needed")
        return False
    
    # Find CORE_DEPS and add jwt
    lines = content.splitlines()
    modified = False
    
    for i, line in enumerate(lines):
        if 'CORE_DEPS = [' in line:
            # Look for the next few lines to find where to insert jwt
            for j in range(i+1, min(i+20, len(lines))):
                if lines[j].strip().startswith('"jinja2"') or lines[j].strip().startswith("'jinja2'"):
                    # Insert jwt after jinja2
                    indent = len(lines[j]) - len(lines[j].lstrip())
                    jwt_line = ' ' * indent + '"jwt",'
                    lines.insert(j+1, jwt_line)
                    modified = True
                    print("✅ Added 'jwt' to CORE_DEPS after 'jinja2'")
                    break
            break
    
    if not modified:
        print("❌ Could not find CORE_DEPS section to modify")
        return False
    
    # Write the modified content back
    with open(deploy_py_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    
    print("✅ Successfully modified deploy.py")
    return True

def main():
    print("🔧 Cloud Custodian c7n-mailer PyJWT Fix")
    print("=" * 50)
    print("Based on community solution from GitHub Issue #10282")
    print("Solution by @harisfauzi: Add 'jwt' to CORE_DEPS")
    print()
    
    # Find deploy.py
    deploy_py_path = find_deploy_py()
    if not deploy_py_path:
        sys.exit(1)
    
    print(f"📍 Found deploy.py: {deploy_py_path}")
    
    # Create backup
    backup_path = backup_file(deploy_py_path)
    
    try:
        # Fix the CORE_DEPS
        success = fix_core_deps(deploy_py_path)
        
        if success:
            print()
            print("🎉 Fix Applied Successfully!")
            print("Next steps:")
            print("1. Run: c7n-mailer --config mailer.yml --update-lambda")
            print("2. Test your c7n-mailer deployment")
            print()
            print("If you need to revert changes:")
            print(f"copy '{backup_path}' '{deploy_py_path}'")
        else:
            print("❌ Fix failed - restoring backup")
            shutil.copy2(backup_path, deploy_py_path)
            
    except Exception as e:
        print(f"❌ Error during fix: {e}")
        print("Restoring backup...")
        shutil.copy2(backup_path, deploy_py_path)
        sys.exit(1)

if __name__ == "__main__":
    main()