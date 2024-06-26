# exome-sequencing

Workflow to carry out exome sequencing through AWS HealthOmics - specifically for the mouse genome.

## quickstart

### Docker Images Setup

**Ensure that you have the following prerequesites on your PC:**
- Python 3.12.*
- PDM (Python dependency Manager)
- AWS CLI (Command Line Interface)
- AWS CDK (Cloud Development Kit)

1. These instructions currently assume you have grabbed all needed docker images to the omics container following [these steps](https://github.com/aws-samples/amazon-ecr-helper-for-aws-healthomics). **Instructions to do this or a helper script will be created soon.**
2. The images required for the tool are ready for pushing through the ECR helper in `docker/container_pull_manifest.json`.
3. Once the repositories can be seen in Amazon Elastic Container Registry -> Private Repositories, in your AWS console dashboard, select each image that matches those uploaded from container_pull_manifest.json, and go to Actions -> Permissions and add the following permissions policy for each image.

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "omics workflow",
      "Effect": "Allow",
      "Principal": {
        "Service": "omics.amazonaws.com"
      },
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ]
    }
  ]
}
```

We are now ready to proceed with healthomics and running workflows.

### Healthomics Setup

```
# Setup repository and libraries
git clone https://github.com/rosman83/exome-sequencing
cd exome-sequencing
pdm install && pdm update

# ensure that you fill out config.toml properly
...
# Setup AWS -> Upload and run workflow
pdm run run_setup.py
```

## the general idea

We go from fastq -> ubam -> vcf, but instead using the mouse genome reference files.

## the code

We use a few python scripts in ./scripts to setup initialy things like aws permissions, and eventually develop and bundle the workflows folder. Dedicated instructions will come soon after published work.

## credits
this work is making heavy use of the existing gatk published workflow for fastq conversion into analysis ready bam, and is modified to work for the mouse genome instead of the human genome coding.