# Import Packages
import boto3
import botocore.exceptions
import json
import scripts.deploy_omics as deploy_omics
from scripts.run_workflow import build_workflow, build_run

# Create AWS Client, S3 Client, and S3 Bucket
omics = deploy_omics.create_omics_client()
s3c = deploy_omics.create_s3_client()
staging = deploy_omics.create_s3_bucket('omics-staging')

# Bundle and build workflow
account_id = boto3.client('sts').get_caller_identity().get('Account')
region_name = boto3.session.Session().region_name
print('region:', region_name)

cfg = {
    "staging_uri": staging,
    "region_name": region_name,
    # additional parameters
    "account_id": account_id,
    "ecr_registry": f'{account_id}.dkr.ecr.{region_name}.amazonaws.com',
    "output_uri": "s3://omics-output",
    "region": boto3.session.Session().region_name,
}
print('configuring workflow for region:', boto3.session.Session().region_name)
workflow = build_workflow(omics, s3c, cfg, 'to_bam')

# Run workflow
demo_run = False

if demo_run:
    build_run(omics, boto3.session.Session(), cfg, 'to_bam')
# Logging
print('Done')


