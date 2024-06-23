version 1.0

workflow SnpEffAnnotateVCF {
    input {
        String annotated_vcf_path
        String ecr_registry
        String aws_region
    }

    String src_bucket_name = "omics-staging"
    String snpeff_output_path = "s3://" + src_bucket_name + "/snpeff_annotated_vcfs/snpeff_annotated_snps.vcf"

    String snpeff_docker = ecr_registry + "/ecr-public/biocontainers/snpeff:5.0-0"

    call SnpEffAnnotateTask {
        input:
            input_vcf = annotated_vcf_path,
            output_vcf_path = snpeff_output_path,
            docker_image = snpeff_docker,
            genome_version = "GRCm39"
    }

    output {
        File snpeff_annotated_vcf = SnpEffAnnotateTask.output_vcf
    }
}

task SnpEffAnnotateTask {
    input {
        String input_vcf
        String output_vcf_path
        String docker_image
        String genome_version
    }

    command {
        snpEff ann -v ~{genome_version} ~{input_vcf} > ~{output_vcf_path}
    }

    runtime {
        docker: docker_image
        cpu: 2
        memory: "8 GiB"
    }

    output {
        File output_vcf = "~{output_vcf_path}"
    }
}