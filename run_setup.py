# Description: This file is used to setup the AWS environment for the first time. If ran multiple times with the same settings, it will skip over completed steps.
import glob
import io
import os
from urllib.parse import urlparse
from zipfile import ZIP_DEFLATED, ZipFile
from loguru import logger
import boto3
import botocore.exceptions
import json
from botocore.config import Config
import toml
import yaml

# Reading the configuration file
config = toml.load("config.toml")
if "aws" not in config:
    raise RuntimeError("AWS configuration not found in config.toml")

# Reading AWS specific configuration
aws_config = config["aws"]

if "region" not in aws_config:
    raise RuntimeError("AWS region not found in config.toml")
if "bucket" not in aws_config:
    raise RuntimeError("AWS account_id not found in config.toml")
if "role" not in aws_config:
    raise RuntimeError("AWS role not found in config.toml")

region = aws_config["region"]
bucket = aws_config["bucket"]
role = aws_config["role"]
logger.info("Configuration file loaded.")
# Create AWS clients to use throughout setup
sts_client = boto3.client("omics", region)
iam_client = boto3.client("iam", region)
s3_client = boto3.client("s3", region)
stepfunctions_client = boto3.client("stepfunctions", region)
ecr_client = boto3.client("ecr", region)


# Create AWS role with healthomics and administrator access if role does not exist by name checking
def create_role(role_name):
    try:
        role = iam_client.get_role(RoleName=role_name)
        logger.info("Role {} already exists, skipping creation.", role_name)
        return role["Role"]["Arn"]
    except iam_client.exceptions.NoSuchEntityException:
        role = iam_client.create_role(
            RoleName=role_name,
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
        iam_client.attach_role_policy(
            RoleName=role_name,
            PolicyArn="arn:aws:iam::aws:policy/AdministratorAccess",
        )
        logger.info("Created service role {}.", role_name)
        return role["Role"]["Arn"]

create_role(role)


# Automate image ECR Repo creation
# TODO: FIX ECR REPO NOT BEING CREATED
def create_bucket(bucket_name):
    try:
        s3_client.head_bucket(Bucket=bucket_name)
        logger.info("S3 bucket {} already exists, skipping creation.", bucket_name)
        return bucket_name
    except botocore.exceptions.ClientError as e:
        error_code = int(e.response["Error"]["Code"])
        if error_code == 404:
            s3_client.create_bucket(Bucket=bucket_name)
            logger.info("Created S3 bucket {}.", bucket_name)
            return bucket_name

create_bucket(bucket)

# Create ECR repository and grab images using state function
# basically aws stepfunctions start-execution \
#   --state-machine-arn arn:aws:states:<aws-region>:<aws-account-id>:stateMachine:omx-container-puller \
#   --input file://container_pull_manifest.json
# but using boto3
repo_name = 
def create_ecr_repo(repo_name):
    try:
        ecr_client.create_repository(repositoryName=repo_name)
        logger.info("Created ECR repository {}.", repo_name)
    except ecr_client.exceptions.RepositoryAlreadyExistsException:
        logger.info("ECR repository {} already exists, skipping creation.", repo_name)

# Build and upload workflow to AWS
def bundle_workflow(
    workflow_name, workflow_root_dir, target_zip="build/bundle-{workflow_name}.zip"
):
    target_zip = target_zip.format(workflow_name=workflow_name)
    buffer = io.BytesIO()
    with ZipFile(buffer, mode="w", compression=ZIP_DEFLATED) as zf:
        for file in glob.iglob(os.path.join(workflow_root_dir, "**/*"), recursive=True):
            if os.path.isfile(file):
                arcname = file.replace(os.path.join(workflow_root_dir, ""), "")
                zf.write(file, arcname=arcname)

    # write out the zip file but preserve the buffer for later use
    with open(target_zip, "wb") as f:
        f.write(buffer.getvalue())

    return buffer


# return the workflow id
workflow_name = "to_bam"


def build_workflow():
    existing_workflows = sts_client.list_workflows()
    workflow_names = [item.get("name") for item in existing_workflows["items"]]

    if workflow_name in workflow_names:
        logger.info(f"Workflow {workflow_name} already exists, skipping creation.")
        return

    buffer = bundle_workflow(workflow_name, f"workflows/{workflow_name}")
    buffer.seek(0, 2)
    definition_uri = None
    if buffer.tell() / 1024.0 > 4.0:
        staging_uri = f"s3://{bucket}"
        definition_uri = urlparse(
            "/".join([staging_uri, f"bundle-{workflow_name}.zip"])
        )
        logger.info(f"Staging workflow definition to {definition_uri.geturl()}")
        s3_client.put_object(
            Body=buffer.getvalue(),
            Bucket=definition_uri.netloc,
            Key=definition_uri.path[1:],
        )
    with open(f"workflows/{workflow_name}/parameter-template.json", "r") as f:
        parameter_template = json.load(f)
    request_args = {"parameterTemplate": parameter_template}
    if definition_uri:
        request_args |= {"definitionUri": definition_uri.geturl()}
    else:
        request_args |= {"definitionZip": buffer.getvalue()}
    response = sts_client.create_workflow(**request_args)
    workflow_id = response["id"]
    try:
        waiter = sts_client.get_waiter("workflow_active")
        waiter.wait(id=workflow_id)
        workflow = sts_client.get_workflow(id=workflow_id)
        obj = workflow
        path = f"build/workflow-{workflow_name}"
        with open(path, "w") as f:
            json.dump(obj, f, indent=4, default=str)

    except botocore.exceptions.WaiterError as e:
        response = sts_client.get_workflow(id=workflow_id)
        cause = response["statusMessage"]
        logger.error(f"Encountered the following error: {e}\n\nCause:\n{cause}")
        raise RuntimeError

    return workflow_id


workflow_id = build_workflow()
logger.info(f"Workflow {workflow_name} created with id {workflow_id}")


# start a run of the workflow
def start_run() -> None:
    with open(f"workflows/{workflow_name}/test.parameters.json", "r") as f:
        test_parameters = f.read()
    test_parameters = test_parameters.replace("{{region}}", region)
    test_parameters = test_parameters.replace("{{staging_uri}}", bucket)
    test_parameters = test_parameters.replace(
        "{{account_id}}", aws_config["account_id"]
    )
    test_parameters = json.loads(test_parameters)
    test_parameters |= {"aws_region": region}
    role_arn = aws_config["role"]
    try:
        role = iam_client.get_role(RoleName=role_arn)
        role_arn = role["Role"]["Arn"]
    except iam_client.exceptions.NoSuchEntityException:
        raise RuntimeError(f"Role {role_arn} not found")
    ecr_registry = f"{aws_config['account_id']}.dkr.ecr.{region}.amazonaws.com"
    test_parameters |= {"ecr_registry": ecr_registry}
    run = sts_client.start_run(
        workflowId=workflow_id,
        name=f"test: {workflow_name}",
        roleArn=role_arn,
        outputUri=f"s3://{bucket}",
        parameters=test_parameters,
    )
    logger.success(f"Successfully started run '{run['id']}'")
    check_command = f"aws omics get-run --id {run['id']} --region {region}"
    logger.info(f"Run details: {run}")
    logger.info(f"Using parameters: {test_parameters}")
    logger.info(f"Check run status with: {check_command}")


start_run()
