#!/usr/bin/env Rscript

# load required packages
suppressMessages(if (!require("pacman")) install.packages("pacman", repos="https://cran.r-project.org/"))
pacman::p_load(optparse)
##### define cli options #####
option_list = list(
  optparse::make_option(c("-a", "--asv_table"),
                        help = "(Required) Taxonomic count table named by Silva- or GTDB-style taxonomies
                        (i.e., d__DOMAIN;p__PHYLUM;c__CLASS;o__ORDER;f__FAMILY;g__GENUS;s__SPECIES). Ideally rarefied and filtered as necessary.
                        * First column must be named 'sample-id' and must contain unique identifiers.
                        * Must be an absolute abundance table.
                        * If the input table is collapsed higher than level 7 (ASV/OTU), be sure to specify the --taxonomic_level option accordingly."),
  optparse::make_option(c("-m", "--metadata"),
                        help = "(Required) Sample metadata corresponding to asv_table. Must be a .CSV file with sample identifiers in a column named `sample-id.`"),
  optparse::make_option(c("-o", "--output"), default = "bngal-results",
                        help = "Output directory for network graphs and data.
                        * Default = %default"),
  optparse::make_option(c("-c", "--correlation"), default = "spearman",
                        help = "Metric for pairwise comparisons. Can be one of 'pearson' or 'spearman'.
                        * Default = %default"),
  optparse::make_option(c("-l", "--transformation"), default = NULL,
                        help = "Numeric transformation to apply to input data before correlation calculations.
                        Can be one of 'log10'.
                        * Default = %default"),
  optparse::make_option(c("-r", "--corr_columns"), default = NULL,
                        help = "Metadata columns to include in pairwise correlation networks.
                        * Multiple columns may be provided given the following syntax: 'col1,col2'
                        * Default = %default"),
  optparse::make_option(c("-k", "--corr_cutoff"), default = 0.6,
                        help = "Absolute correlation coefficient cutoff for pairwise comparisons.
                        * Default = %default"),
  optparse::make_option(c("-p", "--p_value"), default = 0.05,
                        help  = "Maximum cutoff for p-values calculated from pairwise relationships.
                        * Default = %default"),
  optparse::make_option(c("-f", "--abun_cutoff"), default = 0,
                        help = "Relative abundance cutoff for taxa (values 0-1 accepted). Anything lower than this value is removed before network construction.
                        * Default = %default"),
  optparse::make_option(c("-x", "--cores"), default = 1,
                        help = "Number of CPUs to use. Can only parallelize on Mac or Linux OS.
                        * Default = %default"),
  optparse::make_option(c("-n", "--subnetworks"), default = NULL,
                        help = "Metadata column by which to split data in order to create separate networks.
                        * If not provided, bngal will create a single network from the input ASV table.
                        * Default = %default"),
  optparse::make_option(c("-t", "--taxonomic_level"), default = "asv",
                        help = "Taxonomic level at which to construct co-occurrence networks. Must be at the same level or above the input --asv_table.
                        Can be one of 'phylum', 'class', 'order', 'family', 'genus', or 'asv'
                        * Default = %default"),
  optparse::make_option(c("-d", "--direction"), default = "greaterThan",
                        help = "Direction for --abun-cutoff. Can be one of 'greaterThan' or 'lessThan'.
                        * Default = '%default'"),
  optparse::make_option(c("-s", "--sign"), default = "all",
                        help = "Type of pairwise relationship for network construction. Can be one of 'positive', 'negative', or 'all'.
                        * Default = '%default'"),
  optparse::make_option(c("-b", "--obs_threshold"), default = 5,
                        help = "('Observational threshold') Minimum number of unique observations required for a given pairwise relationship to be included in the network.
                        * Default = %default"),
  optparse::make_option(c("-g", "--graph_layout"), default = "layout_nicely",
                        help = "Type of igraph layout for output network plots.
                        * Refer to the igraph documentation for the full list of options:
                          https://igraph.org/r/html/latest/layout_.html
                        * Default = '%default'")

)

opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)

if (is.null(opt$asv_table) | is.null(opt$metadata)){
  print_help(opt_parser)
  stop("[", Sys.time(), "] At least one required argument is missing. See help above for more information.")
}

# create output directory
out.dr = opt$output
logfiles.dir = file.path(out.dr, "logfiles")
if (!dir.exists(logfiles.dir)) dir.create(logfiles.dir, recursive = TRUE)
logfile_name = file.path(logfiles.dir, paste0(opt$taxonomic_level, "-bngal-build-networks.log"))
msg <- file(logfile_name, open = "a")
sink(file = msg,
     append = FALSE,
     type = "message")

#####

message("
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
")

# load packages
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(dplyr))
pacman::p_load(parallel, tidyr,
               Hmisc, RColorBrewer, igraph,
               visNetwork, ggpubr, grid, gridExtra, plotly,
               purrr, viridis)
library(bngal)

# map cli variables to script variables
#asv_table = read_csv(opt$asv_table, col_types = cols())
asv_table = read.csv(opt$asv_table, check.names = FALSE) %>%
  filter(`sample-id` %in% unique(metadata$`sample-id`))
colnames(asv_table) <- gsub(" ", "", colnames(asv_table)) # remove spaces
metadata = read_csv(opt$metadata, col_types = cols())
correlation = opt$correlation
transformation = opt$transformation
sign = opt$sign
direction = opt$direction
correlation_cutoff = opt$corr_cutoff
cutoff.val = opt$abun_cutoff
pval.cutoff = opt$p_value
corr_cols = opt$corr_columns
sub.comm.column = opt$subnetworks
if (!is.null(corr_cols)) {
  corr_cols = stringr::str_split(corr_cols, ",")
  corr_cols = corr_cols[[1]]
}
obs.cutoff = opt$obs_threshold
graph_layout = opt$graph_layout
NCORES = opt$cores
tax_level = opt$taxonomic_level
tax_levels = c("phylum", "class", "order", "family", "genus", "asv")

message(" | \\\\\\ Input parameters \\\\\\ | \n",
        " ----------------------------\n",
        " | Parent directory         : ", paste0(getwd(), "/"), "\n",
        " |  * ASV table             :  * ", opt$asv_table, "\n",
        " |  * Metadata              :  * ", opt$metadata, "\n",
        " |  * Output directory      :  * ", out.dr, "\n",
        " | Correlation coefficient  : ", correlation, "\n",
        " |  * Observation threshold :  * ", obs.cutoff, "\n",
        " |  * Direction             :  * ", sign, "\n",
        " |  * Cutoff (absolute val) :  * ", correlation_cutoff, "\n",
        " |  * p-value cutoff        :  * ", pval.cutoff, "\n",
        " | Relative abundance cutoff: ", direction, " ", cutoff.val, "\n",
        " |  * Data transformation   :  * ", transformation, "\n",
        " ----------------------------\n",
        " | Metadata columns included in correlation network: \n",
        " |  * ", paste0(shQuote(corr_cols), collapse = ", "), "\n",
        " | Subnetworks created via metadata column: \n",
        " |  * ", sub.comm.column)

message(" | .\n | .\n | .\n | .\n | _____________________________________________________________________\n",
        " | [", Sys.time(), "] Building ", tax_level, "-level networks...")

##### Pipeline #####
t0=Sys.time()
binned_tax <- bngal::bin_taxonomy(asv.table = asv_table,
                                  meta.data = metadata,
                                  tax.level = tax_level,
                                  direction = direction,
                                  cutoff.val = cutoff.val,
                                  compositional = FALSE)
message(" | [", Sys.time(), "] bin_taxonomy() complete")
t1=Sys.time()

prepared_data <- bngal::prepare_network_data(
  binned.tax = binned_tax,
  meta.data = metadata,
  corr.cols = corr_cols,
  sub.comms = sub.comm.column)
message(" | [", Sys.time(), "] prepare_network_data() complete")
t2<-Sys.time()

pw.out <- file.path(out.dr, paste0("pairwise-summaries"))
if (!dir.exists(pw.out)) dir.create(pw.out, recursive = TRUE)

corr_data <- bngal::prepare_corr_data(
  prepared.data = prepared_data,
  obs.cutoff = obs.cutoff,
  out.dr = pw.out,
  transformation = transformation
)
message(" | [", Sys.time(), "] prepare_corr_data() complete")

t3=Sys.time()
corr_matrix <- bngal::corr_matrix(
  filtered.matrix = corr_data,
  correlation = correlation#,
  #cores = NCORES
)
message(" | [", Sys.time(), "] corr_matrix() complete")

t4=Sys.time()

# generate nodes and edges
node_ids <- bngal::get_node_ids(
  prepared.data = prepared_data,
  corr.matrix = corr_matrix
)
message(" | [", Sys.time(), "] get_node_ids() complete")

t5=Sys.time()
edges <- bngal::generate_edges(
  corr.matrix = corr_matrix,
  correlation = correlation,
  node.ids = node_ids
)
message(" | [", Sys.time(), "] generate_edges() complete")

t6=Sys.time()
# filter for positive, negative, or all correlations within defined pval/correlation coefficient cutoffs
prepro_data <- bngal::prepare_net_features(
  edges. = edges,
  node.ids = node_ids,
  p.val.cutoff = pval.cutoff,
  correlation = correlation,
  correlation.cutoff = correlation_cutoff,
  sign = sign
)
# export final QC'd pairwise summary data to "pairwise-summary" output subfolder
bngal::pw_summary(corr.data = corr_data,
                  preprocessed.features = prepro_data,
                  tax.level = tax_level,
                  out.dr = out.dr,
                  cores=NCORES)

message(" | [", Sys.time(), "] prepro_net_features() complete")

t7=Sys.time()

igraph_list <- bngal::get_igraph(
  prepro.data = prepro_data
)
message(" | [", Sys.time(), "] get_igraph() complete")

t8=Sys.time()

ebcs <- bngal::get_edge_betweenness(
  igraph_list
)
message(" | [", Sys.time(), "] get_edge_betweenness() complete")

t9 <- Sys.time()
# extract edge betweenness membership ids for each node id
members <- bngal::get_ebc_member_ids(
  ebcs
)
message(" | [", Sys.time(), "] get_ebc_member_ids() complete")
t10 <- Sys.time()
#
clusters <- bngal::get_ebc_clusters(
  prepro_data,
  members,
  igraph_list,
  sign
)
message(" | [", Sys.time(), "] get_ebc_clusters() complete")
t11 <- Sys.time()
# prepare node data for plotting
node_color_data <- bngal::color_nodes(
  binned.tax = binned_tax,
  clusters.to.color = clusters
)
message(" | [", Sys.time(), "] color_nodes() complete")
t12 <- Sys.time()

# out.dr.plot = file.path(out.dr, "network-plots", tax_level)
# if (!dir.exists(out.dr.plot)) dir.create(out.dr.plot, recursive = TRUE)

if (tax_level %in% c("family", "genus", "asv")) {
  # add color scheme from functional groupings inspired by Brankovits et al. (2017)
  bngal::plot_networks(
    node.color.data = node_color_data,
    filled.by = "other",
    graph.layout = graph_layout,
    out.dr = out.dr,
    sign = sign,
    direction = direction,
    cutoff.val = cutoff.val,
    pval.cutoff = pval.cutoff,
    other.variable = "grouping"
  )
}

# plot networks
for (selected_By in c("phylum", "edge_btwn_cluster")) {
  bngal::plot_networks(
    node.color.data = node_color_data,
    filled.by = selected_By,
    graph.layout = graph_layout,
    out.dr = out.dr,
    sign = sign,
    direction = direction,
    cutoff.val = cutoff.val,
    pval.cutoff = pval.cutoff
  )
}
message(" | [", Sys.time(), "] plot_networks() complete")
t13 <- Sys.time()

# export network data
# create output directory for exported network data
out.dr.nd = file.path(out.dr, "network-data")
if (!dir.exists(out.dr.nd)) dir.create(out.dr.nd, recursive = TRUE)

bngal::export_network_data(
  node.color.data = node_color_data,
  tax.level = tax_level,
  out.dr = out.dr.nd
)
message(" | [", Sys.time(), "] export_network_data() complete")
t14 <- Sys.time()

names <- c(
  "bngal::bin_taxonomy",
  "bngal::prepare_network_data",
  "bngal::prepare_corr_data",
  "bngal::corr_matrix",
  "bngal::get_node_ids",
  "bngal::generate_edges",
  "bngal::prepro_net_features",
  "bngal::get_igraph",
  "bngal::get_edge_betweenness",
  "bngal::get_ebc_member_ids",
  "bngal::get_ebc_clusters",
  "bngal::node_color_data",
  "bngal::plot_networks",
  "bngal::export_network_data"
)
times <- c(
  format(t1-t0),
  format(t2-t1),
  format(t3-t2),
  format(t4-t3),
  format(t5-t4),
  format(t6-t5),
  format(t7-t6),
  format(t8-t7),
  format(t9-t8),
  format(t10-t9),
  format(t11-t10),
  format(t12-t11),
  format(t13-t12),
  format(t14-t13)
)
taxa_lev <- rep(tax_level, length(times))
ncores <- rep(opt$cores, length(times))
comms <- rep(sub.comm.column, length(times))
system_info = Sys.info()
sysname <- rep(system_info[['sysname']], length(times))
release <- rep(system_info[['release']], length(times))

runtime_table <- data.frame('function_name' = names,
                            'times' = times,
                            'taxonomic_level' = taxa_lev,
                            'CPUs' = ncores,
                            'visNetwork_layout' = graph_layout,
                            'sysname' = sysname,
                            'release' = release)

if (!is.null(comms)) {
  runtime_table$num_subcommunities = comms
} else {
  runtime_table$num_subcommunities = rep(1, length(times))
}

# create runtime table directory
out.dr.rt = file.path(out.dr, "runtime-tables")
if (!dir.exists(out.dr.rt)) dir.create(out.dr.rt, recursive = TRUE)

message(" | [", Sys.time(), "] exporting runtime data to ", out.dr.rt)

write_csv(runtime_table, paste0(file.path(out.dr.rt,
                                          paste0(
                                            tax_level, "_",
                                            opt$cores, "cores_",
                                            "runtime-table.csv"))
))

message(" | [", Sys.time(), "] ", tax_level, "-level networks complete!")
closeAllConnections()
