#!/bin/bash

#### bngal setup script ####

# 1. create conda environment and install system libraries
conda create -n bngal -y
conda config --add channels r 
conda config --add channels bioconda
conda config --add channels conda-forge
conda install -n bngal nlopt pandoc zlib r=4.1 r-fs r-rcpp r-igraph r-rcppeigen r-tidyverse r-rcolorbrewer r-visnetwork  -y
source activate bngal

# 2. export github directory as bngal variable for downstream aliases
export bngal=`pwd`

# 3. add bngal Rscripts to user shell profiles
# if macOS or linux, append to either zsh or bash shell:

if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then

	alias_name="alias bngal-build-nets='Rscript --vanilla ${bngal}/R/bngal-build-networks.R'"

	# output depends on zsh shell or bash
	if [[ "$SHELL" == "/bin/zsh" && $(grep ${alias_name} ~/.zshrc | wc -l | xargs) == 0 ]]
	then
		echo ${alias_name} >> ~/.zshrc
		source ~/.zshrc
	elif [[ "$SHELL" == "/bin/bash" && $(grep ${alias_name} ~/.bashrc | wc -l | xargs) == 0 ]]
	then
		echo ${alias_name} >> ~/.bashrc
		source ~/.bashrc
	fi

# if Windows, append to bash shell (cli tool not supported in other shells)
elif [[ "$OSTYPE" == "win"* ]]; then
	windows_path="C:\Program Files\Git\bin\bash.exe"
	echo "alias bngal-build-nets='Rscript --vanilla ${bngal}/R/bngal-build-networks.R'" >> $windows_path
fi 

# 4. install necessary R packages
Rscript R/install-R-pkgs.R
