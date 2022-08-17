#!/bin/bash

#### bngal setup script ####

# 1. create conda environment and install system libraries

# for macOS
conda create -n bngal -y
conda config --add channels defaults
conda config --add channels r 
conda config --add channels bioconda
conda config --add channels conda-forge
conda install -n bngal cmake nlopt pandoc=2.18 zlib r=4.1 r-hmisc r-fs r-rcpp r-sparsem r-igraph r-rcppeigen r-tidyverse r-rcolorbrewer r-visnetwork r-vegan r-purrr r-optparse r-ggpubr r-gridextra r-plotly r-ggrepel r-viridis r-igraph -y
source activate bngal

# 2. export github directory as bngal variable for downstream aliases
export bngal=`pwd`

# 3. add bngal Rscripts to user shell profiles
# if macOS or linux, append to either zsh or bash shell:

alias_name1="alias bngal-build-nets='Rscript --vanilla ${bngal}/R/bngal-build-networks.R'"
alias_name2="alias bngal-summarize-nets='Rscript --vanilla ${bngal}/R/bngal-summarize-networks.R'"

if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
	
	# output depends on zsh shell or bash
	if [[ "$SHELL" == "/bin/zsh" ]] && [[ $(grep -e "${alias_name1}" ~/.zshrc | wc -l | xargs) == 0 ]] && [[ $(grep -e "${alias_name2}" ~/.zshrc | wc -l | xargs) == 0 ]]
	then
		echo ${alias_name1} >> ~/.zshrc
		echo ${alias_name2} >> ~/.zshrc
		source ~/.zshrc
	elif [[ "$SHELL" == "/bin/bash" ]] && [[ $(grep -e "${alias_name1}" ~/.bashrc | wc -l | xargs) == 0 ]] && [[ $(grep -e "${alias_name2}" ~/.bashrc | wc -l | xargs) == 0 ]]
	then
		echo ${alias_name1} >> ~/.bashrc
		echo ${alias_name2} >> ~/.bashrc
		source ~/.bashrc
	fi
# if Windows, append to bash shell (cli tool not supported in other shells)
elif [[ "$OSTYPE" == "win"* ]]; then
	windows_path="C:\Program Files\Git\bin\bash.exe"
	echo ${alias_name1} >> $windows_path
	echo ${alias_name2} >> $windows_path

else 
	echo "Error: OS not supported"
fi

source activate bngal
# 4. install necessary R packages and write output to file
Rscript --vanilla R/install-R-pkgs.R > R-pkgs-install.log
