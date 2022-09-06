#!/bin/bash

#### bngal setup script ####

# 1. create bngal conda environment
conda env create -f bngal.yml

source activate bngal

# export Rscript pipelines to bngal bin
cp R/bngal-build-networks.R ${CONDA_PREFIX}/bin/bngal-build-networks.R 
cp R/bngal-summarize-networks.R ${CONDA_PREFIX}/bin/bngal-summarize-networks.R 

# save as aliases
alias_name1="alias bngal-build-nets='Rscript --vanilla ${CONDA_PREFIX}/bin/bngal-build-networks.R'"
alias_name2="alias bngal-summarize-nets='Rscript --vanilla ${CONDA_PREFIX}/bin/bngal-summarize-networks.R'"

# add bngal aliases to user shell profiles
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
	echo "Error: OS not supported :("
fi

source activate bngal

# 4. double check R package depedency installations and install bngal R package from GitHub
Rscript --vanilla R/install-R-pkgs.R > R-pkgs-install.log
