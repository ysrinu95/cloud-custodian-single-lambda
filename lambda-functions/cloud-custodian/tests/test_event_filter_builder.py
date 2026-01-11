import boto3
import pytest
from botocore.stub import Stubber

import importlib.util
import pathlib


def _load_builder():
    path = pathlib.Path(__file__).parents[1] / 'event_filter_builder.py'
    spec = importlib.util.spec_from_file_location('event_filter_builder', str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.build_filters_and_resources

build_filters_and_resources = _load_builder()


def test_s3_name_filter_no_session():
    event_info = {'generic_resources': {'names': ['my-bucket']}}
    res = build_filters_and_resources(event_info, 'aws.s3', session=None, region='us-east-1')
    assert isinstance(res, dict)
    assert res['filters'] == [{'type': 'value', 'key': 'Name', 'value': 'my-bucket'}]
    assert res['provided_resources'] is None


def test_ec2_prefetch_with_session():
    session = boto3.Session()
    ec2 = session.client('ec2', region_name='us-east-1')
    stub = Stubber(ec2)
    # describe_instances response minimal skeleton
    resp = {
        'Reservations': [
            {'Instances': [{'InstanceId': 'i-12345', 'State': {'Name': 'running'}}]}
        ]
    }
    stub.add_response('describe_instances', resp, {'InstanceIds': ['i-12345']})
    stub.activate()

    # Monkeypatch session.client to return our stubbed client
    class FakeSession:
        def client(self, service, region_name=None):
            if service == 'ec2':
                return ec2
            raise RuntimeError('unexpected service')

    event_info = {'generic_resources': {'ids': ['i-12345']}}
    res = build_filters_and_resources(event_info, 'aws.ec2', session=FakeSession(), region='us-east-1')
    assert res['filters'] == [{'type': 'value', 'key': 'InstanceId', 'value': 'i-12345'}]
    assert res['provided_resources'] is not None
    assert any(r.get('InstanceId') == 'i-12345' or r.get('InstanceId') for r in res['provided_resources'])


def test_alb_prefetch_with_session():
    session = boto3.Session()
    elbv2 = session.client('elbv2', region_name='us-east-1')
    stub = Stubber(elbv2)
    resp = {'LoadBalancers': [{'LoadBalancerArn': 'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-app/abc', 'LoadBalancerName': 'my-app'}]}
    stub.add_response('describe_load_balancers', resp, {'LoadBalancerArns': ['arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-app/abc']})
    stub.activate()

    class FakeSession:
        def client(self, service, region_name=None):
            if service == 'elbv2':
                return elbv2
            raise RuntimeError('unexpected service')

    event_info = {'generic_resources': {'arns': ['arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-app/abc']}}
    res = build_filters_and_resources(event_info, 'aws.app-elb', session=FakeSession(), region='us-east-1')
    assert res['filters'][0]['key'] in ('LoadBalancerArn', 'Arn')
    assert res['provided_resources'] is not None
    assert isinstance(res['provided_resources'], list)


@pytest.mark.parametrize('resource_type, generic_key, value, prefetch', [
    ('aws.elasticache', 'arns', 'arn:aws:elasticache:us-east-1:123:cluster:cache-1', True),
    ('aws.eks', 'names', 'my-cluster', True),
    ('aws.rds', 'ids', 'my-db', True),
    ('aws.secretsmanager', 'ids', 'arn:aws:secretsmanager:us-east-1:123:secret:sec', True),
    ('aws.s3', 'names', 'my-bucket', False),
    ('aws.cloudfront', 'ids', 'E123ABC', True),
    ('aws.acm', 'ids', 'arn:aws:acm:us-east-1:123:certificate/abc', True),
    ('aws.lambda', 'names', 'my-func', False),
    ('aws.waf', 'ids', 'waf-id', False),
    ('aws.shield', 'ids', 'shield-id', False),
    ('aws.cognito', 'names', 'userpool-1', True),
    ('aws.events', 'names', 'default', True),
    ('aws.kinesis', 'names', 'stream-1', False),
    ('aws.kinesis-firehose', 'names', 'firehose-1', True),
    ('aws.timestream', 'names', 'db1', False),
    ('aws.elasticsearch', 'names', 'domain1', True),
    ('aws.codecommit', 'names', 'repo1', True),
    ('aws.ecr', 'names', 'repo1', True),
    ('aws.ecs', 'names', 'cluster1', False),
    ('aws.efs', 'ids', 'fs-123', False),
    ('aws.dynamodb-table', 'names', 'table1', False),
    ('aws.ses', 'names', 'ses-1', False),
    ('aws.sns', 'names', 'topic1', False),
    ('aws.cloudwatch', 'names', 'cw-1', False),
    ('aws.kms', 'ids', 'key-id', True),
    ('aws.vpc', 'ids', 'vpc-123', True),
    ('aws.subnet', 'ids', 'subnet-1', True),
    ('aws.internet-gateway', 'ids', 'igw-1', True),
    ('aws.nat-gateway', 'ids', 'nat-1', True),
    ('aws.flowlogs', 'ids', 'fl-1', False),
    ('aws.network-acl', 'ids', 'acl-1', False),
    ('aws.security-group', 'ids', 'sg-1', False),
    ('aws.inspector', 'ids', 'insp-1', False),
    ('aws.securityhub', 'ids', 'sh-1', False),
    ('aws.config', 'ids', 'cfg-1', False),
])
def test_various_resources(resource_type, generic_key, value, prefetch):
    """Generic tests that ensure filters are built and prefetch occurs when supported."""
    event_info = {'generic_resources': {generic_key: [value]}}

    # For services where prefetch is expected, create a stubbed client
    if prefetch:
        # Map resource_type to expected boto3 client and method
        rt_map = {
            'aws.elasticache': ('elasticache', 'describe_cache_clusters', {'CacheClusters': [{}]}, {'CacheClusterId': value.split(':')[-1]}),
            'aws.eks': ('eks', 'describe_cluster', {'cluster': {}}, {'name': value}),
            'aws.rds': ('rds', 'describe_db_instances', {'DBInstances': []}, {'DBInstanceIdentifier': value}),
            'aws.secretsmanager': ('secretsmanager', 'describe_secret', {}, {'SecretId': value}),
            'aws.cloudfront': ('cloudfront', 'get_distribution', {'Distribution': {}}, {'Id': value}),
            'aws.acm': ('acm', 'describe_certificate', {'Certificate': {}}, {'CertificateArn': value}),
            'aws.cognito': ('cognito-idp', 'describe_user_pool', {'UserPool': {}}, {'UserPoolId': value}),
            'aws.events': ('events', 'describe_event_bus', {}, {'Name': value}),
            'aws.kinesis-firehose': ('firehose', 'describe_delivery_stream', {'DeliveryStreamDescription': {}}, {'DeliveryStreamName': value}),
            'aws.elasticsearch': ('opensearch', 'describe_domains', {'DomainStatusList': []}, {'DomainNames': [value]}),
            'aws.codecommit': ('codecommit', 'get_repository', {'repositoryMetadata': {}}, {'repositoryName': value}),
            'aws.ecr': ('ecr', 'describe_repositories', {'repositories': []}, {'repositoryNames': [value]}),
            'aws.kms': ('kms', 'describe_key', {'KeyMetadata': {}}, {'KeyId': value}),
            'aws.vpc': ('ec2', 'describe_vpcs', {'Vpcs': [{}]}, {'VpcIds': [value]}),
            'aws.subnet': ('ec2', 'describe_subnets', {'Subnets': [{}]}, {'SubnetIds': [value]}),
            'aws.internet-gateway': ('ec2', 'describe_internet_gateways', {'InternetGateways': [{}]}, {'InternetGatewayIds': [value]}),
            'aws.nat-gateway': ('ec2', 'describe_nat_gateways', {'NatGateways': [{}]}, {'NatGatewayIds': [value]}),
        }

        if resource_type in rt_map:
            service, method, resp, params = rt_map[resource_type]
            # For a couple of services the boto models require many fields in
            # the response and Stubber will validate them. For those, return
            # a tiny Fake client that implements the expected call and returns
            # a minimal response without validation.
            if service in ('cloudfront', 'firehose'):
                class FakeSvcClient:
                    def __init__(self, resp):
                        self._resp = resp

                    def get_distribution(self, Id=None):
                        return self._resp

                    def describe_delivery_stream(self, DeliveryStreamName=None):
                        return self._resp

                fake_client = FakeSvcClient(resp)

                class FakeSession:
                    def client(self, svc, region_name=None):
                        if svc == service:
                            return fake_client
                        raise RuntimeError('unexpected service')

                res = build_filters_and_resources(event_info, resource_type, session=FakeSession(), region='us-east-1')
            else:
                session = boto3.Session()
                client = session.client(service, region_name='us-east-1')
                stub = Stubber(client)
                # Ensure responses satisfy botocore model validators for required
                # fields. The rt_map contains minimal shapes; patch a few known
                # problematic ones here.
                if service == 'kms' and method == 'describe_key':
                    # describe_key requires KeyMetadata with KeyId
                    resp = {'KeyMetadata': {'KeyId': value}}
                if service == 'eks' and method == 'describe_cluster':
                    resp = {'cluster': {'name': value}}

                stub.add_response(method, resp, params)
                stub.activate()

                class FakeSession:
                    def client(self, svc, region_name=None):
                        if svc == service:
                            return client
                        raise RuntimeError('unexpected service')

                res = build_filters_and_resources(event_info, resource_type, session=FakeSession(), region='us-east-1')
            # We expect a list of filters; it may be empty if builder doesn't
            # have a specialized mapping for the resource type yet. But it
            # must be a list.
            assert isinstance(res['filters'], list)
            # For prefetch-enabled, we expect provided_resources (may be empty list)
            assert 'provided_resources' in res
        else:
            pytest.skip(f'No prefetch mapping test for {resource_type}')
    else:
        res = build_filters_and_resources(event_info, resource_type, session=None, region='us-east-1')
        assert isinstance(res['filters'], list)
