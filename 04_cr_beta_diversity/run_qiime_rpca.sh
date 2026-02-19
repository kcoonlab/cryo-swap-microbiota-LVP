#!/bin/bash

# Usage: ./run_qiime_rpca.sh -table <table.biom|table.qza> -taxonomy <taxonomy.txt> -metadata <metadata.tsv> -tree <tree.nwk> -outdir <output_directory>

# Initialize variables
TABLE=""
TAXONOMY_TXT=""
METADATA=""
TREE_NWK=""
OUTPUT_DIR=""

# Parse flags
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -table) TABLE="$2"; shift ;;
        -taxonomy) TAXONOMY_TXT="$2"; shift ;;
        -metadata) METADATA="$2"; shift ;;
        -tree) TREE_NWK="$2"; shift ;;
        -outdir) OUTPUT_DIR="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if all required arguments are provided
if [[ -z "$TABLE" || -z "$TAXONOMY_TXT" || -z "$METADATA" || -z "$TREE_NWK" || -z "$OUTPUT_DIR" ]]; then
    echo "Error: Missing required arguments."
    echo "Usage: $0 -table <table.biom|table.qza> -taxonomy <taxonomy.txt> -metadata <metadata.tsv> -tree <tree.nwk> -outdir <output_directory>"
    exit 1
fi

# Check if the output directory exists and is non-empty
if [[ -d "$OUTPUT_DIR" && "$(ls -A "$OUTPUT_DIR")" ]]; then
    echo "Error: Output directory $OUTPUT_DIR already exists and is not empty."
    echo "Please specify a different directory or clear the existing directory."
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Detect if the table is a .biom or .qza file
if [[ "$TABLE" == *.biom ]]; then
    echo "Detected .biom file. Importing OTU table..."
    qiime tools import \
      --input-path "$TABLE" \
      --type 'FeatureTable[Frequency]' \
      --input-format BIOMV100Format \
      --output-path "$OUTPUT_DIR/table.qza"
elif [[ "$TABLE" == *.qza ]]; then
    echo "Detected .qza file. Proceeding with provided table..."
    cp "$TABLE" "$OUTPUT_DIR/table.qza"
else
    echo "Error: Unsupported table format. Please provide a .biom or .qza file."
    exit 1
fi

# Step 1: Import taxonomy from .txt file
echo "Importing taxonomy from .txt file..."
qiime tools import \
  --type 'FeatureData[Taxonomy]' \
  --input-format HeaderlessTSVTaxonomyFormat \
  --input-path "$TAXONOMY_TXT" \
  --output-path "$OUTPUT_DIR/taxonomy.qza"

# Step 2: Import phylogenetic tree from Newick file
echo "Importing phylogenetic tree from Newick file..."
qiime tools import \
  --input-path "$TREE_NWK" \
  --output-path "$OUTPUT_DIR/tree.qza" \
  --type 'Phylogeny[Rooted]'

# Step 3: Summarize and view the table
echo "Summarizing feature table..."
qiime feature-table summarize \
  --i-table "$OUTPUT_DIR/table.qza" \
  --o-visualization "$OUTPUT_DIR/table_summary.qzv"

# Step 4: Summarize and view taxonomy
echo "Tabulating taxonomy..."
qiime metadata tabulate \
  --m-input-file "$OUTPUT_DIR/taxonomy.qza" \
  --o-visualization "$OUTPUT_DIR/taxonomy_summary.qzv"

# Step 5: RPCA (unrarefied)
echo "Running unrarefied RPCA..."
qiime gemelli rpca \
  --i-table "$OUTPUT_DIR/table.qza" \
  --o-biplot "$OUTPUT_DIR/rpca_ordination.qza" \
  --o-distance-matrix "$OUTPUT_DIR/rpca_distance.qza"

# Step 6: Rarefy the table
echo "Rarefying the feature table..."
qiime feature-table rarefy \
  --i-table "$OUTPUT_DIR/table.qza" \
  --p-sampling-depth 1041 \
  --o-rarefied-table "$OUTPUT_DIR/rarefied_table.qza"

# Step 7: RPCA (rarefied)
echo "Running rarefied RPCA..."
qiime gemelli rpca \
  --i-table "$OUTPUT_DIR/rarefied_table.qza" \
  --o-biplot "$OUTPUT_DIR/rarefied_rpca_ordination.qza" \
  --o-distance-matrix "$OUTPUT_DIR/rarefied_rpca_distance.qza"

# Step 8: Compare rarefied and unrarefied RPCA
echo "Running rarefaction QC..."
qiime gemelli qc-rarefy \
  --i-table "$OUTPUT_DIR/table.qza" \
  --i-rarefied-distance "$OUTPUT_DIR/rarefied_rpca_distance.qza" \
  --i-unrarefied-distance "$OUTPUT_DIR/rpca_distance.qza" \
  --o-visualization "$OUTPUT_DIR/rarefaction_qc.qzv"

# Step 9: Generate biplot
echo "Generating biplot..."
qiime emperor biplot \
  --i-biplot "$OUTPUT_DIR/rpca_ordination.qza" \
  --m-sample-metadata-file "$METADATA" \
  --m-feature-metadata-file "$OUTPUT_DIR/taxonomy.qza" \
  --o-visualization "$OUTPUT_DIR/biplot.qzv" \
  --p-number-of-features 8

# Step 10: Permanova analysis
echo "Running Permanova..."
qiime diversity beta-group-significance \
  --i-distance-matrix "$OUTPUT_DIR/rpca_distance.qza" \
  --m-metadata-file "$METADATA" \
  --m-metadata-column sample_type \
  --p-method permanova \
  --o-visualization "$OUTPUT_DIR/permanova.qzv"

# Step 11: Phylogenetic RPCA with taxonomy
echo "Running phylogenetic RPCA with taxonomy..."
qiime gemelli phylogenetic-rpca-with-taxonomy \
  --i-table "$OUTPUT_DIR/table.qza" \
  --i-phylogeny "$OUTPUT_DIR/tree.qza" \
  --m-taxonomy-file "$OUTPUT_DIR/taxonomy.qza" \
  --p-min-feature-count 10 \
  --p-min-sample-count 500 \
  --o-biplot "$OUTPUT_DIR/phylo_rpca_ordination.qza" \
  --o-distance-matrix "$OUTPUT_DIR/phylo_distance.qza" \
  --o-counts-by-node-tree "$OUTPUT_DIR/phylo_tree.qza" \
  --o-counts-by-node "$OUTPUT_DIR/phylo_table.qza" \
  --o-t2t-taxonomy "$OUTPUT_DIR/phylo_taxonomy.qza"

# Step 12: Empress community plot
echo "Generating Empress community plot..."
qiime empress community-plot \
  --i-tree "$OUTPUT_DIR/phylo_tree.qza" \
  --i-feature-table "$OUTPUT_DIR/phylo_table.qza" \
  --i-pcoa "$OUTPUT_DIR/phylo_rpca_ordination.qza" \
  --m-sample-metadata-file "$METADATA" \
  --m-feature-metadata-file "$OUTPUT_DIR/phylo_taxonomy.qza" \
  --p-filter-missing-features \
  --p-number-of-features 8 \
  --o-visualization "$OUTPUT_DIR/phylo_empress.qzv"

echo "Pipeline complete. Results saved in $OUTPUT_DIR"
