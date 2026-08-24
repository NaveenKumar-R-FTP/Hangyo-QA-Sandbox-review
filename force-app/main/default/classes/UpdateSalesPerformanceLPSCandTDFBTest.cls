@isTest
public class UpdateSalesPerformanceLPSCandTDFBTest {
    
    @testSetup
    static void setupTestData() {
        // Fetch existing user with role
        User existingUser = [SELECT Id, UserRoleId FROM User WHERE IsActive = TRUE AND UserRoleId != null LIMIT 1];
        
        // Record Types
        Id retailerRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Retailer' LIMIT 1].Id;
        Id invoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Invoice__c' AND DeveloperName = 'Secondary_Invoice' LIMIT 1].Id;
        
        // Create Retailer Account
        Account retailer = new Account(
            Name = 'Retailer Test Base',
            OwnerId = existingUser.Id,
            RecordTypeId = retailerRT
        );
        insert retailer;
        
        // Asset record
        Asset__c asset = new Asset__c(
            Retailer_Account__c = retailer.Id,
            Asset_Code__c = 'AS123',
            Status__c = 'Purchased'
        );
        insert asset;
        
        // Sales Target with unique identifier
        Sales_Target__c st = new Sales_Target__c(
            OwnerId = existingUser.Id,
            Assigned_To__c = existingUser.Id,
            Number_of_Month__c = Date.today().month(),
            //Name = 'SalesTarget_' + System.currentTimeMillis(), // Ensure uniqueness
            Secondary_Sales_Actual__c = 0,
            LPSC_total_orders_of_bills_Actual__c = 0,
            Total_DF_Billed_Actual__c = 0,
            X20Rs_N_MRP_Sales_Actual__c = 0,
            Total_DF_Throughput_Actual__c = 0
        );
        insert st;
        
        // Trigger Control (insert only once)
        TriggerExecutionController__c tt = new TriggerExecutionController__c();
        tt.Name = 'InvoiceTrigger';
        tt.Is_Active__c = true;
        insert tt;
        
        // Base Invoice
        Invoice__c inv = new Invoice__c(
            Name = 'Test Invoice Base',
            Status__c = 'Confirmed',
            Invoice_Amount__c = 5000,
            Retailer_Account__c = retailer.Id,
            RecordTypeId = invoiceRT
        );
        insert inv;
        
        // Set specific created date
        Test.setCreatedDate(inv.Id, DateTime.newInstance(2025, 7, 10, 0, 0, 0));
    }
    
    @isTest
    static void testUpdateSalesPerformance() {
        // Fetch base invoice
        Invoice__c inv = [SELECT Id, CreatedDate, Retailer_Account__c FROM Invoice__c LIMIT 1];
        
        Test.startTest();
        UpdateSalesPerformanceLPSCandTDFBHandler.updateSalesPerformance(new List<Invoice__c>{ inv });
        Test.stopTest();
        
    }
    
    @isTest
    static void testInvoiceDeliveredUpdate() {
        
        List<Invoice__c> invoices = [SELECT Id, Status__c FROM Invoice__c LIMIT 1];
        
        for (Invoice__c inv : invoices) {
            inv.Status__c = 'Delivered';
        }
        
        Test.startTest();
        update invoices;
        Test.stopTest();
        
    }
    
    /*@isTest
    static void testInvoiceDeliveredDelete() {
        List<Invoice__c> invoices = [SELECT Id, Status__c FROM Invoice__c LIMIT 1];
        
        Test.startTest();
        delete invoices;
        Test.stopTest();
        
    }*/
}