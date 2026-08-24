@isTest
private class InvoiceTriggerReimbursementTest {

    @testSetup
    static void setupRetailerCodeSetting() {
        List<RetailerCodeSetting__c> existing = [SELECT Id FROM RetailerCodeSetting__c WHERE Name = 'SF' LIMIT 1];
        if (existing.isEmpty()) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        }
    }

    @isTest
    static void testDraftToConfirmed_DeductsReimbursementBalanceViaTrigger() {
        Account distributorAcc = new Account(Name = 'Test Distributor TriggerTest');
        insert distributorAcc;

        Id retailerRTId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailerAcc = new Account(
            Name              = 'Test Retailer TriggerTest',
            RecordTypeId      = retailerRTId,
            Primary_State__c  = 'Karnataka'
        );
        insert retailerAcc;

        Reimbursement_Scheme_Definition__c def = new Reimbursement_Scheme_Definition__c(
            Name          = 'Test Scheme TriggerTest',
            Start_Date__c = System.today().addDays(-1),
            End_Date__c   = System.today().addDays(10)
        );
        insert def;

        Retailer_Reimbursement_Scheme__c alloc = new Retailer_Reimbursement_Scheme__c(
            Account__c           = retailerAcc.Id,
            Scheme_Definition__c = def.Id,
            Balance__c            = 1000
        );
        insert alloc;

        // ── ADDED: a real Product + Inventory row, so the trigger's
        // inventory-validation block (before-update) actually has a matching
        // row to find instead of immediately hitting "no matching inventory".
        Product__c prod = new Product__c(Name = 'Test Product TriggerTest');
        insert prod;

        Inventory__c inv2 = new Inventory__c(
            Product__c              = prod.Id,
            Distributor_Name__c     = distributorAcc.Id,
            Quantity_in_hand__c     = 100
        );
        insert inv2;

        // ── ADDED: a real Order + Order Line Item, so the trigger's
        // after-insert/update order-status rollup block actually has an
        // orderId to work with instead of returning immediately.
        Id secondaryOrderRT = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Secondary_Order').getRecordTypeId();
        Order__c ord = new Order__c(
            Account__c    = retailerAcc.Id,
            AccountId__c  = distributorAcc.Id,
            RecordTypeId  = secondaryOrderRT
        );
        insert ord;

        insert new Order_Line_Item__c(
            Order__c            = ord.Id,
            Products__c          = prod.Id,
            Ordered_Quantity__c = 10
        );

        Id secondaryInvoiceRT = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice').getRecordTypeId();
        Invoice__c inv = new Invoice__c(
            Name                   = 'TEST-INV-TRIGGERTEST',
            Distributor_Account__c = distributorAcc.Id,
            Retailer_Account__c    = retailerAcc.Id,
            Order__c               = ord.Id,
            RecordTypeId           = secondaryInvoiceRT,
            Status__c              = 'Draft',
            Invoice_Date__c        = System.today()
        );
        insert inv;

        insert new Invoice_Line_Item__c(
            Invoice__c   = inv.Id,
            Product__c   = prod.Id,
            Quantity__c  = 10
        );

        insert new Invoice_Reimbursement_Line__c(
            Invoice__c                       = inv.Id,
            Retailer_Reimbursement_Scheme__c = alloc.Id,
            Amount_Applied__c                = 400
        );

        Test.startTest();
        // Real DML update — this genuinely fires InvoiceTrigger, unlike calling
        // the service method directly. This is what gives real coverage of the
        // applyLinesOnConfirm() hook added inside the trigger body, as well as
        // the inventory-validation and order-status-rollup blocks that now have
        // real matching data to traverse instead of returning immediately.
        inv.Status__c = 'Confirmed';
        update inv;
        Test.stopTest();

        Retailer_Reimbursement_Scheme__c updatedAlloc = [
            SELECT Balance__c FROM Retailer_Reimbursement_Scheme__c WHERE Id = :alloc.Id
        ];
        System.assertEquals(600, updatedAlloc.Balance__c, 'Balance should be reduced by exactly the applied amount via the real trigger firing');
    }
}