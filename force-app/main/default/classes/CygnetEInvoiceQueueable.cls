// Added by Hari - TDD : Async E-Invoice flow – Button → Queueable → Auth → save → store referenceId → poll → update Invoice
public with sharing class CygnetEInvoiceQueueable implements Queueable, Database.AllowsCallouts {
    private final Id invoiceId;

    public CygnetEInvoiceQueueable(Id invoiceId) {
        this.invoiceId = invoiceId;
    }

    public void execute(QueueableContext ctx) {
        String requestBody = null;
        try {
            // Added by hari for Http Testing - trace queueable execution start
            System.debug('CEQ STEP 1 (Http Testing): start, invoiceId=' + invoiceId);

            requestBody = InvoiceToCygnetMapper.buildEInvoiceSaveBody(invoiceId);
            // Added by hari for Http Testing - confirm mapper completed and log payload size (not full body)
            Integer bodyLen = (requestBody == null) ? 0 : requestBody.length();
            System.debug('CEQ STEP 2 (Http Testing): after buildEInvoiceSaveBody, body length=' + bodyLen);

            // Added by hari (Under SS) - Cygnet credentials from Cygnet_Integration_Setting_Under_SS__c when record type is Secondary_Invoice_Under_SS
            String referenceId = CygnetApiService.saveEInvoice(requestBody, invoiceId);
            // Added by hari for Http Testing - confirm saveEInvoice returned a referenceId
            System.debug('CEQ STEP 3 (Http Testing): after saveEInvoice, referenceId=' + referenceId);

            CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone(referenceId, invoiceId);
            // Added by hari for Http Testing - log StatusResult summary
            System.debug('CEQ STEP 4 (Http Testing): after pollUntilDone, success='
                + (sr == null ? null : sr.success) + ', irn=' + (sr == null ? null : sr.irn));
            if (sr != null && sr.success == true) {
                // Under SS safety: if Cygnet says success but IRN is missing, surface error instead of silently clearing the reference.
                Boolean isUnderSs = false;
                try {
                    Invoice__c inv = [
                        SELECT RecordType.DeveloperName
                        FROM Invoice__c
                        WHERE Id = :invoiceId
                        LIMIT 1
                    ];
                    if (inv.RecordType != null && inv.RecordType.DeveloperName != null) {
                        // Use contains() to avoid brittle matches if DeveloperName differs slightly.
                        isUnderSs = inv.RecordType.DeveloperName.toLowerCase()
                            .contains('secondary_invoice_under_ss');
                    }
                } catch (Exception e) { }

                if (isUnderSs && String.isBlank(sr.irn)) {
                    String msg = 'Cygnet returned success but IRN is missing in the status response.';
                    CygnetIntegrationLogService.logFailure(
                        invoiceId,
                        msg,
                        requestBody,
                        sr != null ? JSON.serialize(sr) : null,
                        'E-Invoice Queueable'
                    );
                    SObject invErr = new Invoice__c(Id = invoiceId);
                    // Keep reference id for troubleshooting/retry
                    invErr.put('Cygnet_Reference_Id__c', referenceId);
                    update invErr;
                    return;
                }

                InvoiceEInvoiceController.processEInvoiceResult(invoiceId, sr);
                if (!isUnderSs || !String.isBlank(sr.irn)) {
                    SObject invClear = new Invoice__c(Id = invoiceId);
                    invClear.put('Cygnet_Reference_Id__c', null);
                    update invClear;
                }
            } else {
                String err = (sr != null && sr.errorMessage != null) ? sr.errorMessage : 'E-Invoice generation failed.';
                try {
                    CygnetIntegrationLogService.logFailure(
                        invoiceId,
                        err,
                        requestBody,
                        sr != null ? JSON.serialize(sr) : null,
                        'E-Invoice Queueable'
                    );
                    SObject invErr = new Invoice__c(Id = invoiceId);
                    invErr.put('Cygnet_Reference_Id__c', referenceId);
                    update invErr;

                    // Added by hari for Http Testing - log non-success StatusResult
                    System.debug('CEQ ERROR (Http Testing): non-success StatusResult for invoiceId='
                        + invoiceId + ', referenceId=' + referenceId + ', error=' + err);
                } catch (Exception e) { }
            }
        } catch (Exception e) {
            try {
                // Added by hari for Http Testing - surface exception details in debug log
                System.debug('CEQ FATAL (Http Testing): ' + e.getMessage());
                System.debug('CEQ FATAL STACK (Http Testing): ' + e.getStackTraceString());

                String err = e.getMessage();
                if (String.isBlank(err)) err = e.getTypeName();
                String st = e.getStackTraceString();
                if (String.isNotBlank(st)) {
                    Integer nl = st.indexOf('\n');
                    String firstLine = nl > -1 ? st.substring(0, nl) : st;
                    err = err + ' @ ' + firstLine;
                }
                CygnetIntegrationLogService.logFailure(
                    invoiceId,
                    err,
                    requestBody,
                    null,
                    'E-Invoice Queueable'
                );
                SObject invEx = new Invoice__c(Id = invoiceId);
                invEx.put('Cygnet_Reference_Id__c', null);
                update invEx;
            } catch (Exception ex) { }
        }
    }
}