import json
from datetime import datetime
import glob
import io
import os
from pprint import pprint
from textwrap import dedent
from time import sleep
from urllib.parse import urlparse
from zipfile import ZipFile, ZIP_DEFLATED

import boto3
import botocore.exceptions

# Create a service IAM role 

dt_fmt = '%Y%m%dT%H%M%S'
ts = datetime.now().strftime(dt_fmt)

iam = boto3.client('iam')
role = iam.create_role(
    RoleName=f"OmicsServiceRole-{ts}",
    AssumeRolePolicyDocument=json.dumps({
        "Version": "2012-10-17",
        "Statement": [{
            "Principal": {
                "Service": "omics.amazonaws.com"
            },
            "Effect": "Allow",
            "Action": "sts:AssumeRole"
        }]
    }),
    Description="HealthOmics service role",
)

AWS_ACCOUNT_ID = boto3.client('sts').get_caller_identity()['Account']

policy_s3 = iam.create_policy(
    PolicyName=f"omics-s3-access-{ts}",
    PolicyDocument=json.dumps({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:PutObject",
                    "s3:Get*",
                    "s3:List*",
                ],
                "Resource": [
                    "arn:aws:s3:::*/*"
                ]
            }
        ]
    })
)

policy_logs = iam.create_policy(
    PolicyName=f"omics-logs-access-{ts}",
    PolicyDocument=json.dumps({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup"
                ],
                "Resource": [
                    f"arn:aws:logs:*:{AWS_ACCOUNT_ID}:log-group:/aws/omics/WorkflowLog:*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "logs:DescribeLogStreams",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                "Resource": [
                    f"arn:aws:logs:*:{AWS_ACCOUNT_ID}:log-group:/aws/omics/WorkflowLog:log-stream:*"
                ]
            }
        ]
    })
)

for policy in (policy_s3, policy_logs):
    _ = iam.attach_role_policy(
        RoleName=role['Role']['RoleName'],
        PolicyArn=policy['Policy']['Arn']
    )

# AWS HealthOmics Workflow

