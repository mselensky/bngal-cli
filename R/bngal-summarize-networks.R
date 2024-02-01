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
  optparse::make_option(c("-w", "--network_dir"),
                        help = "(Required) Input network data. Should be parent folder of `bngal-build-nets` output. Output subfolders will write here as well unless --output is specified."),
  optparse::make_option(c("-o", "--output"), default = NULL,
                        help = "Optional output folder. May be useful if one desires to test multiple `-f` inputs on the same network data."),
  optparse::make_option(c("-t", "--taxonomic_level"), default = "asv",
                        help = "Taxonomic level at which to construct co-occurrence networks. Must be at the same level or above the input --asv_table.
                        Can be one of 'phylum', 'class', 'order', 'family', 'genus', or 'asv'
                        * Default = %default"),
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
                        * Default = %default"),
  optparse::make_option(c("-q", "--query"), default = NULL,
                        help = "A query string to construct co-occurrence plots for a specific taxon.
                        Be sure to use the full taxonomic ID as appropriate for the given taxonomic level as noted in the *taxa_spread.csv output in the network-summaries subfolder.
                        Multiple queries may be provided given space characters: 'Archaea;Crenarchaeota Bacteria;Actinobacteriota'
                        * Default = %default"),
  optparse::make_option(c("-s", "--skip_plotting"), default = FALSE,
                        help = "Skip the plotting of taxonomic barplots and EBC composition plots. Useful if you want to test multiple --query inputs on the same data.
                        * Default = %default")
)

opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)

if (is.null(opt$asv_table) | is.null(opt$metadata) | is.null(opt$network_dir)){
  print_help(opt_parser)
  stop("[", Sys.time(), "] At least one required argument is missing. See help above for more information.")
}

# create output directory
# output will write to input folder by default unless --output is defined
if (is.null(opt$output)) {
  out.dr = opt$network_dir
} else {
  out.dr = opt$output
  if (!dir.exists(out.dr)) dir.create(out.dr, recursive = TRUE)
}
logfiles.dir = file.path(out.dr, "logfiles")
if (!dir.exists(logfiles.dir)) dir.create(logfiles.dir, recursive = TRUE)
logfile_name = file.path(logfiles.dir, paste0(opt$taxonomic_level, "-bngal-summarize-networks.log"))
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
colnames(asv_table) <- gsub(" ", "", colnames(asv_table)) # remove spaces
tax_level = opt$taxonomic_level
sub.comm.column=opt$subnetworks
ebc.comp.fill = opt$fill_ebc_by
metadata.cols = ebc.comp.fill
NCORES = opt$cores
query = opt$query

out.dr.core = file.path(out.dr, "ebc-composition-plots")
if (!dir.exists(out.dr.core)) dir.create(out.dr.core, recursive = TRUE)

# load network data from bngal-build-nets
network_data <- bngal::load_network_data(network_dir, tax.level = tax_level)
message(" | [", Sys.time(), "] Network data imported from:\n |   * ", network_dir)

# bin taxonomy at defined level of classification
binned_tax <- bngal::bin_taxonomy(asv.table = asv_table,
                    meta.data = metadata,
                    tax.level = tax_level,
                    remove.singletons = FALSE,
                    compositional = TRUE)

# extract network node data
ebc_nodes <- bngal::extract_node_data(network.data = network_data, tax.level = tax_level)
message(" | [", Sys.time(), "] Node data extracted")

# default will plot the following
if (opt$skip_plotting == FALSE) {
  library(ggpubr)
  library(ggdendro)
  # calculate shannon, simpson, and invsimpson for all levels of tax.
  alpha_diversity <- bngal::get_alpha.div(binned.taxonomy = binned_tax, tax.level = tax_level)
  message(" | [", Sys.time(), "] Alpha diversity calculated")

  # calculate edge between cluster compositions and abundance
  ebc_comps <- bngal::ebc_compositions(ebc.nodes = ebc_nodes,
                                       binned.taxonomy = binned_tax,
                                       alpha.div = alpha_diversity,
                                       tax.level = tax_level,
                                       metadata = metadata,
                                       metadata.cols = ebc.comp.fill,
                                       sub.comms = sub.comm.column)
  message(" | [", Sys.time(), "] EBC compositions calculated")

  out.dr.taxa.bp = file.path(out.dr, "taxa-barplots")
  if (!dir.exists(out.dr.taxa.bp)) dir.create(out.dr.taxa.bp, recursive = TRUE)

  if (!is.null(ebc.comp.fill)) {
    core_comps <- bngal::plot_core_comp(ebc_comps, tax_level, metadata, fill.by = ebc.comp.fill)
    suppressMessages(
      ggplot2::ggsave(file.path(out.dr.core, paste0(tax_level, "-filled.by-", ebc.comp.fill, ".pdf")),
                      core_comps,
                      device = "pdf")
    )
    message(" | [", Sys.time(), "] EBC composition plots exported to\n |   * ", out.dr.core)
  } else {
    message(" | [", Sys.time(), "] No --fill_by_ebc option found; skipping EBC composition plots")
  }

  # output summary data for each level of taxonomic classification
  out <- bngal::export_ebc_taxa_summary(binned.taxonomy = binned_tax,
                                        ebc.nodes.abun = ebc_comps,
                                        tax.level = tax_level,
                                        out.dr = out.dr)
  message(" | [", Sys.time(), "] EBC and taxonomic abundance data exported to\n |   * ", file.path(out.dr, "network-summary-tables"))
  Sys.sleep(1)

  dendros <- bngal::build_dendrograms(binned.taxonomy = binned_tax,
                                      metadata = metadata,
                                      color.by = ebc.comp.fill,
                                      trans = "log10",
                                      sub.comms = sub.comm.column)
  Sys.sleep(1)

  taxa.plots=list()
  for (x in c("phylum", "ebc")) {
    suppressWarnings(
      taxa.plots[[x]] <- bngal::build_taxa.barplot(plotdata = ebc_comps,
                                            tax.level = tax_level,
                                            dendrogram = dendros,
                                            fill.by = x,
                                            interactive = opt$interactive,
                                            out.dr = out.dr,
                                            metadata.cols = metadata.cols)
    )
  }

  if (tax_level %in% c("family", "genus", "asv")) {
    suppressWarnings(
      taxa.plots[[x]] <- bngal::build_taxa.barplot(plotdata = ebc_comps,
                                            tax.level = tax_level,
                                            dendrogram = dendros,
                                            fill.by = "grouping",
                                            interactive = opt$interactive,
                                            out.dr = out.dr,
                                            metadata.cols = metadata.cols)
    )
  }

}

nodes <- ebc_nodes %>%
  filter(tax_level %in% tax_level)
edges <- network_data$edges[[tax_level]]
# return list if not already
# (using nrow to check bc tibbles are technically lists)
if (!is.null(nrow(edges))) {
  edges = list("all" = edges)
}

# primary and secondary connection node summaries
split.nodes <- split(nodes, nodes$sub_comm)
coocc <- parallel::mclapply(names(split.nodes),
                            function(i){
                              bngal::summarize_cooccurrence(nodes. = split.nodes[[i]],
                                                            edges. = edges[[i]],
                                                            tax.level = tax_level)
                              },
                            mc.cores = NCORES)
names(coocc) = names(split.nodes)

# reimport ebc_taxa_summary results
merge_spread_data <- function(i) {
  taxa.spread <- read.csv(file.path(out.dr, "network-summary-tables", tax_level, paste0(i, "_tax_spread.csv")))

  coocc[[i]]$node_summaries %>%
    dplyr::mutate(edge_btwn_cluster = as.numeric(edge_btwn_cluster)) %>%
    left_join(taxa.spread, by = c("taxon_", "edge_btwn_cluster"))

}
taxa_spread <- lapply(names(coocc),
                      merge_spread_data)
names(taxa_spread)=names(coocc)

# ebc legend colors
ebc_legend_colors<- function(split.nodes) {
  ebc.leg.cols <- split.nodes %>%
    distinct(edge_btwn_cluster, edge_btwn_cluster_color) %>%
    filter(edge_btwn_cluster_color != "#000000") %>%
    dplyr::mutate(edge_btwn_cluster = as.character(edge_btwn_cluster))
  ebc.leg.cols <- rbind(ebc.leg.cols, c("edge_btwn_cluster" = "other", "edge_btwn_cluster_color" = "#000000"))
  ebc.colors <- ebc.leg.cols$edge_btwn_cluster_color
  names(ebc.colors) <- as.character(ebc.leg.cols$edge_btwn_cluster)
  ebc.colors
}
# plot connections
plot_xions <- function(taxa_spread, ebc.colors) {
  phylum.color.scheme <- pull(bngal:::phylum_colors_tol, phylum_color, Silva_phylum)

  taxa_spread %>%
    ggplot(aes(median_rel_abun*100, n_obs)) +
    geom_point(aes(fill = as.factor(edge_btwn_cluster),
                   size = total_xions),
               shape = 21,
               alpha = 0.7) +
    scale_fill_manual(values = ebc.colors) +
    guides(size = element_text("Degree")) +
    ylab("Prevalence") +
    xlab("Median relative abundance (%)")

}

ebc.colors <- lapply(split.nodes,
                     ebc_legend_colors)

# prevalence vs. relative abundance, sized by total connections and filled by EBC
if (!dir.exists(file.path(out.dr, "node_prevalence_plots"))) dir.create(file.path(out.dr, "node_prevalence_plots"))
out.plot = list()
for (i in names(taxa_spread)) {
  out.plot[[i]] <- plot_xions(taxa_spread[[i]], ebc.colors[[i]])
  ggsave(file.path(out.dr, "node_prevalence_plots", paste0(i, "-", tax_level, "-node_prevalence.pdf")),
         out.plot[[i]],
         device = "pdf", width = 8.5, height = 11)
}
for (i in names(coocc)) {
  coocc[[i]]$sub_comm = i
}
for (i in names(edges)) {
  edges[[i]]$sub_comm = i
}
joined.edges <- Reduce(rbind, edges) %>%
  dplyr::rename(id = from)
tmp.coocc=list()
for (i in names(coocc)) {
  tmp.coocc$node_summaries[[i]] <- coocc[[i]]$node_summaries %>%
    dplyr::mutate(sub_comm = i)
}

joined.coocc <- Reduce(rbind, tmp.coocc$node_summaries)

# optional: create cross-network co-occurrence plots for each query
if (!is.null(query)) {
  query = stringr::str_split(query, " ")
  query = query[[1]]

edge_deets <- list()
for (i in names(coocc)) {
  edge_deets[[i]] = coocc[[i]]$edge_details
  edge_deets[[i]]$sub_comm = i

}
joined.edge.details <- Reduce(rbind, edge_deets)

build_coocc_plots <- function(query) {
  queried.data <- joined.edge.details %>%
    filter(grepl(query, from_taxon_)) %>%
    select(to_taxon_, contains("to"), spearman, p_value, sub_comm) %>%
    distinct()
  sorted.labels <- sort(queried.data$to_taxon_)

  query.coocc.plot <- queried.data %>%
    ggplot(aes(y = to_taxon_, x = sub_comm)) +
    geom_tile(aes(fill = spearman)) +
    scale_fill_viridis_c(breaks = c(-1,-0.8,-0.6,0.6,0.8,1),
                         limits = c(-1, 1)) +
    theme_bw() +
    ggtitle(paste0(query, " connections")) +
    xlab("Network") +
    theme_bw() +
    theme(axis.title.y = element_blank(),
          axis.text.y = element_text(size = 4),
          legend.position = "bottom",
          legend.text = element_text(angle = 90, vjust = .1,
                                     size = 6))

}
coocc_plots <- mclapply(query,
                        build_coocc_plots)
names(coocc_plots) = query
coocc_plots_out <- gridExtra::marrangeGrob(coocc_plots, nrow=1, ncol=1)

# export full page cross-network co-occurrence plot for each query
ggsave(file.path(out.dr, paste0(tax_level, "_co-occurrence-queries.pdf")),
       coocc_plots_out,
       device = "pdf", width = 8.5, height = 11)

}

phylum.color.scheme = pull(bngal:::phylum_colors_tol, phylum_color, Silva_phylum)

# connectivity summarized by phylum
# joined.coocc %>%
#   group_by(edge_btwn_cluster, sub_comm) %>%
#   dplyr::summarise(ebc_tot = sum(total_xions),
#                    ebc_pos = sum(pos_xions),
#                    ebc_inter = sum(inter_ebc_xions))

xions_plot <- joined.coocc %>%
  group_by(sub_comm) %>%
  dplyr::mutate(sub_comm_xions = sum(total_xions)) %>%
  group_by(phylum, sub_comm) %>%
  dplyr::summarize(phy_pos = sum(pos_xions),
                   phy_tot = sum(total_xions),
                   pos_rel = (phy_pos/phy_tot),
                   sub_comm_xions = sub_comm_xions,
                   n_phy = n()#,
                   #connectivity = (phy_tot/n_phy)
                   ) %>%
  distinct(phylum, sub_comm, .keep_all = TRUE) %>%
  group_by(phylum, sub_comm) %>%
  dplyr::mutate(connectivity = (phy_tot/n_phy),
                connectivity_pos = (phy_pos/n_phy)) %>%
  left_join(select(bngal:::phylum_colors_tol, phylum_order, Silva_phylum),
            by = c("phylum" = "Silva_phylum")) %>%
  ggplot(aes(fill = phylum)) +
  geom_bar(aes(connectivity, reorder(phylum, phylum_order)),
           stat = "identity", alpha = 0.5) +
  geom_bar(aes(connectivity_pos, reorder(phylum, phylum_order)),
           stat = "identity") +
  geom_text(aes(connectivity, reorder(phylum, phylum_order),
               label = n_phy)) +
  facet_wrap(~sub_comm) +
  scale_fill_manual(values = phylum.color.scheme) +
  xlab("connectivity (# edges / # nodes)") +
  theme_bw() +
  theme(legend.position = "none",
        axis.title.y = element_blank()) +
  ggtitle(label = paste0(tax_level, "-level connections summarized by phylum"),
          subtitle = "Darker bars = positive connection. Faded bars = negative connections.\nLabels = number of unique taxa within phylum.")

# export plots and data
if (!dir.exists(file.path(out.dr, "connectivity_plots"))) dir.create(file.path(out.dr, "connectivity_plots"))
ggsave(file.path(out.dr, "connectivity_plots", paste0(tax_level, "_connections_plot.pdf")),
       xions_plot,
       device = "pdf", width = 8.5, height = 11)
write.csv(joined.coocc,
          file = file.path(out.dr, "connectivity_plots", paste0(tax_level, "_connections_data.csv")),
          row.names = FALSE)

message(" | [", Sys.time(), "] Exported summary plots.")
message(" | [", Sys.time(), "] bngal-summarize-nets complete!")
