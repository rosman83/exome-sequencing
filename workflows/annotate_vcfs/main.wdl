version 1.0

workflow AnnotateVCF {
    input {
        String filtered_vcf_path
        String filtered_vcf_index_path
        String ecr_registry
        String aws_region
    }

    String src_bucket_name = "omics-staging"
    String annotated_vcf_output_path = "s3://" + src_bucket_name + "/annotated_vcfs/annotated_snps.vcf"
    String annotated_vcf_index_output_path = annotated_vcf_output_path + ".tbi"
    String snpeff_output_path = "s3://" + src_bucket_name + "/snpeff_annotated_vcfs/snpeff_annotated_snps.vcf"

    String gatk_docker = ecr_registry + "/aws-genomics/broadinstitute/gatk:4.2.6.1-corretto-11"
    String snpeff_docker = ecr_registry + "/ecr-public/biocontainers/snpeff:5.0-0"

    call AnnotateVCFTask {
        input:
            input_vcf = filtered_vcf_path,
            input_vcf_index = filtered_vcf_index_path,
            output_vcf_path = annotated_vcf_output_path,
            output_vcf_index_path = annotated_vcf_index_output_path,
            docker_image = gatk_docker,
            ref_fasta = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa",
            ref_fasta_index = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa.fai",
            ref_dict = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.dict",
            data_sources_path = "s3://" + src_bucket_name + "/funcotator_dataSources"
    }

    call SnpEffAnnotateTask {
        input:
            input_vcf = AnnotateVCFTask.output_vcf,
            output_vcf_path = snpeff_output_path,
            docker_image = snpeff_docker,
            genome_version = "GRCm39"
    }

    output {
        File annotated_vcf = AnnotateVCFTask.output_vcf
        File annotated_vcf_index = AnnotateVCFTask.output_vcf_index
        File snpeff_annotated_vcf = SnpEffAnnotateTask.output_vcf
    }
}

task AnnotateVCFTask {
    input {
        String input_vcf
        String input_vcf_index
        String output_vcf_path
        String output_vcf_index_path
        String docker_image
        String ref_fasta
        String ref_fasta_index
        String ref_dict
        String data_sources_path
    }

    command {
        gatk Funcotator \
            -R ~{ref_fasta} \
            -V ~{input_vcf} \
            -O ~{output_vcf_path} \
            --output-file-format VCF \
            --data-sources-path ~{data_sources_path} \
            --ref-version GRCm38
        gatk IndexFeatureFile -I ~{output_vcf_path}
    }

    runtime {
        docker: docker_image
        cpu: 4
        memory: "16 GiB"
    }

    output {
        File output_vcf = "~{output_vcf_path}"
        File output_vcf_index = "~{output_vcf_index_path}"
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