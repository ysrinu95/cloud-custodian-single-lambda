"""
Compliance Pre-Validator for Long-Running AWS Resources

This module provides pre-validation logic for AWS resources that take a long time
to reach 'available' status. Validators check CloudTrail event responseElements
before invoking Cloud Custodian policies, improving efficiency by skipping
compliant resources.

Usage:
    from compliance_pre_validator import ResourceValidator
    
    validator = ResourceValidator()
    result = validator.validate('CreateCacheCluster', event_detail)
    
    if result['action'] == 'skip':
        # Resource is compliant, skip Cloud Custodian
        return
    else:
        # Proceed with Cloud Custodian for violation notification
        invoke_cloud_custodian(event)
"""

import logging
from typing import Dict, List, Set, Optional, Any

logger = logging.getLogger(__name__)


class ResourceValidator:
    """
    Validates AWS resource configurations from CloudTrail events.
    
    Supports pre-validation for:
    - ElastiCache (Redis) - encryption at rest and in transit
    - EKS - control plane logging
    - Elasticsearch/OpenSearch - encryption at rest and node-to-node
    - Redshift - encryption at rest
    - RDS - encryption at rest (DB instances and Aurora clusters)
    """
    
    # Required EKS logging types
    EKS_REQUIRED_LOG_TYPES = {'api', 'audit', 'authenticator', 'controllerManager', 'scheduler'}
    
    def __init__(self):
        """Initialize the resource validator."""
        self.validators = {
            'CreateCacheCluster': self.validate_elasticache_encryption,
            'CreateReplicationGroup': self.validate_elasticache_replication_encryption,
            'CreateCluster': self.validate_eks_logging,
            'CreateDomain': self.validate_elasticsearch_encryption,
            'CreateElasticsearchDomain': self.validate_elasticsearch_encryption,
            'CreateDBInstance': self.validate_rds_encryption,
            'CreateDBCluster': self.validate_rds_cluster_encryption,
        }
    
    def validate(self, event_name: str, event_detail: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate a CloudTrail event for resource compliance.
        
        Args:
            event_name: CloudTrail event name (e.g., 'CreateCacheCluster')
            event_detail: CloudTrail event detail containing responseElements
            
        Returns:
            Dictionary with validation result:
            {
                'action': 'skip' | 'proceed',
                'reason': 'compliant' | 'violation',
                'resource_id': str,
                'violations': dict (if non-compliant)
            }
        """
        validator_func = self.validators.get(event_name)
        
        if not validator_func:
            logger.debug(f"No validator for event: {event_name}")
            return {'action': 'proceed', 'reason': 'no_validator'}
        
        try:
            return validator_func(event_detail)
        except Exception as e:
            logger.error(f"Validation error for {event_name}: {e}", exc_info=True)
            # On error, proceed with Cloud Custodian (fail-safe)
            return {'action': 'proceed', 'reason': 'validation_error', 'error': str(e)}
    
    def validate_elasticache_encryption(self, event_detail: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate ElastiCache Redis cluster encryption configuration.
        
        Checks:
        - atRestEncryptionEnabled: true
        - transitEncryptionEnabled: true (for standalone clusters)
        
        Args:
            event_detail: CloudTrail event detail
            
        Returns:
            Validation result with action and violations
        """
        response = event_detail.get('responseElements', {})
        cluster_id = response.get('cacheClusterId', 'unknown')
        engine = response.get('engine', '').lower()
        
        # Only validate Redis clusters
        if engine != 'redis':
            return {
                'action': 'skip',
                'reason': 'not_redis',
                'resource_id': cluster_id
            }
        
        at_rest = response.get('atRestEncryptionEnabled', False)
        in_transit = response.get('transitEncryptionEnabled', False)
        
        violations = {}
        if not at_rest:
            violations['at_rest_encryption'] = 'disabled'
        if not in_transit:
            violations['transit_encryption'] = 'disabled'
        
        if violations:
            logger.info(f"ElastiCache {cluster_id} violations: {violations}")
            return {
                'action': 'proceed',
                'reason': 'violation',
                'resource_id': cluster_id,
                'violations': violations
            }
        
        logger.info(f"ElastiCache {cluster_id} is compliant")
        return {
            'action': 'skip',
            'reason': 'compliant',
            'resource_id': cluster_id
        }
    
    def validate_elasticache_replication_encryption(self, event_detail: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate ElastiCache Replication Group encryption configuration.
        
        Checks:
        - atRestEncryptionEnabled: true
        - transitEncryptionEnabled: true
        
        Args:
            event_detail: CloudTrail event detail
            
        Returns:
            Validation result with action and violations
        """
        response = event_detail.get('responseElements', {})
        replication_group_id = response.get('replicationGroupId', 'unknown')
        
        at_rest = response.get('atRestEncryptionEnabled', False)
        in_transit = response.get('transitEncryptionEnabled', False)
        
        violations = {}
        if not at_rest:
            violations['at_rest_encryption'] = 'disabled'
        if not in_transit:
            violations['transit_encryption'] = 'disabled'
        
        if violations:
            logger.info(f"ElastiCache Replication Group {replication_group_id} violations: {violations}")
            return {
                'action': 'proceed',
                'reason': 'violation',
                'resource_id': replication_group_id,
                'violations': violations
            }
        
        logger.info(f"ElastiCache Replication Group {replication_group_id} is compliant")
        return {
            'action': 'skip',
            'reason': 'compliant',
            'resource_id': replication_group_id
        }
    
    def validate_eks_logging(self, event_detail: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate EKS cluster control plane logging configuration.
        
        Checks that all 5 log types are enabled:
        - api
        - audit
        - authenticator
        - controllerManager
        - scheduler
        
        Args:
            event_detail: CloudTrail event detail
            
        Returns:
            Validation result with action and missing log types
        """
        response = event_detail.get('responseElements', {})
        cluster = response.get('cluster', {})
        cluster_name = cluster.get('name', 'unknown')
        
        logging_config = cluster.get('logging', {}).get('clusterLogging', [])
        
        # Collect enabled log types
        enabled_types = set()
        for log_setup in logging_config:
            if log_setup.get('enabled', False):
                enabled_types.update(log_setup.get('types', []))
        
        missing_types = self.EKS_REQUIRED_LOG_TYPES - enabled_types
        
        if missing_types:
            logger.info(f"EKS {cluster_name} missing log types: {missing_types}")
            return {
                'action': 'proceed',
                'reason': 'violation',
                'resource_id': cluster_name,
                'violations': {
                    'missing_log_types': list(missing_types),
                    'enabled_types': list(enabled_types)
                }
            }
        
        logger.info(f"EKS {cluster_name} has all required logging enabled")
        return {
            'action': 'skip',
            'reason': 'compliant',
            'resource_id': cluster_name,
            'enabled_log_types': list(enabled_types)
        }
    
    def validate_elasticsearch_encryption(self, event_detail: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate Elasticsearch/OpenSearch domain encryption configuration.
        
        Checks:
        - encryptionAtRestOptions.enabled: true
        - nodeToNodeEncryptionOptions.enabled: true
        
        Args:
            event_detail: CloudTrail event detail
            
        Returns:
            Validation result with action and violations
        """
        response = event_detail.get('responseElements', {})
        domain_status = response.get('domainStatus', {})
        domain_name = domain_status.get('domainName', 'unknown')
        
        at_rest_options = domain_status.get('encryptionAtRestOptions', {})
        at_rest = at_rest_options.get('enabled', False)
        
        node_to_node_options = domain_status.get('nodeToNodeEncryptionOptions', {})
        node_to_node = node_to_node_options.get('enabled', False)
        
        violations = {}
        if not at_rest:
            violations['at_rest_encryption'] = 'disabled'
        if not node_to_node:
            violations['node_to_node_encryption'] = 'disabled'
        
        if violations:
            logger.info(f"Elasticsearch {domain_name} violations: {violations}")
            return {
                'action': 'proceed',
                'reason': 'violation',
                'resource_id': domain_name,
                'violations': violations
            }
        
        logger.info(f"Elasticsearch {domain_name} is compliant")
        return {
            'action': 'skip',
            'reason': 'compliant',
            'resource_id': domain_name
        }
    
    def validate_redshift_encryption(self, event_detail: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate Redshift cluster encryption configuration.
        
        Checks:
        - encrypted: true
        
        Args:
            event_detail: CloudTrail event detail
            
        Returns:
            Validation result with action and violations
        """
        response = event_detail.get('responseElements', {})
        cluster = response.get('cluster', {})
        cluster_id = cluster.get('clusterIdentifier', 'unknown')
        
        encrypted = cluster.get('encrypted', False)
        
        if not encrypted:
            logger.info(f"Redshift {cluster_id} is not encrypted")
            return {
                'action': 'proceed',
                'reason': 'violation',
                'resource_id': cluster_id,
                'violations': {
                    'encryption': 'disabled'
                }
            }
        
        logger.info(f"Redshift {cluster_id} is compliant")
        return {
            'action': 'skip',
            'reason': 'compliant',
            'resource_id': cluster_id
        }
    
    def validate_rds_encryption(self, event_detail: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate RDS DB instance encryption and accessibility configuration.
        
        Checks:
        - storageEncrypted: true
        - publiclyAccessible: false
        
        Args:
            event_detail: CloudTrail event detail
            
        Returns:
            Validation result with action and violations
        """
        response = event_detail.get('responseElements', {})
        db_instance_id = response.get('dBInstanceIdentifier', 'unknown')
        
        # Check if storage encryption is enabled
        encrypted = response.get('storageEncrypted', False)
        
        # Check if publicly accessible
        publicly_accessible = response.get('publiclyAccessible', False)
        
        violations = {}
        if not encrypted:
            violations['storage_encryption'] = 'disabled'
        if publicly_accessible:
            violations['publicly_accessible'] = 'enabled'
        
        if violations:
            logger.info(f"RDS {db_instance_id} violations: {violations}")
            return {
                'action': 'proceed',
                'reason': 'violation',
                'resource_id': db_instance_id,
                'violations': violations
            }
        
        logger.info(f"RDS {db_instance_id} is compliant")
        return {
            'action': 'skip',
            'reason': 'compliant',
            'resource_id': db_instance_id
        }
    
    def validate_rds_cluster_encryption(self, event_detail: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate RDS DB cluster (Aurora) encryption and accessibility configuration.
        
        Checks:
        - storageEncrypted: true
        - publiclyAccessible: false (checked via cluster endpoint)
        
        Args:
            event_detail: CloudTrail event detail
            
        Returns:
            Validation result with action and violations
        """
        response = event_detail.get('responseElements', {})
        # For clusters, the cluster info is nested under 'dBCluster'
        db_cluster = response.get('dBCluster', {})
        db_cluster_id = db_cluster.get('dBClusterIdentifier', response.get('dBClusterIdentifier', 'unknown'))
        
        # Check if storage encryption is enabled
        encrypted = db_cluster.get('storageEncrypted', response.get('storageEncrypted', False))
        
        # Check if publicly accessible (Aurora clusters inherit from instances)
        # For cluster creation, check if any endpoint is public
        publicly_accessible = db_cluster.get('publiclyAccessible', response.get('publiclyAccessible', False))
        
        violations = {}
        if not encrypted:
            violations['storage_encryption'] = 'disabled'
        if publicly_accessible:
            violations['publicly_accessible'] = 'enabled'
        
        if violations:
            logger.info(f"RDS Aurora Cluster {db_cluster_id} violations: {violations}")
            return {
                'action': 'proceed',
                'reason': 'violation',
                'resource_id': db_cluster_id,
                'violations': violations
            }
        
        logger.info(f"RDS Aurora Cluster {db_cluster_id} is compliant")
        return {
            'action': 'skip',
            'reason': 'compliant',
            'resource_id': db_cluster_id
        }
    
    def get_supported_events(self) -> List[str]:
        """
        Get list of supported CloudTrail event names.
        
        Returns:
            List of event names that have validators
        """
        return list(self.validators.keys())
    
    def is_supported(self, event_name: str) -> bool:
        """
        Check if an event name has a validator.
        
        Args:
            event_name: CloudTrail event name
            
        Returns:
            True if validator exists for this event
        """
        return event_name in self.validators
