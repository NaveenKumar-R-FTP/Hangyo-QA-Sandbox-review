@isTest
public class UpdateSalesPerformanceTDFThroughTest {
    @isTest
    static void testUpdateSalesPerformance() {
        
        Id secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Invoice__c' AND DeveloperName = 'Secondary_Invoice' LIMIT 1].Id;

        User accountOwner = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];

        Id retailerRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Retailer' LIMIT 1].Id;

        Account retailerAccount = new Account();
        retailerAccount.RecordTypeId = retailerRecordType;
        retailerAccount.Name = 'Retailer Account';
        retailerAccount.OwnerId = accountOwner.Id;
        insert retailerAccount;

        Invoice__c invoice = new Invoice__c();
        invoice.Name = 'Invoice 1';
        invoice.Retailer_Account__c = retailerAccount.Id;
        invoice.Invoice_Amount__c = 5000;
        invoice.RecordTypeId = secondaryInvoiceRT;
        invoice.Status__c = 'Confirmed';
        insert invoice;
        
        Invoice_Line_Item__c invlit = new Invoice_Line_Item__c();
        invlit.Quantity__c = 5;
        invlit.Price__c = 15;
        invlit.Total_Amount__c = 300;
        invlit.Invoice__c = invoice.id;
        insert invlit;
        
        Asset__c ass = new Asset__c();
        ass.Retailer_Account__c = retailerAccount.id;
        ass.Status__c = 'Purchased';
        ass.Asset_Code__c = '123';
        insert ass;
        
        
        invoice = [SELECT Id,Name,RecordTypeId,CreatedDate,Invoice_Amount__c,Retailer_Account__c FROM Invoice__c WHERE Id = :invoice.Id LIMIT 1];

        Test.setCreatedDate(invoice.Id, DateTime.newInstance(2025, 1, 15, 0, 0, 0));

        Sales_Target__c salesTarget = new Sales_Target__c();
        salesTarget.OwnerId = accountOwner.Id;
        salesTarget.Assigned_To__c = accountOwner.Id;
        salesTarget.Number_of_Month__c = 1;
        salesTarget.Secondary_Sales_Actual__c = null;
        insert salesTarget;
        
        Test.startTest();
        UpdateSalesPerformanceTDFThroughHandler.updateSalesPerformance(new List<Invoice__c>{invoice});
        Test.stopTest();
        
    }
}