# exome-sequencing

Workflow to carry out exome sequencing through AWS HealthOmics - specifically for the mouse genome.

## the general idea

We go from fastq -> ubam -> vcf, but instead using the mouse genome reference files.

## the code

We use a few python scripts in ./scripts to setup initialy things like aws permissions, and eventually develop and bundle the workflows folder. Dedicated instructions will come soon after published work.

## credits
this work is making heavy use of the existing gatk published workflow for fastq conversion into analysis ready bam, and is modified to work for the mouse genome instead of the human genome coding.