version 1.0

workflow FilterVCF {
    input {
        String input_vcf_path
        String input_vcf_index_path
        String ecr_registry
        String aws_region
    }

    String src_bucket_name = "omics-staging"
    String filtered_vcf_output_path = "s3://" + src_bucket_name + "/filtered_vcfs/filtered_snps.vcf.gz"
    String filtered_vcf_index_output_path = filtered_vcf_output_path + ".tbi"
    String bcftools_docker = ecr_registry + "/ecr-public/biocontainers/bcftools:1.20--h8b25389_0"

    call FilterVCFTask {
        input:
            input_vcf = input_vcf_path,
            input_vcf_index = input_vcf_index_path,
            output_vcf_path = filtered_vcf_output_path,
            output_vcf_index_path = filtered_vcf_index_output_path,
            docker_image = bcftools_docker
    }

    output {
        File filtered_vcf = FilterVCFTask.output_vcf
        File filtered_vcf_index = FilterVCFTask.output_vcf_index
    }
}

task FilterVCFTask {
    input {
        String input_vcf
        String input_vcf_index
        String output_vcf_path
        String output_vcf_index_path
        String docker_image
    }

    command {
        bcftools filter -e 'FORMAT/AD[1] < 3' ~{input_vcf} -Oz -o ~{output_vcf_path}
        bcftools index ~{output_vcf_path}
    }

    runtime {
        docker: docker_image
        cpu: 2
        memory: "4 GiB"
    }

    output {
        File output_vcf = "~{output_vcf_path}"
        File output_vcf_index = "~{output_vcf_index_path}"
    }
}