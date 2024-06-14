version 1.0

import "./processing-for-variant-discovery-gatk4.wdl" as preprocess
import "./ubam-to-vcf.wdl" as ubam_to_vcf
workflow FastqsToAnalysisReadyBam {
  # Initial Parameters for Task Run
    input {
      String sample_name
      Array[FastqPair] fastq_pairs
      String ecr_registry
      String aws_region
    }
  # Setting Default Parameters
    call preprocess.PreProcessingForVariantDiscovery_GATK4 {
        input:
          sample_name = sample_name,
          fastq_pairs = fastq_pairs,
          unmapped_bam_suffix = ".bam",
          ecr_registry = ecr_registry,
          aws_region = aws_region
    }

    call ubam_to_vcf.HaplotypeCallerGvcf_GATK4 {
        input:
          input_bam = preprocess.PreProcessingForVariantDiscovery_GATK4.analysis_ready_bam,
          input_bam_index = preprocess.PreProcessingForVariantDiscovery_GATK4.analysis_ready_bam_index,
          ecr_registry = ecr_registry,  
          aws_region = aws_region
    }


  # Output to Bam
    output {
        File duplication_metrics = PreProcessingForVariantDiscovery_GATK4.duplication_metrics
        File bqsr_report = PreProcessingForVariantDiscovery_GATK4.bqsr_report
        File analysis_ready_bam = PreProcessingForVariantDiscovery_GATK4.analysis_ready_bam
        File analysis_ready_bam_index = PreProcessingForVariantDiscovery_GATK4.analysis_ready_bam_index
        File analysis_ready_bam_md5 = PreProcessingForVariantDiscovery_GATK4.analysis_ready_bam_md5
        # Output to VCF
        File output_vcf = HaplotypeCallerGvcf_GATK4.output_vcf
        File output_vcf_index = HaplotypeCallerGvcf_GATK4.output_vcf_index
    }
}