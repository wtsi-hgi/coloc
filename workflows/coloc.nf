/*
========================================================================================
    VALIDATE INPUTS
========================================================================================
*/

// def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// // Validate input parameters
// WorkflowColoc.initialise(params, log)

// // TODO nf-core: Add all file path parameters for the pipeline to the list below
// // Check input path parameters to see if they exist
// def checkPathParamList = [ params.input, params.multiqc_config, params.fasta ]
// for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
// if (params.input) { ch_input = file(params.input) } else { exit 1, 'Input samplesheet not specified!' }

/*
========================================================================================
    CONFIG FILES
========================================================================================
*/

// ch_multiqc_config        = file("$projectDir/assets/multiqc_config.yaml", checkIfExists: true)
// ch_multiqc_custom_config = params.multiqc_config ? Channel.fromPath(params.multiqc_config) : Channel.empty()

/*
========================================================================================
    IMPORT LOCAL MODULES/SUBWORKFLOWS
========================================================================================
*/

include { COLOC_FREQ_AND_SNPS } from "$projectDir/modules/nf-core/modules/coloc_frq/main"
// include { GWAS_FREQ } from '../modules/nf-core/modules/coloc_frq/main'
include { COLOC_ON_SIG_VARIANTS } from "$projectDir/modules/nf-core/modules/coloc_sig_variants/main"
include { eCAVIAR } from "$projectDir/modules/nf-core/modules/eCaviar/main"
include { SMR_HEIDI } from "$projectDir/modules/nf-core/modules/smr_heidi/main"
/*
========================================================================================
    RUN MAIN WORKFLOW
========================================================================================
*/

// Info required for completion email and summary
def multiqc_report = []
workflow COLOC {

    // read lists of GWAS and eQTL statistics fofns
    gwas_list = Channel
        .fromPath(params.gwas_list, followLinks: true, checkIfExists: true)
        .splitText()

    eqtl_fofn = Channel
        .fromPath(params.eqtl_list, followLinks: true, checkIfExists: true)
        .splitText( by: 10, file: true )

    eqtl_snps = Channel
        .fromPath(params.eqtl_snps, followLinks: true, checkIfExists: true)

    plink_files = Channel
        .fromFilePairs("${params.bfile}.{bed,bim,fam}", checkIfExists: true, size: 3)

    // Calculate frequencies and extract number of significant GWAS hits for each input GWAS sum stats.
    COLOC_FREQ_AND_SNPS(gwas_list, eqtl_fofn, eqtl_snps, params.rsid_mappings_file, "${params.rsid_mappings_file}.csi")

    // Then for each of the GWAS independent SNPs and each of the corresponding eQTLs we generate a new job - we can split this up later on even more.
    COLOC_FREQ_AND_SNPS.out.sig_signals_eqtls
        .splitCsv(header: true, sep: '\t', by: 1)
        .map { row -> row.gwas_name2.split("--") }
        .map { it -> [it[0], it[1], it[2]] }
        .set { variant_id }

    // Have to run this on each of the eQTL files separately.
    COLOC_ON_SIG_VARIANTS(
        variant_id.combine(plink_files),eqtl_snps,params.rsid_mappings_file, "${params.rsid_mappings_file}.csi"
    )
    // variant_id.view()
    // variant_id
    //   .subscribe onNext: {println "variant_id: $it"},
    //   onComplete: {println "variant_id: done"}
    eCAVIAR(variant_id.combine(plink_files))
    SMR_HEIDI(variant_id.combine(plink_files))
}

/*
========================================================================================
    COMPLETION EMAIL AND SUMMARY
========================================================================================
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    }
    NfcoreTemplate.summary(workflow, params, log)
}

/*
========================================================================================
    THE END
========================================================================================
*/
