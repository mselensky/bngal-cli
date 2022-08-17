# load required packages
suppressMessages(if (!require("pacman")) install.packages("pacman", repos="https://cran.r-project.org/"))
pacman::p_load(optparse)
##### define cli options #####
option_list = list(
  optparse::make_option(c("-a", "--asv_table"),
                        help = "(Required) ASV count table named by Silva-138 L7 taxonomies. Ideally rarefied and filtered as necessary.
                        * First column must be named 'sample-id' and must contain unique identifiers.
                        * Must be an absolute abundance ASV table."),
  optparse::make_option(c("-m", "--metadata"),
                        help = "(Required) Sample metadata corresponding to asv_table. Must be a .CSV file with sample identifiers in a column named `sample-id.`"),
  optparse::make_option(c("-w", "--network_dir"),
                        help = "(Required) Input network data. Should be parent folder of output from bngal-build-nets"),
  optparse::make_option(c("-o", "--output"),
                        help = "(Required) Output directory for network summary graphs and data."),
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
                        help = "Number of CPUs to use. Can only parallelize on Mac or Linux OS. Currently, bngal can only run on multiple cores when sub_comm_col is provided.
                        * Default = %default")
)

opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)

if (is.null(opt$asv_table) | is.null(opt$metadata) | is.null(opt$network_dir) | is.null(opt$output)){
  print_help(opt_parser)
  stop("[", Sys.time(), "] At least one required argument is missing. See help above for more information.")
}

logfile_name = file.path(opt$output, "bngal-summarize-networks.log")
msg <- file(logfile_name, open = "a")
sink(file = msg,
     append = FALSE,
     type = "message")

message("
__________________________________________________________
                  Welcome to BNGAL!

      Biological Network Graph Analysis and Learning
               (c) Matt Selensky 2022

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

pacman::p_load(tidyverse, parallel, ggpubr, grid, gridExtra, viridis, treeio, ggtree, vegan)
library(bngal)

# inputs
network_dir = file.path(opt$network_dir, "network-data")
asv.table = opt$asv_table
metadata = read_csv(opt$metadata, col_types = cols())
asv_table = read_csv(asv.table, col_types = cols()) %>%
  filter(`sample-id` %in% unique(metadata$`sample-id`))
sub.comms=opt$subnetworks
out.dr = opt$output
ebc.comp.fill = opt$fill_ebc_by
metadata.cols = ebc.comp.fill
NCORES = opt$cores

tax.levels = c("phylum", "class", "order", "family", "genus", "asv")


out.dr.core = file.path(out.dr, "ebc-composition-plots")
if (!dir.exists(out.dr.core)) dir.create(out.dr.core, recursive = TRUE)


# load network data from bngal-build-nets
network_data <- bngal::load_network_data(network_dir)
message(" | [", Sys.time(), "] Network data imported from:\n |   * ", network_dir)

# get number of cores
# if (Sys.getenv("SLURM_NTASKS") > 1) {
#   NCORES = Sys.getenv("SLURM_NTASKS")
# } else if (parallel::detectCores() > 2) {
#   NCORES = parallel::detectCores()-1
#   # only reserve cores for each level of taxonomic classification to run in parallel
#   if (NCORES > length(tax.levels)) NCORES = as.numeric(length(tax.levels))
# } else {
#   NCORES = 1
# }

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

# calcuate edge between cluster compositions and abundance
ebc_comps <- parallel::mclapply(X = tax.levels,
                                FUN = function(i){
                                  bngal::ebc_compositions(ebc.nodes = ebc_nodes,
                                                          binned.taxonomy = binned_tax,
                                                          alpha.div = alpha_diversity,
                                                          tax.level = i,
                                                          metadata = metadata,
                                                          metadata.cols = ebc.comp.fill,
                                                          sub.comms = sub.comms)
                                },
                                mc.cores = NCORES)
names(ebc_comps) = tax.levels
message(" | [", Sys.time(), "] EBC compositions calculated")

out.dr.taxa.bp = file.path(out.dr, "taxa-barplots")
if (!dir.exists(out.dr.taxa.bp)) dir.create(out.dr.taxa.bp, recursive = TRUE)

for (i in tax.levels) {
  core_comps <- bngal::plot_core_comp(ebc_comps, i, metadata, fill.by = ebc.comp.fill)
  ggplot2::ggsave(file.path(out.dr.core, paste0(i, "-filled.by-", ebc.comp.fill, ".pdf")),
                  core_comps,
                  device = "pdf")
}
message(" | [", Sys.time(), "] EBC composition plots exported to\n |   * ", out.dr.core)

# output summary data for each level of taxonomic classification
parallel::mclapply(X = tax.levels,
                   FUN = function(x){
                     suppressMessages(
                       bngal::export_ebc_taxa_summary(binned.taxonomy = binned_tax,
                                                      ebc.nodes.abun = ebc_comps,
                                                      tax.level = x,
                                                      out.dr = out.dr)
                     )
                   },
                   mc.cores = NCORES)
message(" | [", Sys.time(), "] EBC and taxonomic abundance data exported to\n |   * ", file.path(out.dr, "network-summary-tables"))
Sys.sleep(3)

dendros <- bngal::build_dendrograms(binned.taxonomy = binned_tax,
                                    metadata = metadata,
                                    color.by = ebc.comp.fill,
                                    trans = "log10",
                                    sub.comms = sub.comms)
message(" | [", Sys.time(), "] Dendrograms constructed")

Sys.sleep(3)

# parallel::mclapply(X = tax.levels,
#                    FUN = function(i){
#                      bngal::build_taxa.barplot(plotdata = ebc_comps,
#                                                tax.level = i,
#                                                dendrogram = dendros,
#                                                fill.by = "phylum",
#                                                interactive = F,
#                                                out.dr = out.dr,
#                                                metadata.cols = metadata.cols)
#                    },
#                    mc.cores = NCORES)

for (i in tax.levels) {
build_taxa.barplot(plotdata = ebc_comps,
                   tax.level = i,
                   dendrogram = dendros,
                   fill.by = "phylum",
                   interactive = opt$interactive,
                   out.dr = out.dr,
                   metadata.cols = metadata.cols)
}

Sys.sleep(3)

# parallel::mclapply(X = tax.levels,
#                    FUN = function(i){
#                      bngal::build_taxa.barplot(plotdata = ebc_comps,
#                                                tax.level = i,
#                                                dendrogram = dendros,
#                                                fill.by = "ebc",
#                                                interactive = F,
#                                                out.dr = out.dr,
#                                                metadata.cols = metadata.cols)
#                    },
#                    mc.cores = NCORES)

for (i in tax.levels) {
build_taxa.barplot(plotdata = ebc_comps,
                   tax.level = i,
                   dendrogram = dendros,
                   fill.by = "ebc",
                   interactive = opt$interactive,
                   out.dr = out.dr,
                   metadata.cols = metadata.cols)
}

Sys.sleep(3)

# parallel::mclapply(X = tax.levels,
#                    FUN = function(i){
#                      bngal::build_taxa.barplot(plotdata = ebc_comps,
#                                                tax.level = i,
#                                                dendrogram = dendros,
#                                                fill.by = "grouping",
#                                                interactive = F,
#                                                out.dr = out.dr,
#                                                metadata.cols = metadata.cols)
#                    },
#                    mc.cores = NCORES)

for (i in c("family", "genus", "asv")) {
build_taxa.barplot(plotdata = ebc_comps,
                   tax.level = i,
                   dendrogram = dendros,
                   fill.by = "grouping",
                   interactive = opt$interactive,
                   out.dr = out.dr,
                   metadata.cols = metadata.cols)
}

Sys.sleep(3)