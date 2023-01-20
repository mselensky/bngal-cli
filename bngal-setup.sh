#!/bin/bash

#### bngal setup script ####

printf "
___________________________________________________

    ██████╗ ███╗   ██╗ ██████╗  █████╗ ██╗
    ██╔══██╗████╗  ██║██╔════╝ ██╔══██╗██║
    ██████╔╝██╔██╗ ██║██║  ███╗███████║██║
    ██╔══██╗██║╚██╗██║██║   ██║██╔══██║██║
    ██████╔╝██║ ╚████║╚██████╔╝██║  ██║███████╗
    ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝    
  Biological Network Graph Analysis and Learning   
            (c) Matt Selensky 2023
            e: mselensky@gmail.com
      https://github.com/mselensky/bngal

___________________________________________________

-- . --- .-- -- . --- .-- -- . --- .-- -- . --- .--
      -.. .- .--. .... -. . / --. .. .-. .-..      
"

# create bngal conda environment
conda env create -f bngal.yml
source activate bngal

# export Rscript pipelines as executables to bngal bin
cp R/bngal-build-networks.R ${CONDA_PREFIX}/bin/bngal-build-nets
cp R/bngal-summarize-networks.R ${CONDA_PREFIX}/bin/bngal-summarize-nets
chmod +x ${CONDA_PREFIX}/bin/bngal-build-nets
chmod +x ${CONDA_PREFIX}/bin/bngal-summarize-nets

R -e "if (!require('bngal')) pacman::p_install_gh('mselensky/bngal')" &> R-pkgs-install.log

# double check R package depedency installations and install bngal R package from GitHub
# Rscript --vanilla R/install-R-pkgs.R &> R-pkgs-install.log
