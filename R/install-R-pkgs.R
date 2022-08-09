if (!require("pacman")) install.packages("pacman", repos="https://cran.r-project.org/")
if (!require("BiocManager")) install.packages("BiocManager", repos="https://cran.r-project.org/")

message(" | ", Sys.time(), " Verifying conda installation for R package dependencies...")

library(tidyverse)
library(parallel)
library(optparse)
library(purrr)
library(visNetwork)
library(ggpubr)
library(grid)
library(gridExtra)
library(vegan)
library(plotly)
library(ggrepel)
library(viridis)
library(igraph)
library(Hmisc)

message(" | ", Sys.time(), " Installing other R package dependencies from bioconductor...")

BiocManager::install("treeio")
BiocManager::install("ggtree")

message(" | ", Sys.time(), " Installing bngal R package from GitHub...")
pacman::p_install_gh("mselensky/bngal")
