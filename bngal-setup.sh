#!/bin/bash

#### bngal setup script ####

# 1. create bngal conda environment
conda env create -f bngal.yml

source activate bngal

# export Rscript pipelines to bngal bin
cp R/bngal-build-networks.R ${CONDA_PREFIX}/bin/bngal-build-networks.R
cp R/bngal-summarize-networks.R ${CONDA_PREFIX}/bin/bngal-summarize-networks.R

# save as functions
function_name1="bngal-build-nets () { Rscript --vanilla ${CONDA_PREFIX}/bin/bngal-build-networks.R }"
function_name2="bngal-summarize-nets () { Rscript --vanilla ${CONDA_PREFIX}/bin/bngal-summarize-networks.R }"

# add bngal functions to user shell profiles
if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then

	# output depends on zsh shell or bash
	if [[ "$SHELL" == "/bin/zsh" ]] && [[ $(grep -e "${function_name1}" ~/.zshrc | wc -l | xargs) == 0 ]] && [[ $(grep -e "${function_name2}" ~/.zshrc | wc -l | xargs) == 0 ]]
	then
		echo ${function_name1} >> ~/.zshrc
		echo ${function_name2} >> ~/.zshrc
		source ~/.zshrc
	elif [[ "$SHELL" == "/bin/bash" ]] && [[ $(grep -e "${function_name1}" ~/.bashrc | wc -l | xargs) == 0 ]] && [[ $(grep -e "${function_name2}" ~/.bashrc | wc -l | xargs) == 0 ]]
	then
		echo ${function_name1} >> ~/.bashrc
		echo ${function_name2} >> ~/.bashrc
		source ~/.bashrc
	fi
# if Windows, append to bash shell (cli tool not supported in other shells)
elif [[ "$OSTYPE" == "win"* ]] || [[ "$OSTYPE" == "msys" ]]; then
	windows_path="C:\Program Files\Git\bin\bash.exe"
	echo ${function_name1} >> $windows_path
	echo ${function_name2} >> $windows_path

else
	echo "Error: OS not supported :("
fi

conda activate bngal

# double check R package depedency installations and install bngal R package from GitHub
Rscript --vanilla R/install-R-pkgs.R &> R-pkgs-install.log
