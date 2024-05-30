import boto3
import botocore.exceptions
import json
import scripts.deploy_omics as deploy_omics
from scripts.run_workflow import build_workflow

# Create AWS Client
omics = deploy_omics.create_omics_client()
s3c = deploy_omics.create_s3_client()
staging = deploy_omics.create_s3_bucket('omics-staging')

cfg = {
    "staging_uri": staging,
    "region_name": boto3.session.Session().region_name,
}

workflow = build_workflow(omics, s3c, cfg, 'fastqs-to-analysis-ready-bam')

print('Done')

# First step is going to be exome sequencing Fastq to mapping to variant call file (vcf) to mutation annotation file (Maf) for mouse genome

