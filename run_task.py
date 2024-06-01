# Description: This file intiates a run of the workflow, assuming setup is already complete, and uses the parameters that are included within the workflow folder. This is the same as initiating a run through the GUI interface of the AWS console through healthomics.
import json
import boto3
import botocore
from loguru import logger
import toml

def start_workflow() -> None:
    workflow_name = "to_bam"
    config = toml.load("config.toml")
    region = config["aws"]["region"]
    session = boto3.Session(region_name=region)
    omics = session.client("omics")
    response = omics.list_workflows()
    workflow_id = None
    for item in response["items"]:
        if item["name"] == workflow_name:
            workflow_id = item["id"]
            break
    if workflow_id is None:
        raise RuntimeError(f"Workflow {workflow_name} not found")
    response = omics.get_workflow(id=workflow_id)

    with open(f"workflows/{workflow_name}/test.parameters.json", "r") as f:
        test_parameters = f.read()
    
    test_parameters = test_parameters.replace("{{region}}", region)
    test_parameters = test_parameters.replace("{{staging_uri}}", config["aws"]["bucket"])
    test_parameters = test_parameters.replace("{{account_id}}", config["aws"]["account_id"])
    test_parameters = json.loads(test_parameters)
    test_parameters |= {"aws_region": region}
    
    role_arn = config["aws"]["role"]
    try:
        role = session.client("iam").get_role(RoleName=role_arn)
        role_arn = role["Role"]["Arn"]
    except session.client("iam").exceptions.NoSuchEntityException:
        raise RuntimeError(f"Role {role_arn} not found")
    
    # add ecr registry to test parameters
    ecr_registry=f"{config["aws"]["account_id"]}.dkr.ecr.{region}.amazonaws.com"
    test_parameters |= {"ecr_registry": ecr_registry}
    run = omics.start_run(
        workflowId=workflow_id,
        name=f"test: {workflow_name}",
        roleArn=role_arn,
        outputUri=f"s3://{config["aws"]["bucket"]}",
        parameters=test_parameters
    )

    logger.success(f"Successfully started run '{run['id']}'")
    profile = session.profile_name
    check_command = f"aws omics get-run --id {run['id']} --region {region}"
    if profile:
        check_command += f" --profile {profile}"
    logger.info(f"Run details: {run}")
    logger.info(f"Using parameters: {test_parameters}")
    logger.info(f"Check run status with: {check_command}")

if __name__ == "__main__":
    start_workflow()
    

