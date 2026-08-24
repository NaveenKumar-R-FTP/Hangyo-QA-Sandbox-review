trigger InvoiceSharingTrigger on Invoice__c (after insert, after update) {
    Set<Id> accountIds = new Set<Id>();

    // Collect all Account Ids from Under_SS__c lookup field
    for (Invoice__c invoice : Trigger.new) {
        if (invoice.Under_SS__c != null) {
            accountIds.add(invoice.Under_SS__c);
        }
    }

    if (!accountIds.isEmpty()) {
        // Fetch all Partner Users related to these accounts
        List<User> partnerUsers = [
            SELECT Id FROM User 
            WHERE AccountId IN :accountIds AND IsPartner = TRUE
        ];

        if (!partnerUsers.isEmpty()) {
            List<Invoice__Share> invoiceShares = new List<Invoice__Share>();

            // Iterate over invoices and create sharing records
            for (Invoice__c invoice : Trigger.new) {
                if (invoice.Under_SS__c != null) {
                    for (User user : partnerUsers) {
                        Invoice__Share invoiceShare = new Invoice__Share();
                        invoiceShare.ParentId = invoice.Id;
                        invoiceShare.UserOrGroupId = user.Id;
                        invoiceShare.AccessLevel = 'Read'; // Change to 'Edit' if needed
                        invoiceShare.RowCause = Schema.Invoice__Share.RowCause.Manual;
                        invoiceShares.add(invoiceShare);
                    }
                }
            }

            // Insert all sharing records
            if (!invoiceShares.isEmpty()) {
                insert invoiceShares;
            }
        }
    }
}