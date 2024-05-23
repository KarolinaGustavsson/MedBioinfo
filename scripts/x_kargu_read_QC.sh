#!/bin/bash
echo "start of script"
date

# Directory setup
WORK_DIR="/proj/applied_bioinformatics/users/x_kargu/MedBioinfo"
DATA_DIR="$WORK_DIR/data/sra_fastq"
ANALYSES_DIR="$WORK_DIR/analyses"
RUN_ACCESSIONS_FILE="$ANALYSES_DIR/x_kargu_run_accessions.txt"

mkdir -p $DATA_DIR
mkdir -p $ANALYSES_DIR

# Export run accessions
sqlite3 -batch /proj/applied_bioinformatics/common_data/sample_collab.db \
-noheader -csv "select run_accession from sample_annot spl left join sample2bioinformatician s2b using(patient_code) where username='x_kargu';" > $RUN_ACCESSIONS_FILE

# Test download with the first accession
FIRST_RUN=$(head -n 1 $RUN_ACCESSIONS_FILE)
apptainer exec /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif fastq-dump --split-files --gzip --defline-seq '@$ac.$si.$ri' -O $DATA_DIR -X 10 $FIRST_RUN

# Download all FASTQ files
cat $RUN_ACCESSIONS_FILE | srun --cpus-per-task=1 --time=00:30:00 apptainer exec /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif xargs -I {} fastq-dump --split-files --gzip --defline-seq '@$ac.$si.$ri' -O $DATA_DIR {}

# Verify FASTQ files
echo "Verifying FASTQ files..."
for file in $DATA_DIR/*.fastq.gz; do
  echo "File: $file"
  zcat $file | grep "^+$" | wc -l
done

# Base call quality scores encoding
echo "Checking base call quality scores..."
for file in $DATA_DIR/*.fastq.gz; do
  echo "File: $file"
  zcat $file | head -n 40 | tail -n 4
done

date
echo "end of script"

