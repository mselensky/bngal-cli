#!/bin/bash

source activate conda

### for development only: export conda env to cross-platform yml and host on bngal-cli GitHub
#### from my mac
conda create -n bngal -y
conda config --add channels defaults
conda config --add channels r 
conda config --add channels bioconda
conda config --add channels conda-forge
conda install -n bngal cmake nlopt pandoc=2.18 zlib r=4.1 r-ape r-later r-hmisc r-ggdendro r-scales r-fs r-rcpp r-sparsem r-igraph r-rcppeigen r-tidyverse r-rcolorbrewer r-visnetwork r-vegan r-purrr r-optparse r-ggpubr r-gridextra r-plotly r-ggrepel r-viridis r-igraph r-pacman -y
#bioconductor-treeio bioconductor-ggtree
source activate bngal
conda env export --from-history > bngal.yml
sed '/prefix/d' bngal.yml > ../bngal.yml
rm bngal.yml
