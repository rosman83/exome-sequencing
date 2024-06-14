version 1.0

## Copyright Broad Institute, 2019
##
## The haplotypecaller-gvcf-gatk4 workflow runs the HaplotypeCaller tool
## from GATK4 in GVCF mode on a single sample according to GATK Best Practices.
## When executed the workflow scatters the HaplotypeCaller tool over a sample
## using an intervals list file. The output file produced will be a
## single gvcf file.
##
## Requirements/expectations :
## - One analysis-ready BAM file for a single sample (as identified in RG:SM)
## - Set of variant calling intervals lists for the scatter, provided in a file
##
## Outputs :
## - One GVCF file and its index
##
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3) (see LICENSE in
## https://github.com/broadinstitute/wdl). Note however that the programs it calls may
## be subject to different licenses. Users are responsible for checking that they are
## authorized to run all programs before running this script. Please see the dockers
## for detailed licensing information pertaining to the included programs.

# WORKFLOW DEFINITION
workflow HaplotypeCallerGvcf_GATK4 {
    input {
        File input_bam
        File input_bam_index
        String ecr_registry
        String aws_region
    }

    String src_bucket_name = "omics-staging"

    File ref_dict = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.dict"
    File ref_fasta = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa"
    File ref_fasta_index = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa.fai"
    File scattered_calling_intervals_archive= "s3://" + src_bucket_name + "/reference/mm39.interval_list.tar.gz"
    File intervals_list = "s3://" + src_bucket_name + "/reference/mm39.interval_list"

    Boolean make_gvcf = true
    Boolean make_bamout = false

    String gatk_docker = ecr_registry + "/ecr-public/aws-genomics/broadinstitute/gatk:4.2.6.1-corretto-11"
    String utils_docker = ecr_registry + "/ecr-public/ubuntu/ubuntu:20.04"
    String gatk_path = "/gatk/gatk"

    String sample_basename = basename(input_bam, ".bam")
    String vcf_basename = sample_basename
    String output_suffix = if make_gvcf then ".g.vcf.gz" else ".vcf.gz"
    String output_filename = vcf_basename + output_suffix


    # call UnpackIntervals {
    #     input:
    #         archive = scattered_calling_intervals_archive,
    #         docker = utils_docker
    # }

    # # Call an error if there are no intervals
    # call CheckIntervals {
    #     input:
    #         interval_files = UnpackIntervals.interval_files
    # }

    # Call variants in parallel over grouped calling intervals
    # scatter (interval_file in UnpackIntervals.interval_files) {

    #     # Generate GVCF by interval
    #     call HaplotypeCaller {
    #         input:
    #             input_bam = input_bam,
    #             input_bam_index = input_bam_index,
    #             interval_list = interval_file,
    #             output_filename = output_filename,
    #             ref_dict = ref_dict,
    #             ref_fasta = ref_fasta,
    #             ref_fasta_index = ref_fasta_index,
    #             make_gvcf = make_gvcf,
    #             make_bamout = make_bamout,
    #             docker = gatk_docker,
    #             gatk_path = gatk_path
    #     }
    # }

    call HaplotypeCaller {
        input:
            input_bam = input_bam,
            input_bam_index = input_bam_index,
            interval_list = intervals_list,
            output_filename = output_filename,
            ref_dict = ref_dict,
            ref_fasta = ref_fasta,
            ref_fasta_index = ref_fasta_index,
            make_gvcf = make_gvcf,
            make_bamout = make_bamout,
            docker = gatk_docker,
            gatk_path = gatk_path
    }
    
    # Merge per-interval GVCFs
    # call MergeGVCFs {
    #      input:
    #         input_vcfs = HaplotypeCaller.output_vcf,
    #         input_vcfs_indexes = HaplotypeCaller.output_vcf_index,
    #         output_filename = output_filename,
    #         docker = gatk_docker,
    #         gatk_path = gatk_path
    # }

    # Outputs that will be retained when execution is complete
    output {
        # File output_vcf = MergeGVCFs.output_vcf
        # File output_vcf_index = MergeGVCFs.output_vcf_index
        # Retain unpacked intervals for debugging purposes
        # Array[File] unpacked_intervals = UnpackIntervals.interval_files
        # Also retain the GVCFs generated per-interval
        File per_interval_vcfs = HaplotypeCaller.output_vcf
        File per_interval_vcfs_indexes = HaplotypeCaller.output_vcf_index
    }
}

# TASK DEFINITIONS

task UnpackIntervals {
    input {
        File archive
        String docker
    }
    String basestem_input = basename(archive, ".tar.gz")
    command {
        set -e
        echo "Unpack Intervals" >&2
        tar xvfz ~{archive} --directory ./
        echo "Unpacked intervals: $(ls ~{basestem_input})"
    }
    runtime {
        docker: docker
        cpu: 8
        memory: "32 GiB"
    }
    output {
        Array[File] interval_files = glob("${basestem_input}/*")
    }
}

task CheckIntervals {
    input {
        Array[File] interval_files
    }
    command {
        set -e
        echo "Check Intervals" >&2
        if [ ~{length(interval_files)} -eq 0 ]; then
            echo "No intervals found" >&2
            exit 1
        fi
    }
}

# HaplotypeCaller per-sample in GVCF mode
task HaplotypeCaller {
    input {
        # Command parameters
        File input_bam
        File input_bam_index
        File interval_list
        String output_filename
        File ref_dict
        File ref_fasta
        File ref_fasta_index
        Float? contamination
        Boolean make_gvcf
        Boolean make_bamout

        String gatk_path
        String? java_options

        # Runtime parameters
        String docker
        Int? mem_gb
    }

    String java_opt = select_first([java_options, ""])

    Int machine_mem_gb = select_first([mem_gb, 8])
    Int command_mem_gb = machine_mem_gb - 2

    String vcf_basename = if make_gvcf then  basename(output_filename, ".gvcf") else basename(output_filename, ".vcf")
    String bamout_arg = if make_bamout then "-bamout ~{vcf_basename}.bamout.bam" else ""

    parameter_meta {
        input_bam: {
                       description: "a bam file"
                   }
        input_bam_index: {
                             description: "an index file for the bam input"
                         }
    }
    command {
    set -e
    
    ~{gatk_path} --java-options "-Xmx~{command_mem_gb}G ~{java_opt}" \
      HaplotypeCaller \
      -R ~{ref_fasta} \
      -I ~{input_bam} \
      -L ~{interval_list} \
      -O ~{output_filename} \
      -contamination ~{default="0" contamination} \
      -G StandardAnnotation -G StandardHCAnnotation ~{true="-G AS_StandardAnnotation" false="" make_gvcf} \
      -GQB 10 -GQB 20 -GQB 30 -GQB 40 -GQB 50 -GQB 60 -GQB 70 -GQB 80 -GQB 90 \
      ~{true="-ERC GVCF" false="" make_gvcf} \
      ~{bamout_arg}

    # Cromwell doesn't like optional task outputs, so we have to touch this file.
    touch ~{vcf_basename}.bamout.bam 

    }
    runtime {
        docker: docker
        memory: machine_mem_gb + " GiB"
        cpu: 2
    }
    output {
        File output_vcf = "~{output_filename}"
        File output_vcf_index = "~{output_filename}.tbi"
        File bamout = "~{vcf_basename}.bamout.bam"
    }
}
# Merge GVCFs generated per-interval for the same sample
task MergeGVCFs {
    input {
        # Command parameters
        File input_vcfs
        File input_vcfs_indexes
        String output_filename

        String gatk_path

        # Runtime parameters
        String docker
        Int? mem_gb
    }
    Int machine_mem_gb = select_first([mem_gb, 8])
    Int command_mem_gb = machine_mem_gb - 2
    String disk_usage_cmd = "echo storage remaining: $(df -Ph . | awk 'NR==2 {print $4}')"

    command {
        echo MergeGVCFs
        echo "input_vcfs: ~{input_vcfs}"
        set -euxo pipefail

        ~{gatk_path} --java-options "-Xmx~{command_mem_gb}G" \
        MergeVcfs \
        --INPUT ~{input_vcfs} \
        --OUTPUT ~{output_filename}

        # determine final scratch size used
        ~{disk_usage_cmd}
    }
    runtime {
        docker: docker
        memory: machine_mem_gb + " GB"
        cpu: 2
    }
    output {
        File output_vcf = "~{output_filename}"
        File output_vcf_index = "~{output_filename}.tbi"
    }
}