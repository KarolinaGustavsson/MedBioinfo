#!/bin/bash
#SBATCH --job-name=read_QC
#SBATCH --output=/proj/applied_bioinformatics/users/x_kargu/MedBioinfo/logs/read_QC_%j.log
#SBATCH --error=/proj/applied_bioinformatics/users/x_kargu/MedBioinfo/logs/read_QC_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=01:00:00
#SBATCH --partition=tetralith  # Correct partition specification

echo "start of script"
date

# Directory setup
WORK_DIR="/proj/applied_bioinformatics/users/x_kargu/MedBioinfo"
DATA_DIR="$WORK_DIR/data/sra_fastq"
ANALYSES_DIR="$WORK_DIR/analyses"
LOGS_DIR="$WORK_DIR/logs"
RUN_ACCESSIONS_FILE="$ANALYSES_DIR/x_kargu_run_accessions.txt"

mkdir -p $DATA_DIR
mkdir -p $ANALYSES_DIR
mkdir -p $LOGS_DIR

# Export run accessions if not already done
if [ ! -f $RUN_ACCESSIONS_FILE ]; then
  echo "Exporting run accessions..."
  sqlite3 -batch /proj/applied_bioinformatics/common_data/sample_collab.db \
  -noheader -csv "select run_accession from sample_annot spl left join sample2bioinformatician s2b using(patient_code) where username='x_kargu';" > $RUN_ACCESSIONS_FILE
fi

# Verify the run accessions file creation
if [ ! -f $RUN_ACCESSIONS_FILE ]; then
  echo "Run accessions file creation failed. Exiting script."
  exit 1
fi

# Test download with the first accession
FIRST_RUN=$(head -n 1 $RUN_ACCESSIONS_FILE)
if [ ! -f $DATA_DIR/${FIRST_RUN}_1.fastq.gz ]; then
  echo "Downloading test reads for first run accession $FIRST_RUN..."
  apptainer exec /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif fastq-dump --split-files --gzip --defline-seq '@$ac.$si.$ri' -O $DATA_DIR -X 10 $FIRST_RUN
fi

# Check if test download was successful
if [ ! -f $DATA_DIR/${FIRST_RUN}_1.fastq.gz ]; then
  echo "Test download failed. Exiting script."
  exit 1
fi

# Download all FASTQ files
echo "Downloading all FASTQ files..."
cat $RUN_ACCESSIONS_FILE | while read -r ACCESSION; do
  if [ ! -f $DATA_DIR/${ACCESSION}_1.fastq.gz ]; then
    srun --cpus-per-task=1 --time=00:30:00 apptainer exec /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif fastq-dump --split-files --gzip --defline-seq '@$ac.$si.$ri' -O $DATA_DIR $ACCESSION
  fi
done

# Verify FASTQ files
if [ ! -f $ANALYSES_DIR/fastq_verification.txt ]; then
  echo "Verifying FASTQ files..." > $ANALYSES_DIR/fastq_verification.txt
  for file in $DATA_DIR/*.fastq.gz; do
    echo "File: $file" >> $ANALYSES_DIR/fastq_verification.txt
    zcat $file | grep "^+$" | wc -l >> $ANALYSES_DIR/fastq_verification.txt
  done
fi

# Base call quality scores encoding
if [ ! -f $ANALYSES_DIR/base_call_quality.txt ]; then
  echo "Checking base call quality scores..." > $ANALYSES_DIR/base_call_quality.txt
  for file in $DATA_DIR/*.fastq.gz; do
    echo "File: $file" >> $ANALYSES_DIR/base_call_quality.txt
    zcat $file | head -n 40 | tail -n 4 >> $ANALYSES_DIR/base_call_quality.txt
  done
fi

# seqkit statistics
if [ ! -f $ANALYSES_DIR/fastq_stats.txt ]; then
  echo "Generating seqkit statistics..."
  srun --cpus-per-task=4 apptainer exec /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif seqkit stats --threads 4 $DATA_DIR/*.fastq.gz > $ANALYSES_DIR/fastq_stats.txt
fi

# Check for duplicate reads
if [ ! -f $ANALYSES_DIR/duplicate_reads_report.txt ]; then
  echo "Checking for duplicate reads..."
  srun --cpus-per-task=4 apptainer exec /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif seqkit rmdup -s -i $DATA_DIR/*.fastq.gz > $ANALYSES_DIR/duplicate_reads_report.txt
fi

# Search for adapter sequences
if [ ! -f $ANALYSES_DIR/adapter_search_report.txt ]; then
  echo "Searching for adapter sequences..."
  srun --cpus-per-task=4 apptainer exec /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif seqkit locate -i -p "AGATCGGA" $DATA_DIR/*.fastq.gz > $ANALYSES_DIR/adapter_search_report.txt
fi

# Create FastQC output directory
mkdir -p $ANALYSES_DIR/fastqc

# Run FastQC on all FASTQ files
srun --cpus-per-task=2 --time=00:30:00 apptainer exec exec --bind $DATA_DIR:/data_sra_fastq /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif xargs -I{} -a $RUN_ACCESSIONS_FILE fastqc $DATA_DIR/{}_1.fastq.gz $DATA_DIR/{}_2.fastq.gz -o $ANALYSES_DIR/fastqc

# see comment at the end but basically we don't have adapters and low quality is removed

# Merging paired-end reads
if [ ! -d $MERGED_DIR ]; then
  mkdir -p $MERGED_DIR
fi

# Merge paired-end reads using FLASH
echo "Merging paired-end reads..."
srun --cpus-per-task=2 apptainer exec --bind $DATA_DIR:/data_sra_fastq /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif xargs -I{} -a $RUN_ACCESSIONS_FILE flash /data_sra_fastq/{}_1.fastq.gz /data_sra_fastq/{}_2.fastq.gz -d $MERGED_DIR -o {}.flash 2>&1 | tee -a $ANALYSES_DIR/x_kargu_flash.log

date
echo "end of script"

# after inspecting the html files I see that it was incorrect earlier, the adapters have been removed. in addition reads have been trimmed to exclude low quality scores
# intital reads
# apptainer exec --bind /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/data/sra_fastq:/data_sra_fastq /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif seqkit stats /data_sra_fastq/ERR6913284_1.fastq.gz

#apptainer exec --bind /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/data/sra_fastq:/data_sra_fastq /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif seqkit stats /data_sra_fastq/ERR6913284_2.fastq.gz

#merged: 
# apptainer exec --bind /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/data/merged_pairs:/merged_pairs /proj/applied_bioinformatics/users/x_kargu/MedBioinfo/bioinformatics_tools.sif seqkit stats /merged_pairs/ERR6913284.flash.extendedFrags.fastq
# merged 1,048,239, initial 1,196,413, proportion merged 87.6%
#average length of merged reads is 151.8, which is slightly longer than the initial reads' average length of 132.3 -> longer sequences formed
# the .histogram file shows a distribution of read lengths, indicating the frequency of each read length. The peak at around 300 bp suggests that the library insert sizes are around this length, matching the expected average size of 350 bp, this is consistent  with the expected length

# the warning we got earlier is As-is, FLASH is penalizing overlaps longer than 65 bp when considering them for possible combining, so ideally we would investigate this in more detail
