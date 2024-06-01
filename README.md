# exome-sequencing

Workflow to carry out exome sequencing through AWS HealthOmics - specifically for the mouse genome.

## quickstart

**Ensure that you have the following prerequesites on your PC:**
- Python 3.12.*
- PDM (Python dependency Manager)
- AWS CLI (Command Line Interface)
- AWS CDK (Cloud Development Kit)

These instructions currently assume you have grabbed all needed docker images to the omics container following [these steps](https://github.com/aws-samples/amazon-ecr-helper-for-aws-healthomics). **Instructions to do this or a helper script will be created soon.**

The images required are ready for pushing through the ECR helper in `docker/container_pull_manifest.json`.

```
# Setup repository and libraries
git clone https://github.com/rosman83/exome-sequencing
cd exome-sequencing
pdm install && pdm update

# ensure that you fill out config.toml properly
...

# Upload workflows, setup S3, permissions, AWS
pdm run run_setup.py

# Run the workflow given test parameters in workflows/{{name}}/test.parameters.json
pdm run run_task.py
```

## the general idea

We go from fastq -> ubam -> vcf, but instead using the mouse genome reference files.

## the code

We use a few python scripts in ./scripts to setup initialy things like aws permissions, and eventually develop and bundle the workflows folder. Dedicated instructions will come soon after published work.

## credits
this work is making heavy use of the existing gatk published workflow for fastq conversion into analysis ready bam, and is modified to work for the mouse genome instead of the human genome coding.