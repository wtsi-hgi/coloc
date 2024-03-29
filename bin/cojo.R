# https://yanglab.westlake.edu.cn/software/gcta/#COJO
library(data.table)
requireNamespace('dplyr')

make_cojo_df <- function(df, source = c('gwas', 'eqtl')){
    source <- match.arg(source)
    if (source == 'gwas'){
        df <- dplyr::rename(df, FREQ = eaf)
    }

    if (source == 'eqtl'){
        # we can do this since in eQTL data effect allele is always the minor allele
        df <- dplyr::rename(df, FREQ = MAF)
    }

    Cojo_Dataframe <- dplyr::select(df,
        SNP=variant_id,
        A1=effect_allele,  # the effect allele
        A2=other_allele,   # the other allele
        freq=FREQ,         # frequency of the effect allele
        b=beta,            # effect size
        se=standard_error,
        p=p_value,         # p-value
        N                  # sample size
    )
    Cojo_Dataframe = Cojo_Dataframe[!is.na(Cojo_Dataframe$freq), ]  # <- 0
    Cojo_Dataframe = Cojo_Dataframe[!Cojo_Dataframe$N < 10, ]  # Cojo doesnt like sample sizes smaller than 10
    Cojo_Dataframe = transform(Cojo_Dataframe, freq = as.numeric(freq), N = as.numeric(N), b = as.numeric(b))
    return (Cojo_Dataframe)
}

# a small wrapper for system calls with return code check
run_tool <- function (bin, args){
    
    print(paste(c(bin, args), collapse = ' '))
    logfile <- tempfile()
    rc <- system2(command = bin, args = args, stdout = logfile)
    log <- readLines(logfile)
    file.remove(logfile)
    if(rc != 0){
        cat(paste(log, collapse = '\n'), '\n')
        stop(rc != 0)
    } else{
        cat(paste(tail(log, n = 15), collapse = '\n'), '\n')
    }
}

# call gcta program
run_gcta <- function (bin = NULL, args){
    if (is.null(bin)) bin <- 'gcta'
    run_tool(bin = bin, args = args)
}

# call gcta program in COJO-mode
# bfile -- path plink file with LD reference panel
run_cojo <- function (bin = NULL, bfile, marker_list = NULL, conditional_markers = NULL, summary_stat, pvalue, out_prefix){
    gcta_args <- c(
        '--bfile', bfile,
        '--cojo-p', pvalue,           # p-value to declare a genome-wide significant hit
        '--cojo-file', summary_stat,  # summary-level statistics from a GWAS
        '--maf', '0.01',
        '--out', out_prefix
    )

    if (!is.null(conditional_markers)){
        cond_args <- c('--cojo-cond', conditional_markers)  # analysis conditional on the given list of SNPs
    } else {
        cond_args <- '--cojo-slct'  # select independently associated SNPs
    }
    gcta_args <- append(gcta_args, cond_args)

    if (!is.null(marker_list)){
        gcta_args <- append(gcta_args,
            c('--extract', marker_list)  # limit the COJO analysis in a certain genomic region
        )
    }

    run_gcta(bin = bin, args = gcta_args)

    out <- list(
        independent_signals = paste0(out_prefix, ".jma.cojo"),
        conditional_analysis = paste0(out_prefix, ".cma.cojo")
    )
    return(out)
}

run_cojo_on_locus <- function (gcta_bin = NULL, plink2_bin = NULL,
                               bfile, chrom, start, end, pvalue,
                               conditional_markers = NULL, summary_stat, out_prefix){

    cojo_filename <- paste0(variant_id, '_', GWAS_name, "_sum.txt")
    fwrite(summary_stat, file = cojo_filename, row.names = F, quote = F, sep = "\t")

    locus_filename <- paste(basename(bfile), chrom, start, end, sep = '-')
    extract_locus(
        bin = plink2_bin,
        genotypes_prefix = bfile,
        chrom = chrom, start = start, end = end,
        out_prefix = locus_filename
    )

    cojo <- run_cojo(
        bin = gcta_bin,
        bfile = locus_filename,
        summary_stat = cojo_filename,
        pvalue = pvalue,
        conditional_markers = conditional_markers,
        out_prefix = out_prefix
    )
    return(cojo)
}

# call plink program
run_plink <- function (bin = NULL, args){
    if (is.null(bin)) bin <- 'plink'
    run_tool(bin = bin, args = args)
}

# call plink2 program
run_plink2 <- function (bin = NULL, args){
    if (is.null(bin)) bin <- 'plink2'
    run_tool(bin = bin, args = args)
}

# extracts genomic interval from bfile using plink2
extract_locus <- function (bin = NULL, genotypes_prefix, chrom, start, end, filters = NULL, out_prefix){
    range_filename <- tempfile(tmpdir = '.', fileext = '.txt')
    df <- data.table(chrom = chrom, start = start, end = end, label = 'locus')
    fwrite(df, range_filename, sep = '\t', col.names = F, scipen = 1e9L)

    plink_args <- c(
        '--bfile', genotypes_prefix,
        '--extract', 'bed1', range_filename,
        '--make-bed',
        filters,
        '--out', out_prefix
    )

    run_plink2(bin = bin, args = plink_args)
    file.remove(range_filename)
    # ensure the same names are used in the bim file othervise the cojo vill fail
    bim_file <- fread(paste0(out_prefix, '.bim'))
    # bim_file$chr_pos = paste0(bim_file$V1,'-',bim_file$V4)


    if (sum(str_detect(bim_file$V2, ':')) > 0){
        # This part checks for the ids that needs to be converted and convers them to rsids where available.
        # quite often there are no rsids associated. 
        # For this we could consider converting GWAS loci to chr positons.
        to_fix = bim_file[str_detect(bim_file$V2, ':')]
        replacement_snp_ids = convert_chr_positions_to_rsids(to_fix$V2)
        bim_file[str_detect(bim_file$V2, ':')]$V2=replacement_snp_ids$rsid
    }

    # marker.data <- read_eqtl_marker_file(eqtl_marker_file)
    # marker.data$chr_pos = paste0(marker.data$chromosome,'-',marker.data$base_pair_location)
    # d <- merge(bim_file, marker.data[c("SNP", "chr_pos")], by = "chr_pos", all.x = T)
    # d$V2 = d$SNP
    d2 = bim_file
    # d2[is.na(d2)] <- '.'
    fwrite(d2, file = paste0(out_prefix, '.bim'), row.names = F,col.names = F, quote = F, sep = "\t")

    return(out_prefix)
}

get_ld_matrix <- function (plink_bin = NULL, genotypes_prefix, markers, out_prefix){
    marker_filename <- tempfile(tmpdir = '.', fileext = '.txt')
    writeLines(markers, marker_filename)

    if(missing(out_prefix)){
        out_prefix <- paste(genotypes_prefix, 'r', sep = '-')
    }

    plink_args <- c(
        '--bfile', genotypes_prefix,
        '--extract', marker_filename,
        '--r', 'square', 'gz',
        '--make-just-bim',
        '--out', out_prefix
    )
    run_plink(bin = plink_bin, args = plink_args)
    file.remove(marker_filename)

    ld_filename <- paste0(out_prefix, '.ld.gz')
    bim_filename <- paste0(out_prefix, '.bim')

    m <- as.matrix(fread(ld_filename))
    cols <- unlist(fread(bim_filename, select = 2))

    colnames(m) <- cols
    rownames(m) <- cols

    return(m)
}

get_plink_freq <- function (plink2_bin, genotypes_prefix, out_prefix){
    if(missing(out_prefix)) out_prefix <- tempfile(tmpdir = '.')
    plink_args <- c(
      '--bfile', genotypes_prefix,
      '--freq',
      '--out', out_prefix
    )
    run_plink2(bin = plink2_bin, args = plink_args)

    freq_filename <- paste0(out_prefix, '.afreq')
    freq <- fread(freq_filename)
    return(freq)
}

combine_cojo_results <- function (independent_signals, conditional_signals, lead_snp){
    conditioned_dataset <- fread(conditional_signals)
    conditioned_dataset_condSNP <- fread(independent_signals)

    conditioned_dataset_condSNP <- conditioned_dataset_condSNP[conditioned_dataset_condSNP$SNP == lead_snp]
    conditioned_dataset_condSNP <- conditioned_dataset_condSNP[, !c("LD_r","pJ","bJ","bJ_se")]
    conditioned_dataset_condSNP <- dplyr::mutate(conditioned_dataset_condSNP,
        pC = p, bC = b, bC_se = se
    )

    dataset <- rbind(conditioned_dataset, conditioned_dataset_condSNP)
    return(dataset)
}

prepare_coloc_table <- function (df){
    rules <- c(
        snp = 'variant_id', chr = 'chromosome', position = 'base_pair_location',
        varbeta = 'standard_error', pvalues = 'p_value', 'beta', MAF = 'eaf', 'N',
        snp = 'SNP', chr = 'Chr', position = 'bp',
        beta = 'bC', varbeta = 'bC_se', pvalues = 'pC', MAF = 'freq', 'MAF'
    )
    names <- intersect(rules, colnames(df))
    rename_rules <- rules[rules %in% names]
    D1 <- dplyr::select(df, !!rename_rules)
    D1$varbeta = D1$varbeta^2
    D1 = na.omit(D1)
    return(D1)
}

prepare_coloc_list <- function (coloc_df, N, type = c('quant', 'cc')){
    require(dplyr)
    type <- match.arg(type)
    coloc_df <- coloc_df %>% add_count(snp) %>% filter(n == 1) %>% select(-n)  # remove duplicated snps
    l <- as.list(coloc_df)
    l$type <- type
    l$N <- N
    if(type == 'cc') l$pvalues <- NULL  # otherwise coloc will ignore betas
    return(l)
}
