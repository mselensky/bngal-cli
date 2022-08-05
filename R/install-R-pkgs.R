if (!require("pacman")) install.packages("pacman", repos="https://cran.r-project.org/")
if (!require("tidyverse")) install.packages("tidyverse", repos="https://cran.r-project.org/")
if (!require("BiocManager")) install.packages("BiocManager", repos="https://cran.r-project.org/")
pacman::p_load(parallel, tidyverse, plyr, Hmisc, RColorBrewer, igraph, 
               visNetwork, ggpubr, grid, gridExtra, vegan, plotly, 
               ggrepel, purrr, viridis, optparse)
BiocManager::install("treeio")
BiocManager::install("ggtree")

pacman::p_install_gh("mselensky/bngal")
