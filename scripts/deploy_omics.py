# functions to connect to AWS services

import boto3
import botocore.exceptions
import json

def create_omics_client():
    omics_iam_name = "OmicsServiceRole"
    iam = boto3.resource("iam")

    try:
        role = iam.Role("OmicsServiceRole")
        role.load()
        print('[aws] using role', role.role_name.lower())

    except iam.meta.client.exceptions.NoSuchEntityException as ex:
        if ex.response["Error"]["Code"] == "NoSuchEntity":
            role = iam.create_role(
                RoleName=omics_iam_name,
                AssumeRolePolicyDocument=json.dumps(
                    {
                        "Version": "2012-10-17",
                        "Statement": [
                            {
                                "Effect": "Allow",
                                "Principal": {"Service": "omics.amazonaws.com"},
                                "Action": "sts:AssumeRole",
                            }
                        ],
                    }
                ),
                Description="HealthOmics service role",
            )

            policy = iam.create_policy(
                PolicyName="{}-policy".format(omics_iam_name),
                Description="Policy for AWS HealthOmics demo",
                PolicyDocument=json.dumps(
                    {
                        "Version": "2012-10-17",
                        "Statement": [
                            {"Effect": "Allow", "Action": ["omics:*"], "Resource": "*"},
                            {
                                "Effect": "Allow",
                                "Action": [
                                    "ram:AcceptResourceShareInvitation",
                                    "ram:GetResourceShareInvitations",
                                ],
                                "Resource": "*",
                            },
                            {
                                "Effect": "Allow",
                                "Action": [
                                    "s3:GetBucketLocation",
                                    "s3:PutObject",
                                    "s3:GetObject",
                                    "s3:ListBucket",
                                    "s3:AbortMultipartUpload",
                                    "s3:ListMultipartUploadParts",
                                    "s3:GetObjectAcl",
                                    "s3:PutObjectAcl",
                                ],
                                "Resource": "*",
                            },
                        ],
                    }
                ),
            )

            policy.attach_role(
                RoleName=role["Role"]["RoleName"],
                PolicyArn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
            )
            print(role["Role"]["RoleName"])
        else:
            print(
                "Something went wrong, please retry and check your account settings and permissions"
            )

    region = boto3.session.Session().region_name
    omics = boto3.client('omics', region_name=region)
    
    return omics

# Create S3 client
def create_s3_client():
    s3c = boto3.client('s3')
    return s3c

# create s3 bucket and if exists return staging url
def create_s3_bucket(bucket_name):
    s3c = create_s3_client()
    try:
        s3c.create_bucket(Bucket=bucket_name)
    except botocore.exceptions.ClientError as ex:
        if ex.response["Error"]["Code"] == "BucketAlreadyOwnedByYou":
            print(f"[aws] bucket {bucket_name} already exists")
        else:
            print(f"[aws] failed to create bucket {bucket_name}")
            raise ex

    return f"s3://{bucket_name}"