#!/bin/bash

#### bngal setup script ####

# 1. create conda environment and install system libraries
conda create -n bngal -c conda-forge nlopt pandoc r=4.1 -y
conda activate bngal

# 2. export github directory as bngal variable for downstream scripts
export bngal=`pwd`

# 3. add bngal Rscripts to user shell profiles
# if macOS or linux, append to either zsh or bash shell:
if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then

	if [[ "$SHELL" == "/bin/zsh" ]]; then
		echo "alias bngal-build-nets=Rscript --vanilla ${bngal}/R/bngal-build-networks.R" >> ~/.zshrc
	elif [[ "$SHELL" == "/bin/bash" ]]; then
		echo "alias bngal-build-nets=Rscript --vanilla ${bngal}/R/bngal-build-networks.R" >> ~/.bashrc
	fi
# if Windows, append to bash shell (cli tool not supported in other shells)
elif [[ "$OSTYPE" == "win"* ]]; then

	echo "alias bngal-build-nets=Rscript --vanilla ${bngal}/R/bngal-build-networks.R" >> C:\Program Files\Git\bin\bash.exe

fi 

# 4. install necessary R packages
Rscript R/install-r-pkgs.R
