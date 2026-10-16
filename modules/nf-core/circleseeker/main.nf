process CIRCLESEEKER {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
?         'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/a3/a30b0118879aeb2a81314bfd1983f0e3027f5ad578fff6e9d91e1f10b0391e4c/data'
:         'community.wave.seqera.io/library/circleseeker:1.6.1--30c163cc47db14e8' }"

    input:
    tuple val(meta), path(reads)
    tuple val(meta2), path(fasta)

    output:
    tuple val(meta), path("${prefix}_eccDNA_summary.csv"), emit: summary
    tuple val(meta), path("${prefix}_summary.txt"),        emit: summary_txt
    tuple val(meta), path("${prefix}_report.html"),        emit: report
    tuple val("${task.process}"), val('circleseeker'), eval("circleseeker --version 2>&1 | sed 's/CircleSeeker //'"), topic: versions, emit: versions_circleseeker

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    # CircleSeeker requires FASTA input (pysam.FastaFile) and detects format
    # by file extension, so decompress gz and convert FASTQ to FASTA first.
    if [[ "${reads}" == *.gz ]]; then
        zcat "${reads}" > reads_input.fastq
        READS_IN="reads_input.fastq"
    else
        READS_IN="${reads}"
    fi
    if [[ "\${READS_IN}" == *.fastq || "\${READS_IN}" == *.fq ]]; then
        awk 'NR%4==1 {print ">" substr(\$0,2)} NR%4==2 {print}' "\${READS_IN}" > reads_input.fasta
        READS_IN="reads_input.fasta"
    fi

    # Reference genome: decompress if gz (CircleSeeker auto-creates .mmi/.fai
    # indexes next to the file, so run it in the writable workdir).
    if [[ "${fasta}" == *.gz ]]; then
        zcat "${fasta}" > reference.fa
        FASTAIN="reference.fa"
    else
        FASTAIN="${fasta}"
    fi

    circleseeker \\
        -i \${READS_IN} \\
        -r \${FASTAIN} \\
        -o . \\
        -p ${prefix} \\
        -t ${task.cpus} \\
        $args

    # CircleSeeker may omit summary/report files when no candidates are found.
    if [ ! -f ${prefix}_eccDNA_summary.csv ]; then
        echo "eccDNA_id,type,state,chr,start,end,strand,length" > ${prefix}_eccDNA_summary.csv
    fi
    touch ${prefix}_summary.txt
    touch ${prefix}_report.html

    # External aligners spawned by CircleSeeker can outlive the main process
    # and keep the container PID namespace alive; wait for any remaining children.
    wait || true
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "eccDNA_id,type,state,chr,start,end,strand,length" > ${prefix}_eccDNA_summary.csv
    touch ${prefix}_summary.txt
    touch ${prefix}_report.html
    """
}
