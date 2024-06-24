version 1.0

workflow DemoWorkflow {
    input {
        String input_text_path
        String ecr_registry
        String aws_region
    }

    String src_bucket_name = "omics-staging"
    String demo_output_path = "s3://" + src_bucket_name + "/demo_output/demo_result.txt"

    String ubuntu_docker = ecr_registry + "/ecr-public/ubuntu/ubuntu:20.04"

    call PrintTextTask {
        input:
            input_text_path = input_text_path,
            docker_image = ubuntu_docker
    }

    output {
        File printed_text = PrintTextTask.output_text
    }
}

task PrintTextTask {
    input {
        String input_text_path
        String docker_image
    }

    command {
        aws s3 cp ~{input_text_path} input.txt
        cat input.txt
        echo "Demo complete" > result.txt
    }

    runtime {
        docker: docker_image
        cpu: 1
        memory: "1 GiB"
    }

    output {
        File output_text = "result.txt"
    }
}