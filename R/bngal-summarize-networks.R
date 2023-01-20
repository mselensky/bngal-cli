#!/usr/bin/env Rscript

# load required packages
suppressMessages(if (!require("pacman")) install.packages("pacman", repos="https://cran.r-project.org/"))
pacman::p_load(optparse)
##### define cli options #####
option_list = list(
  optparse::make_option(c("-a", "--asv_table"),
                        help = "(Required) Taxonomic count table named by Silva- or GTDB-style taxonomies (i.e., d__DOMAIN;p__PHYLUM;c__CLASS;o__ORDER;f__FAMILY;g__GENUS;s__SPECIES). Ideally rarefied and filtered as necessary.
                        * First column must be named 'sample-id' and must contain unique identifiers.
                        * Must be an absolute abundance table."),
  optparse::make_option(c("-m", "--metadata"),
                        help = "(Required) Sample metadata corresponding to asv_table. Must be a .CSV file with sample identifiers in a column named `sample-id.`"),
  optparse::make_option(c("-w", "--network_dir"),
                        help = "(Required) Input network data. Should be parent folder of `bngal-build-nets` output. Output subfolders will write here as well unless --output is specified."),
  optparse::make_option(c("-o", "--output"), default = NULL,
                        help = "Optional output folder. May be useful if one desires to test multiple `-f` inputs on the same network data."),
  optparse::make_option(c("-n", "--subnetworks"), default = NULL,
                        help = "Metadata column by which to split data in order to create separate networks.
                        * If not provided, bngal will create a single network from the input ASV table.
                        * Default = %default"),
  optparse::make_option(c("-f", "--fill_ebc_by"), default = NULL,
                        help = "Metadata column by which to fill EBC composition plots.
                        * Default = %default"),
  optparse::make_option(c("-i", "--interactive"), default = FALSE,
                        help = "Determines whether output EBC composition plots are exported as interactive HTMLs (TRUE) or static PDFs (FALSE)
                        * Default = %default"),
  optparse::make_option(c("-x", "--cores"), default = 1,
                        help = "Number of CPUs to use. Can only parallelize on Mac or Linux OS. Currently, bngal can only run on multiple cores when --subnetworks is provided.
                        * Default = %default")
)

opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)

if (is.null(opt$asv_table) | is.null(opt$metadata) | is.null(opt$network_dir)){
  print_help(opt_parser)
  stop("[", Sys.time(), "] At least one required argument is missing. See help above for more information.")
}

logfile_name = file.path(opt$network_dir, "bngal-summarize-networks.log")
msg <- file(logfile_name, open = "a")
sink(file = msg,
     append = FALSE,
     type = "message")

message("
__________________________________________________________
                  Welcome to BNGAL!

      Biological Network Graph Analysis and Learning
               (c) Matt Selensky 2023

        ██████╗ ███╗   ██╗ ██████╗  █████╗ ██╗
        ██╔══██╗████╗  ██║██╔════╝ ██╔══██╗██║
        ██████╔╝██╔██╗ ██║██║  ███╗███████║██║
        ██╔══██╗██║╚██╗██║██║   ██║██╔══██║██║
        ██████╔╝██║ ╚████║╚██████╔╝██║  ██║███████╗
        ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝
         https://github.com/mselensky/bngal
               e: mselensky@gmail.com

__________________________________________________________

   -- . --- .-- -- . --- .-- -- . --- .-- -- . --- .--
         -.. .- .--. .... -. . / --. .. .-. .-..

        ")

pacman::p_load(tidyverse, parallel, ggpubr, grid, gridExtra, viridis, vegan,
               ggdendro)
library(bngal)

# inputs
network_dir = file.path(opt$network_dir, "network-data")
asv.table = opt$asv_table
metadata = read_csv(opt$metadata, col_types = cols())
asv_table = read_csv(asv.table, col_types = cols()) %>%
  filter(`sample-id` %in% unique(metadata$`sample-id`))
sub.comm.column=opt$subnetworks
ebc.comp.fill = opt$fill_ebc_by
metadata.cols = ebc.comp.fill
NCORES = opt$cores
# output will write to input folder by default unless --output is defined
if (is.null(opt$output)) {
  out.dr = opt$network_dir
} else {
  out.dr = opt$output
}

tax.levels = c("phylum", "class", "order", "family", "genus", "asv")


out.dr.core = file.path(out.dr, "ebc-composition-plots")
if (!dir.exists(out.dr.core)) dir.create(out.dr.core, recursive = TRUE)


# load network data from bngal-build-nets
network_data <- bngal::load_network_data(network_dir)
message(" | [", Sys.time(), "] Network data imported from:\n |   * ", network_dir)

# bin taxonomy at each level of classification
binned_tax <- parallel::mclapply(X = tax.levels,
                                 FUN = function(i){bngal::bin_taxonomy(asv.table = asv_table,
                                                                       meta.data = metadata,
                                                                       tax.level = i,
                                                                       remove.singletons = FALSE,
                                                                       compositional = TRUE)},
                                 mc.cores = NCORES)
names(binned_tax) = tax.levels

# extract network node data
ebc_nodes <- bngal::extract_node_data(network.data = network_data)
message(" | [", Sys.time(), "] Node data extracted")


# calculate shannon, simpson, and invsimpson for all levels of tax.
alpha_diversity <- bngal::get_alpha.div(binned.taxonomy = binned_tax)
message(" | [", Sys.time(), "] Alpha diversity calculated")

# calculate edge between cluster compositions and abundance
ebc_comps <- parallel::mclapply(X = tax.levels,
                                FUN = function(i){
                                  bngal::ebc_compositions(ebc.nodes = ebc_nodes,
                                                          binned.taxonomy = binned_tax,
                                                          alpha.div = alpha_diversity,
                                                          tax.level = i,
                                                          metadata = metadata,
                                                          metadata.cols = ebc.comp.fill,
                                                          sub.comms = sub.comm.column)
                                },
                                mc.cores = NCORES)
names(ebc_comps) = tax.levels
message(" | [", Sys.time(), "] EBC compositions calculated")

out.dr.taxa.bp = file.path(out.dr, "taxa-barplots")
if (!dir.exists(out.dr.taxa.bp)) dir.create(out.dr.taxa.bp, recursive = TRUE)

if (!is.null(ebc.comp.fill)) {
  for (i in tax.levels) {
    core_comps <- bngal::plot_core_comp(ebc_comps, i, metadata, fill.by = ebc.comp.fill)
    suppressMessages(
      ggplot2::ggsave(file.path(out.dr.core, paste0(i, "-filled.by-", ebc.comp.fill, ".pdf")),
                      core_comps,
                      device = "pdf")
    )
  }
  message(" | [", Sys.time(), "] EBC composition plots exported to\n |   * ", out.dr.core)
} else {
  message(" | [", Sys.time(), "] No --fill_by_ebc option found; skipping EBC composition plots")
}

# output summary data for each level of taxonomic classification
out <- parallel::mclapply(X = tax.levels,
                          FUN = function(x){
                            bngal::export_ebc_taxa_summary(binned.taxonomy = binned_tax,
                                                           ebc.nodes.abun = ebc_comps,
                                                           tax.level = x,
                                                           out.dr = out.dr)
                          },
                          mc.cores = NCORES)
message(" | [", Sys.time(), "] EBC and taxonomic abundance data exported to\n |   * ", file.path(out.dr, "network-summary-tables"))
Sys.sleep(3)

dendros <- bngal::build_dendrograms(binned.taxonomy = binned_tax,
                                    metadata = metadata,
                                    color.by = ebc.comp.fill,
                                    trans = "log10",
                                    sub.comms = sub.comm.column)

Sys.sleep(3)

taxa.plots=list()
for (i in tax.levels) {
  for (x in c("phylum", "ebc")) {
    suppressWarnings(
      taxa.plots[[i]][[x]] <- build_taxa.barplot(plotdata = ebc_comps,
                         tax.level = i,
                         dendrogram = dendros,
                         fill.by = x,
                         interactive = opt$interactive,
                         out.dr = out.dr,
                         metadata.cols = metadata.cols)
    )
  }

  if (i %in% c("family", "genus", "asv")) {
    suppressWarnings(
      taxa.plots[[i]][[x]] <- build_taxa.barplot(plotdata = ebc_comps,
                         tax.level = i,
                         dendrogram = dendros,
                         fill.by = "grouping",
                         interactive = opt$interactive,
                         out.dr = out.dr,
                         metadata.cols = metadata.cols)
    )
  }

}


out.dr.taxa.bp = file.path(out.dr, "taxa-barplots")
message(" | [", Sys.time(), "] Exported summary barplots to:\n |   * ", out.dr.taxa.bp)
message(" | [", Sys.time(), "] bngal-summarize-nets complete!")
