#!/bin/bash

source activate bngal

# build regional network
cd /Users/matt/Documents/Manuscripts/YucatanBioGeo/Yucatan_R
mkdir -p bngal-output-test
cd bngal-output-test
asv_table=../asv_table_rarefied9957-noPIT32.csv
meta_data=../metadata_9957rarefied-noPIT32.csv
GRAPH_LO="layout_with_kk"
OUT_DR=`pwd`/network-region-ot5-9957rare-noPIT32-$GRAPH_LO-ToL-colors
mkdir -p $OUT_DR

echo "[`date`] Building networks by region (observational threshold = 5)..."

Rscript /Users/matt/Projects/tmp-bngal/bngal-cli/R/bngal-build-networks.R \
  --asv_table=$asv_table \
  --metadata=$meta_data \
  --output=$OUT_DR \
  --obs_threshold=5 \
  --subnetworks="region" \
  --cores=4 \
  --corr_columns='wc_depth,mS_cm_F21,SO4_meqL_F21,Cl_meqL_F21,S_meqL,dist_coast_m,Alk_meas_ueqL' \
  --graph_layout=$GRAPH_LO

echo "[`date`] Summarizing networks by region (observational threshold = 5)..."

mkdir -p ${OUT_DR}/filledBy-cave_name
bngal-summarize-nets \
  --asv_table=$asv_table \
  --metadata=$meta_data \
  --network_dir=$OUT_DR \
  --output=${OUT_DR}/filledBy-cave_name \
  --cores=4 \
  --subnetworks="region" \
  --fill_ebc_by="cave_name" \
  --interactive=FALSE
