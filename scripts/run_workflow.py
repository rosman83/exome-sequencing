import configparser
from base64 import b64decode
from datetime import datetime, timezone
import glob
import io
import json
import os
from textwrap import dedent
from time import sleep
from urllib.parse import urlparse
import warnings
from zipfile import ZipFile, ZIP_DEFLATED

import boto3
import botocore
import yaml

# workflow building

def _write_artifact(obj, path: str) -> None:
        print(f"creating build artifact: {path}")
        with open(path, "w") as f:
            json.dump(obj, f, indent=4, default=str)

def bundle_workflow(
    workflow_name, workflow_root_dir, target_zip="build/bundle-{workflow_name}.zip"
):
    target_zip = target_zip.format(workflow_name=workflow_name)
    print(f"creating zip bundle for workflow '{workflow_name}': {target_zip}")

    buffer = io.BytesIO()
    with ZipFile(buffer, mode="w", compression=ZIP_DEFLATED) as zf:
        for file in glob.iglob(os.path.join(workflow_root_dir, "**/*"), recursive=True):
            if os.path.isfile(file):
                arcname = file.replace(os.path.join(workflow_root_dir, ""), "")
                print(f".. adding: {file} -> {arcname}")
                zf.write(file, arcname=arcname)

    # write out the zip file but preserve the buffer for later use
    with open(target_zip, "wb") as f:
        f.write(buffer.getvalue())

    return buffer

def build_workflow(omics, s3c, cfg, workflow_name) -> None:
    # create zip file
    buffer = bundle_workflow(workflow_name, f"workflows/{workflow_name}")

    # check the size of the buffer, if more than 4MiB it needs to be staged to S3
    buffer.seek(0, 2)
    definition_uri = None
    if buffer.tell() / 1024.0 > 4.0:
        staging_uri = cfg["staging_uri"]

        definition_uri = urlparse(
            "/".join([staging_uri, f"bundle-{workflow_name}.zip"])
        )
        print(f"staging workflow definition to {definition_uri.geturl()}")

        s3c.put_object(
            Body=buffer.getvalue(),
            Bucket=definition_uri.netloc,
            Key=definition_uri.path[1:],
        )

    # register workflow (use provided cli-input-yaml)
    with open(f"workflows/{workflow_name}/cli-input.yaml", "r") as f:
        cli_input = yaml.safe_load(f)

    with open(f"workflows/{workflow_name}/parameter-template.json", "r") as f:
        parameter_template = json.load(f)

    request_args = {"parameterTemplate": parameter_template}

    if definition_uri:
        request_args |= {"definitionUri": definition_uri.geturl()}
    else:
        request_args |= {"definitionZip": buffer.getvalue()}

    request_args |= cli_input
    response = omics.create_workflow(**request_args)
    workflow_id = response["id"]

    # wait for workflow to be active
    # let the build fail if there's an error here
    try:
        waiter = omics.get_waiter("workflow_active")
        waiter.wait(id=workflow_id)

        workflow = omics.get_workflow(id=workflow_id)
        _write_artifact(workflow, f"build/workflow-{workflow_name}")
    except botocore.exceptions.WaiterError as e:
        response = omics.get_workflow(id=workflow_id)
        cause = response["statusMessage"]

        print(f"Encountered the following error: {e}\n\nCause:\n{cause}")

        raise RuntimeError

# workflow running

def build_run(omics, session, cfg, workflow_name) -> None:
    profile = session.profile_name
    region_name = cfg["region"]

    # merge test parameters with build/ecr-registry asset
    # workflows have ecr_registry parameterized
    ecr_registry = {"ecr_registry": cfg["ecr_registry"]}
    staging_uri = cfg["staging_uri"]
    output_uri = cfg["output_uri"]
    account_id = cfg["account_id"]

    with open(f"workflows/{workflow_name}/test.parameters.json", "r") as f:
        test_parameters = f.read()

    test_parameters = test_parameters.replace("{{region}}", region_name)
    test_parameters = test_parameters.replace("{{staging_uri}}", staging_uri)
    test_parameters = test_parameters.replace("{{account_id}}", account_id)
    test_parameters = json.loads(test_parameters)

    test_parameters |= ecr_registry | {"aws_region": region_name}

    # get workflow-id from build asset
    with open(f"build/workflow-{workflow_name}", "r") as f:
        workflow_id = json.load(f)["id"]

    # get role arn from build asset
    with open(f"build/iam-workflow-role", "r") as f:
        workflow_role_arn = json.load(f)["Arn"]

    omics = session.client("omics")
    run = omics.start_run(
        workflowId=workflow_id,
        name=f"test: {workflow_name}",
        roleArn=workflow_role_arn,
        outputUri=output_uri,
        parameters=test_parameters,
    )

    # write out final test parameters for tracking
    _write_artifact(test_parameters, f"build/parameters-{workflow_name}.json")

    check_command = f"aws omics get-run --id {run['id']} --region {region_name}"
    if profile:
        check_command += f" --profile {profile}"

    print(
        dedent(
            f"""
            successfully started run '{run['id']}':
            
            {run}
            
            using parameters:
            {test_parameters}
            
            to check on the status of this run you can use the following command:
            $ {check_command}
            """
        ).strip()
    )
