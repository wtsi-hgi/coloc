#!/usr/bin/env nextflow
/*
========================================================================================
    nf-core/coloc
========================================================================================
    Github : https://github.com/nf-core/coloc
    Website: https://nf-co.re/coloc
    Slack  : https://nfcore.slack.com/channels/coloc
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

/*
========================================================================================
    GENOME PARAMETER VALUES
========================================================================================
*/



/*
========================================================================================
    VALIDATE & PRINT PARAMETER SUMMARY
========================================================================================
*/



/*
========================================================================================
    NAMED WORKFLOW FOR PIPELINE
========================================================================================
*/

include { COLOC } from './workflows/coloc'

//
// WORKFLOW: Run main nf-core/coloc analysis pipeline
//
workflow NFCORE_COLOC {
    COLOC ()
}

/*
========================================================================================
    RUN ALL WORKFLOWS
========================================================================================
*/

//
// WORKFLOW: Execute a single named workflow for the pipeline
// See: https://github.com/nf-core/rnaseq/issues/619
//
workflow {
    NFCORE_COLOC ()
}

/*
========================================================================================
    THE END
========================================================================================
*/
