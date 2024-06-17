version 1.0
import "./structs.wdl" as structs

workflow FQtoVCF {
  # INPUTS --------------------------------------------------
  input {
    String sample_name
    Array[FastqPair] fastq_pairs
    String ecr_registry
    String aws_region
  }

  # TO BAM --------------------------------------------------
  String unmapped_bam_suffix = ".bam"
  Int compression_level = 2
  String gatk_path = "/gatk/gatk"
  String gotc_path = "/usr/gitc/"
  String src_bucket_name = "omics-staging"
  String ref_name = "mm39"
  File ref_fasta = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa"
  File ref_fasta_index = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa.fai"
  File ref_dict = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.dict"
  File ref_sa = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa.sa"
  File ref_ann = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa.ann"
  File ref_bwt = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa.bwt"
  File ref_pac = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa.pac"
  File ref_amb = "s3://" + src_bucket_name + "/reference/Mus_musculus.GRCm39.dna.toplevel.fa.amb"
  File dbSNP_vcf = "s3://" + src_bucket_name + "/reference/mgp_REL2021_snps.rsID.vcf.gz"
  File dbSNP_vcf_index = "s3://" + src_bucket_name + "/reference/mgp_REL2021_snps.rsID.vcf.gz.tbi" 
  Array[File] known_indels_sites_VCFs = [ "s3://" + src_bucket_name + "/reference/mgp_REL2021_indels.vcf.gz", ]
  Array[File] known_indels_sites_indices = ["s3://" + src_bucket_name + "/reference/mgp_REL2021_indels.vcf.gz.tbi",]
  String gatk_docker = ecr_registry + "/ecr-public/aws-genomics/broadinstitute/gatk:4.2.6.1-corretto-11"
  String gotc_docker = ecr_registry + "/ecr-public/aws-genomics/broadinstitute/genomes-in-the-cloud:2.5.7-2021-06-09_16-47-48Z-corretto-11"
  String python_docker = ecr_registry + "/ecr-public/docker/library/python:3.9"
  String base_file_name = sample_name + "." + ref_name
  String bwa_commandline = "bwa mem -K 100000000 -v 3 -t 14 -Y $bash_ref_fasta"

  call GetBwaVersion {
    input:
      docker_image = gotc_docker,
      bwa_path = gotc_path,
  }

  scatter (fastq_pair in fastq_pairs) {
    call PairedFastQsToUnmappedBAM {
      input:
        sample_name = sample_name,
        platform = fastq_pair.platform,
        fastq_1 = fastq_pair.fastq_1,
        fastq_2 = fastq_pair.fastq_2,
        readgroup_name = fastq_pair.read_group,
        gatk_path = gatk_path,
        docker = gatk_docker
    }

    String bam_basename = basename(fastq_pair.read_group, unmapped_bam_suffix)

    call BwaMemAlign {
      input:
        input_fastq_pair = fastq_pair,
        bwa_commandline = bwa_commandline,
        output_bam_basename = bam_basename + ".unmerged",
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        # ref_alt = ref_alt,
        ref_sa = ref_sa,
        ref_ann = ref_ann,
        ref_bwt = ref_bwt,
        ref_pac = ref_pac,
        ref_amb = ref_amb,
        docker_image = gotc_docker,
        bwa_path = gotc_path,
        gotc_path = gotc_path,
    }

    call MergeBamAlignment {
      input:
        unmapped_bam = PairedFastQsToUnmappedBAM.output_unmapped_bam,
        bwa_commandline = bwa_commandline,
        bwa_version = GetBwaVersion.version,
        aligned_bam = BwaMemAlign.output_bam,
        output_bam_basename = bam_basename + ".aligned.unsorted",
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        docker_image = gatk_docker,
        gatk_path = gatk_path,
        compression_level = compression_level
    }
  }

  call MarkDuplicates {
    input:
      input_bams = MergeBamAlignment.output_bam,
      output_bam_basename = base_file_name + ".aligned.unsorted.duplicates_marked",
      metrics_filename = base_file_name + ".duplicate_metrics",
      docker_image = gatk_docker,
      gatk_path = gatk_path,
      compression_level = compression_level,
  }

  call SortAndFixTags {
    input:
      input_bam = MarkDuplicates.output_bam,
      output_bam_basename = base_file_name + ".aligned.duplicate_marked.sorted",
      ref_dict = ref_dict,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      docker_image = gatk_docker,
      gatk_path = gatk_path,
      compression_level = compression_level
  }

  call CreateSequenceGroupingTSV {
    input:
      ref_dict = ref_dict,
      docker_image = python_docker,
  }

  scatter (subgroup in CreateSequenceGroupingTSV.sequence_grouping) {
    # Generate the recalibration model by interval
    call BaseRecalibrator {
      input:
        input_bam = SortAndFixTags.output_bam,
        input_bam_index = SortAndFixTags.output_bam_index,
        recalibration_report_filename = base_file_name + ".recal_data.csv",
        sequence_group_interval = subgroup,
        dbSNP_vcf = dbSNP_vcf,
        dbSNP_vcf_index = dbSNP_vcf_index,
        known_indels_sites_VCFs = known_indels_sites_VCFs,
        known_indels_sites_indices = known_indels_sites_indices,
        ref_dict = ref_dict,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        docker_image = gatk_docker,
        gatk_path = gatk_path,
    }
  }

  call GatherBqsrReports {
    input:
      input_bqsr_reports = BaseRecalibrator.recalibration_report,
      output_report_filename = base_file_name + ".recal_data.csv",
      docker_image = gatk_docker,
      gatk_path = gatk_path,
  }

  scatter (subgroup in CreateSequenceGroupingTSV.sequence_grouping_with_unmapped) {
    call ApplyBQSR {
      input:
        input_bam = SortAndFixTags.output_bam,
        input_bam_index = SortAndFixTags.output_bam_index,
        output_bam_basename = base_file_name + ".aligned.duplicates_marked.recalibrated",
        recalibration_report = GatherBqsrReports.output_bqsr_report,
        sequence_group_interval = subgroup,
        ref_dict = ref_dict,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        docker_image = gatk_docker,
        gatk_path = gatk_path,
    }
  }

  call GatherBamFiles {
    input:
      input_bams = ApplyBQSR.recalibrated_bam,
      output_bam_basename = base_file_name,
      docker_image = gatk_docker,
      gatk_path = gatk_path,
      compression_level = 5
  }

  # To VCF ---------------------------------------------------
  File scattered_calling_intervals_archive= "s3://" + src_bucket_name + "/reference/mm39.interval_list.tar.gz"
  File intervals_list = "s3://" + src_bucket_name + "/reference/mm39.interval_list"
  Boolean make_gvcf = true
  Boolean make_bamout = false
  String utils_docker = ecr_registry + "/ecr-public/ubuntu/ubuntu:20.04"
  String sample_basename = basename(GatherBamFiles.output_bam, ".bam")
  String vcf_basename = sample_basename
  String output_suffix = if make_gvcf then ".g.vcf.gz" else ".vcf.gz"
  String output_filename = vcf_basename + output_suffix
  
  call HaplotypeCaller {
    input:
      input_bam = GatherBamFiles.output_bam,
      input_bam_index = GatherBamFiles.output_bam_index,
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

  # Outputs --------------------------------------------------
  output {
    File per_interval_vcfs = HaplotypeCaller.output_vcf
    File per_interval_vcfs_indexes = HaplotypeCaller.output_vcf_index

  }
}

# TASK DEFINITIONS for FASTQ TO BAM --------------------------------------------------

task GetBwaVersion {
  input {
    Float mem_size_gb = 2
    String docker_image
    String bwa_path
  }

  command {
    echo GetBwaVersion >&2

    # Not setting "set -o pipefail" here because /bwa has a rc=1 and we don't want to allow rc=1 to succeed
    # because the sed may also fail with that error and that is something we actually want to fail on.

    set -ux

    ~{bwa_path}bwa 2>&1 | \
    grep -e '^Version' | \
    sed 's/Version: //'
  }
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb} GiB"
    cpu: 2
  }
  output {
    String version = read_string(stdout())
  }
}

task BwaMemAlign {
  # TODO: ENSURE ALT FILE IS OPTIONAL HERE
  # This is the .alt file from bwa-kit (https://github.com/lh3/bwa/tree/master/bwakit),
  # listing the reference contigs that are "alternative". Leave blank in JSON for legacy
  # references such as b37 and hg19.
  input {
    FastqPair input_fastq_pair
    String bwa_commandline
    String output_bam_basename
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    # File? ref_alt
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa

    Float mem_size_gb = 32
    Int num_cpu = 16

    String docker_image
    String bwa_path
    String gotc_path
  }

  command {
    echo ref_fasta = ~{ref_fasta}
    echo fastq_1 = ~{input_fastq_pair.fastq_1}
    echo fastq_2 = ~{input_fastq_pair.fastq_2}
    set -euo pipefail

    # set the bash variable needed for the command-line
    bash_ref_fasta=~{ref_fasta}

    set -x
    ~{bwa_path}~{bwa_commandline} ~{input_fastq_pair.fastq_1} ~{input_fastq_pair.fastq_2} \
    | \
    samtools view -b -F 4 -@ 4 -1 - > ~{output_bam_basename}.bam
  }
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb} GiB"
    cpu: num_cpu
  }
  output {
    File output_bam = "~{output_bam_basename}.bam"
  }
}

task MergeBamAlignment {
  input {
    File unmapped_bam
    String bwa_commandline
    String bwa_version
    File aligned_bam
    String output_bam_basename
    File ref_fasta
    File ref_fasta_index
    File ref_dict

    Int compression_level
    Int mem_size_gb = 8

    String docker_image
    String gatk_path
  }

  Int command_mem_gb = ceil(mem_size_gb) - 1

  command {



    echo MergeBamAlignment >&2

    set -euxo pipefail

    # set the bash variable needed for the bwa_commandline arg to --PROGRAM_GROUP_COMMAND_LINE
    bash_ref_fasta=~{ref_fasta}

    ~{gatk_path} --java-options "-Dsamjdk.compression_level=~{compression_level} -Xmx~{command_mem_gb}G -XX:+UseShenandoahGC" \
    MergeBamAlignment \
    --VALIDATION_STRINGENCY SILENT \
    --EXPECTED_ORIENTATIONS FR \
    --ATTRIBUTES_TO_RETAIN X0 \
    --ALIGNED_BAM ~{aligned_bam} \
    --UNMAPPED_BAM ~{unmapped_bam} \
    --OUTPUT ~{output_bam_basename}.bam \
    --REFERENCE_SEQUENCE ~{ref_fasta} \
    --PAIRED_RUN true \
    --SORT_ORDER "unsorted" \
    --IS_BISULFITE_SEQUENCE false \
    --ALIGNED_READS_ONLY false \
    --CLIP_ADAPTERS false \
    --ADD_MATE_CIGAR true \
    --MAX_INSERTIONS_OR_DELETIONS -1 \
    --PRIMARY_ALIGNMENT_STRATEGY MostDistant \
    --PROGRAM_RECORD_ID "bwamem" \
    --PROGRAM_GROUP_VERSION "~{bwa_version}" \
    --PROGRAM_GROUP_COMMAND_LINE "~{bwa_commandline}" \
    --PROGRAM_GROUP_NAME "bwamem" \
    --UNMAPPED_READ_STRATEGY COPY_TO_TAG \
    --ALIGNER_PROPER_PAIR_FLAGS true \
    --UNMAP_CONTAMINANT_READS true
  }
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb} GiB"
    cpu: 2
  }
  output {
    File output_bam = "~{output_bam_basename}.bam"
  }
}

task SortAndFixTags {
  input {
    File input_bam
    String output_bam_basename
    File ref_dict
    File ref_fasta
    File ref_fasta_index

    Int compression_level
    Float mem_size_gb = 64

    String docker_image
    String gatk_path
  }

  command {

    echo SortAndFixTags >&2

    set -euxo pipefail

    ~{gatk_path} --java-options "-Dsamjdk.compression_level=2 -Xmx50G" \
    SortSam \
    --INPUT ~{input_bam} \
    --OUTPUT /dev/stdout \
    --SORT_ORDER "coordinate" \
    --CREATE_INDEX false \
    --CREATE_MD5_FILE false \
    | \
    ~{gatk_path} --java-options "-Dsamjdk.compression_level=~{compression_level} -Xmx8G " \
    SetNmMdAndUqTags \
    --INPUT /dev/stdin \
    --OUTPUT ~{output_bam_basename}.bam \
    --CREATE_INDEX true \
    --CREATE_MD5_FILE false \
    --REFERENCE_SEQUENCE ~{ref_fasta}

  }
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb} GiB"
    cpu: 4
  }
  output {
    File output_bam = "~{output_bam_basename}.bam"
    File output_bam_index = "~{output_bam_basename}.bai"
  }
}

task MarkDuplicates {
  input {
    Array[File] input_bams
    String output_bam_basename
    String metrics_filename

    Int compression_level
    Int mem_size_gb = 64

    String docker_image
    String gatk_path
  }

  Int xmx_size= mem_size_gb - 4

  # Task is assuming query-sorted input so that the Secondary and Supplementary reads get marked correctly.
  # This works because the output of BWA is query-grouped and therefore, so is the output of MergeBamAlignment.
  # While query-grouped isn't actually query-sorted, it's good enough for MarkDuplicates with ASSUME_SORT_ORDER="queryname"
  command {

    echo MarkDuplicates >&2

    set -euxo pipefail

    ~{gatk_path} --java-options "-Dsamjdk.compression_level=~{compression_level} -Xmx~{xmx_size}G" \
    MarkDuplicates \
    --INPUT ~{sep=' --INPUT ' input_bams} \
    --OUTPUT ~{output_bam_basename}.bam \
    --METRICS_FILE ~{metrics_filename} \
    --VALIDATION_STRINGENCY SILENT \
    --OPTICAL_DUPLICATE_PIXEL_DISTANCE 2500 \
    --ASSUME_SORT_ORDER "queryname" \
    --CREATE_MD5_FILE false

  }
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb}  GiB"
    cpu: 4
  }
  output {
    File output_bam = "~{output_bam_basename}.bam"
    File duplicate_metrics = "~{metrics_filename}"
  }
}

task CreateSequenceGroupingTSV {
  input {
    File ref_dict
    Float mem_size_gb = 2

    String docker_image
  }
  # Use python to create the Sequencing Groupings used for BQSR and PrintReads Scatter.
  # It outputs to stdout where it is parsed into a wdl Array[Array[String]]
  # e.g. [["1"], ["2"], ["3", "4"], ["5"], ["6", "7", "8"]]
  command <<<
    set -e
    echo CreateSequenceGroupingTSV >&2

    python <<CODE
    with open("~{ref_dict}", "r") as ref_dict_file:
        sequence_tuple_list = []
        longest_sequence = 0
        for line in ref_dict_file:
            if line.startswith("@SQ"):
                line_split = line.split("\t")
                # (Sequence_Name, Sequence_Length)
                sequence_tuple_list.append((line_split[1].split("SN:")[1], int(line_split[2].split("LN:")[1])))
        longest_sequence = sorted(sequence_tuple_list, key=lambda x: x[1], reverse=True)[0][1]
    # We are adding this to the intervals because hg38 has contigs named with embedded colons (:) and a bug in
    # some versions of GATK strips off the last element after a colon, so we add this as a sacrificial element.
    hg38_protection_tag = ":1+"
    # initialize the tsv string with the first sequence
    tsv_string = sequence_tuple_list[0][0] + hg38_protection_tag
    temp_size = sequence_tuple_list[0][1]
    for sequence_tuple in sequence_tuple_list[1:]:
        if temp_size + sequence_tuple[1] <= longest_sequence:
            temp_size += sequence_tuple[1]
            tsv_string += "\t" + sequence_tuple[0] + hg38_protection_tag
        else:
            tsv_string += "\n" + sequence_tuple[0] + hg38_protection_tag
            temp_size = sequence_tuple[1]
    # add the unmapped sequences as a separate line to ensure that they are recalibrated as well
    with open("sequence_grouping.txt","w") as tsv_file:
      tsv_file.write(tsv_string)
      tsv_file.close()

    tsv_string += '\n' + "unmapped"

    with open("sequence_grouping_with_unmapped.txt","w") as tsv_file_with_unmapped:
      tsv_file_with_unmapped.write(tsv_string)
      tsv_file_with_unmapped.close()
    CODE

    cat sequence_grouping_with_unmapped.txt
  >>>
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb} GiB"
    cpu: 2
  }
  output {
    Array[Array[String]] sequence_grouping = read_tsv("sequence_grouping.txt")
    Array[Array[String]] sequence_grouping_with_unmapped = read_tsv("sequence_grouping_with_unmapped.txt")
  }
}

task BaseRecalibrator {
  input {
    File input_bam
    File input_bam_index
    String recalibration_report_filename
    Array[String] sequence_group_interval
    File dbSNP_vcf
    File dbSNP_vcf_index
    Array[File] known_indels_sites_VCFs
    Array[File] known_indels_sites_indices
    File ref_dict
    File ref_fasta
    File ref_fasta_index

    Float mem_size_gb = 16

    String docker_image
    String gatk_path
  }

  Int xmx = ceil(mem_size_gb) - 4
  String sequence_group_interval_str = sep(",", sequence_group_interval)
  String known_indels_sites_VCFs_str = sep(",", known_indels_sites_VCFs)
  String known_indels_sites_indices_str = sep(",",known_indels_sites_indices)
  command {

    echo BaseRecalibrator >&2
    echo input_bam: ~{input_bam}
    echo input_bam_index: ~{input_bam_index}
    echo recalibration_report_filename: ~{recalibration_report_filename}
    echo sequence_group_interval: ~{sequence_group_interval_str}
    echo dbSNP_vcf: ~{dbSNP_vcf}
    echo dbSNP_vcf_index: ~{dbSNP_vcf_index}
    echo known_indels_sites_VCFs: ~{known_indels_sites_VCFs_str}
    echo known_indels_sites_indices: ~{known_indels_sites_indices_str}
    echo ref_dict: ~{ref_dict}
    echo ref_fasta: ~{ref_fasta}
    echo mem_size_gb: ~{mem_size_gb}
    echo docker_image: ~{docker_image}
    echo gatk_path: ~{gatk_path}

    set -eux

    ~{gatk_path} --java-options "-Xmx~{xmx}G" \
    BaseRecalibrator \
    -R ~{ref_fasta} \
    -I ~{input_bam} \
    --use-original-qualities \
    -O ~{recalibration_report_filename} \
    --known-sites ~{dbSNP_vcf} \
    --known-sites ~{sep=" --known-sites " known_indels_sites_VCFs} \
    -L ~{sep=" -L " sequence_group_interval}

  }
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb} GiB"
    cpu: 2
  }
  output {
    File recalibration_report = "~{recalibration_report_filename}"
  }
}

task GatherBqsrReports {
  input {
    Array[File] input_bqsr_reports
    String output_report_filename

    Float mem_size_gb = 8

    String docker_image
    String gatk_path
  }

  Int xmx = ceil(mem_size_gb) - 2

  command {

    echo GatherBqsrReports
    set -euxo pipefail

    ~{gatk_path} --java-options "-Xmx~{xmx}G -XX:+UseShenandoahGC" \
    GatherBQSRReports \
    -I ~{sep=' -I ' input_bqsr_reports} \
    -O ~{output_report_filename}

  }
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb} GiB"
    cpu: 2
  }
  output {
    File output_bqsr_report = "~{output_report_filename}"
  }
}

task ApplyBQSR {
  input {
    File input_bam
    File input_bam_index
    String output_bam_basename
    File recalibration_report
    Array[String] sequence_group_interval
    File ref_dict
    File ref_fasta
    File ref_fasta_index

    Float mem_size_gb = 8

    String docker_image
    String gatk_path
  }

  Int xmx = ceil(mem_size_gb) - 2
  command {

    echo ApplyBQSR
    set -euxo pipefail

    ~{gatk_path} --java-options "-Dsamjdk.compression_level=2 -Xmx~{xmx}G -XX:+UseShenandoahGC" \
    ApplyBQSR \
    -R ~{ref_fasta} \
    -I ~{input_bam} \
    -O ~{output_bam_basename}.bam \
    -L ~{sep=" -L " sequence_group_interval} \
    -bqsr ~{recalibration_report} \
    --static-quantized-quals 10 --static-quantized-quals 20 --static-quantized-quals 30 \
    --add-output-sam-program-record \
    --create-output-bam-md5 \
    --use-original-qualities

  }
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb} GiB"
    cpu: 2
  }
  output {
    File recalibrated_bam = "~{output_bam_basename}.bam"
  }
}

task GatherBamFiles {
  input {
    Array[File] input_bams
    String output_bam_basename

    Int compression_level = 6
    Float mem_size_gb = 8

    String docker_image
    String gatk_path
  }

  Int xmx = ceil(mem_size_gb) - 2
  String disk_usage_cmd = "echo storage remaining: $(df -Ph . | awk 'NR==2 {print $4}')"

  command {

    echo GatherBamFiles
    set -euxo pipefail

    ~{gatk_path} --java-options "-Dsamjdk.compression_level=~{compression_level} -Xmx~{xmx}G -XX:+UseShenandoahGC" \
    GatherBamFiles \
    --INPUT ~{sep=' --INPUT ' input_bams} \
    --OUTPUT ~{output_bam_basename}.bam \
    --CREATE_INDEX true \
    --CREATE_MD5_FILE true

    ~{disk_usage_cmd}
  }
  runtime {
    docker: docker_image
    memory: "~{mem_size_gb} GiB"
    cpu: 4
  }
  output {
    File output_bam = "~{output_bam_basename}.bam"
    File output_bam_index = "~{output_bam_basename}.bai"
    File output_bam_md5 = "~{output_bam_basename}.bam.md5"
  }
}

task PairedFastQsToUnmappedBAM {
    input {
        # Command parameters
        String sample_name
        File fastq_1
        File fastq_2
        String readgroup_name
        # The platform type (e.g. illumina, solid)
        String platform
        String gatk_path

        # Runtime parameters
        Int machine_mem_gb = 8
        String docker
    }
    Int command_mem_gb = machine_mem_gb - 1
    String disk_usage_cmd = "echo storage remaining: $(df -Ph . | awk 'NR==2 {print $4}')"

    command {
        set -e
        # determine scratch size used
        ~{disk_usage_cmd}

        echo "FASTQ to uBAM" >&2
        echo "fastq_1 ~{fastq_1}" >&2
        echo "fastq_2 ~{fastq_2}" >&2
        echo "sample_name ~{sample_name}" >&2
        echo "readgroup_name ~{readgroup_name}" >&2
        echo "platform ~{readgroup_name}" >&2

        ~{gatk_path} --java-options "-Dsamjdk.compression_level=2 -Xmx~{command_mem_gb}g" \
        FastqToSam \
        --FASTQ ~{fastq_1} \
        --FASTQ2 ~{fastq_2} \
        --OUTPUT ~{readgroup_name}.unmapped.bam \
        --READ_GROUP_NAME ~{readgroup_name} \
        --PLATFORM ~{platform} \
        --SAMPLE_NAME ~{sample_name}

        # determine final scratch size used
        ~{disk_usage_cmd}
    }
    runtime {
        docker: docker
        memory: machine_mem_gb + " GiB"
        cpu: 2
    }
    output {
        File output_unmapped_bam = "~{readgroup_name}.unmapped.bam"
    }
}

# TASK DEFINITIONS for BAM to VCF --------------------------------------------------

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