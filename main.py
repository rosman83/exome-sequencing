# Import Packages
import boto3
import botocore.exceptions
import json
import scripts.deploy_omics as deploy_omics
from scripts.run_workflow import build_workflow

# Create AWS Client, S3 Client, and S3 Bucket
omics = deploy_omics.create_omics_client()
s3c = deploy_omics.create_s3_client()
staging = deploy_omics.create_s3_bucket('omics-staging')

# Bundle and build workflow
cfg = {
    "staging_uri": staging,
    "region_name": boto3.session.Session().region_name,
}

workflow = build_workflow(omics, s3c, cfg, 'fastqs-to-analysis-ready-bam')

# Logging
print('Done')


