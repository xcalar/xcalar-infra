import os
import json
import boto3

EC2 = boto3.client('ec2')
LAUNCH_TEMPLATE_ID = os.getenv('LAUNCH_TEMPLATE_ID', '')
LAUNCH_TEMPLATE = os.getenv('LAUNCH_TEMPLATE', 'xcondemand-XcalarLaunchTemplate')
S3BUCKET = os.getenv('S3BUCKET')
USER_DATA = os.getenv('USER_DATA', None)


def _make_reply(code, message, qp):
    return {"status": code, "body": json.dumps({"message": message, "qp": qp})}

def _http_status(resp):
    return resp["ResponseMetadata"]["HTTPStatusCode"]


def _flatten(lst):
    return [item for sublist in lst for item in sublist]


def _response_ec2_instance_ids(resp):
    resvs = resp.get("Reservations", None)
    if not resvs:
        return []
    instances = _flatten([resv["Instances"] for resv in resvs])
    return [instance["InstanceId"] for instance in instances]


def _get_cluster_instance_ids(cluster_name, tag_key="ClusterName"):
    describe_response = EC2.describe_instances(
        Filters=[{
            "Name": "tag:{}".format(tag_key),
            "Values": [cluster_name]
        }, {
            "Name": "instance-state-name",
            "Values": ["pending", "running"]
        }])

    return _response_ec2_instance_ids(
        describe_response)

def _dry_run(qp):
    return qp.has_key('dry_run')

def create_cluster(qp):
    count = int(qp.get('count'))
    name = qp.get('name', 'xcondemand')
    cluster_name = qp.get('cluster_name', '{}-cluster'.format(name))
    #launch_templates = EC2.describe_launch_templates(LaunchTemplateIds=[LAUNCH_TEMPLATE_ID])
    launch_templates = EC2.describe_launch_templates(
        LaunchTemplateNames=[LAUNCH_TEMPLATE])
    version = launch_templates['LaunchTemplates'][0]['LatestVersionNumber']

    instance_ids = _get_cluster_instance_ids(cluster_name)
    if instance_ids:
        return _make_reply(
            400, "Existing cluster has running instances: {}".format(
                ','.join(instance_ids)), qp)

    block_device_mappings = [{
        "DeviceName": "/dev/xvda1",
        "Ebs": {
            "VolumeSize": 32
        }
    }]
    run_resp = EC2.run_instances(
        LaunchTemplate={
            "LaunchTemplateName": LAUNCH_TEMPLATE,
            "Version": str(version)
        },
        MinCount=count,
        MaxCount=count,
        TagSpecifications=[{
            "ResourceType":
            "instance",
            "Tags": [{
                "Key": "ClusterName",
                "Value": cluster_name
            }, {
                "Key": "Name",
                "Value": name
            }]
        },
        {
            "ResourceType":
            "volume",
            "Tags": [
                {
                    "Key": "ClusterName",
                    "Value": cluster_name
                    },
                {
                    "Key": "Name",
                    "Value": name
                    },
                ]
            }],
    )

    return _make_reply(
        _http_status(run_resp),
        "Launched {} instances using version {} of {} template".format(
            count, version, LAUNCH_TEMPLATE_ID), qp)


def stop_cluster(qp):
    name = qp.get('name', 'xcondemand')
    cluster_name = qp.get('cluster_name', '{}-cluster'.format(name))
    instance_ids = _get_cluster_instance_ids(cluster_name)
    stop_resp = EC2.stop_instances(InstanceIds=instance_ids, DryRun=_dry_run(qp))
    return _make_reply(
        _http_status(stop_resp),
        'Stopped instances {}'.format(','.join(instance_ids)), qp)


def delete_cluster(qp):
    name = qp.get('name', 'xcondemand')
    cluster_name = qp.get('cluster_name', '{}-cluster'.format(name))
    instance_ids = _get_cluster_instance_ids(cluster_name)
    terminate_resp = EC2.terminate_instances(InstanceIds=instance_ids, DryRun=_dry_run(qp))
    return _make_reply(
        _http_status(terminate_resp),
        'Terminated instances {}'.format(','.join(instance_ids)), qp)

def lambda_handler(event, context):
    if event:
        qp = event.get('queryStringParameters', {})
    else:
        qp = {}

    command = qp.get('command', None)

    try:
        if command == 'create_cluster':
            reply = create_cluster(qp)
        elif command == 'stop_cluster':
            reply = stop_cluster(qp)
        elif command == 'delete_cluster':
            reply = delete_cluster(qp)
        elif command is None:
            reply = _make_reply(400, "Command not specified", qp)
        else:
            reply = _make_reply(400, "Invalid command: %s" % command, qp)
    except Exception as exc_info:
        print(exc_info)
        reply = _make_reply(400, "Exception has occurred: {}".format(exc_info),
                           qp)

    return reply
