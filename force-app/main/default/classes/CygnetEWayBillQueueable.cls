// Added by Hari - TDD : Async E-Way Bill flow – Button → Queueable → save by IRN → poll → update Invoice
public with sharing class CygnetEWayBillQueueable implements Queueable, Database.AllowsCallouts {
    private final Id invoiceId;

    public CygnetEWayBillQueueable(Id invoiceId) {
        this.invoiceId = invoiceId;
    }

    public void execute(QueueableContext ctx) {
        String requestBody = null;
        try {
            requestBody = InvoiceToCygnetMapper.buildEwayBillByIrnBody(invoiceId);
            // Added by hari (Under SS) - same Cygnet profile as E-Invoice for this invoice record type
            String referenceId = CygnetApiService.saveEwayBillByIrn(requestBody, invoiceId);
            CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone(referenceId, invoiceId);
            if (sr.success) {
                InvoiceEInvoiceController.processEWayBillResult(invoiceId, sr);
                SObject invClear = new Invoice__c(Id = invoiceId);
                invClear.put('Cygnet_Reference_Id__c', null);
                update invClear;
            } else {
                String err = sr.errorMessage != null ? sr.errorMessage : 'E-Way Bill generation failed.';
                try {
                    CygnetIntegrationLogService.logFailure(
                        invoiceId,
                        err,
                        requestBody,
                        JSON.serialize(sr),
                        'E-Way Bill Queueable'
                    );
                    SObject invErr = new Invoice__c(Id = invoiceId);
                    invErr.put('Cygnet_Reference_Id__c', referenceId);
                    update invErr;
                } catch (Exception e) { }
            }
        } catch (Exception e) {
            try {
                CygnetIntegrationLogService.logFailure(
                    invoiceId,
                    e.getMessage(),
                    requestBody,
                    null,
                    'E-Way Bill Queueable'
                );
                SObject invEx = new Invoice__c(Id = invoiceId);
                invEx.put('Cygnet_Reference_Id__c', null);
                update invEx;
            } catch (Exception ex) { }
        }
    }
}