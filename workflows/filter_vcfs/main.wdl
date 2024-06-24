version 1.0

workflow FilterVCF {
    input {
        File input_vcf_path
        String ecr_registry
        String aws_region
    }

    String bcftools_docker = ecr_registry + "/ecr-public/biocontainers/bcftools:1.20--h8b25389_0"

    # Get the base name of the input VCF file
    String input_vcf_basename = basename(input_vcf_path, ".vcf.gz")

    call FilterVCFTask {
        input:
            input_vcf = input_vcf_path,
            output_vcf_basename = input_vcf_basename,
            docker_image = bcftools_docker
    }

    output {
        File filtered_vcf = FilterVCFTask.output_vcf
        File filtered_vcf_index = FilterVCFTask.output_vcf_index
    }
}

task FilterVCFTask {
    input {
        File input_vcf
        String output_vcf_basename
        String docker_image
    }

    command {
        set -euo pipefail
        echo "Filtering VCF file using bcftools..." >&2
        bcftools filter -e 'FORMAT/AD[0:1] < 3' ~{input_vcf} -Oz -o ~{output_vcf_basename}.filtered.vcf.gz
        echo "Indexing filtered VCF file..." >&2
        bcftools index ~{output_vcf_basename}.filtered.vcf.gz
    }

    runtime {
        docker: docker_image
        cpu: 2
        memory: "4 GiB"
    }

    output {
        File output_vcf = "~{output_vcf_basename}.filtered.vcf.gz"
        File output_vcf_index = "~{output_vcf_basename}.filtered.vcf.gz.csi"
    }
}