@isTest
public class UpdateSalesPerformanceLSAHandlerTest {
    @isTest
    static void testUpdateSalesPerformance() {
        
        Id secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Primary_Order' LIMIT 1].Id;
        
        User accountOwner = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        Id distributorRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Distributor' LIMIT 1].Id;

        Account distributorAccount = new Account();
        distributorAccount.RecordTypeId = distributorRecordType;
        distributorAccount.Name = 'Distributor Account';
        distributorAccount.OwnerId = accountOwner.Id;
        insert distributorAccount;
        
        Order__c order = new Order__c();
        order.AccountId__c = distributorAccount.Id;
        order.Total_Order_Value__c = 1000;
        order.RecordTypeId = secondaryInvoiceRT;
        insert order;
        
        order = [SELECT Id,RecordTypeId,AccountId__c,CreatedDate,Total_Order_Value__c FROM Order__c WHERE Id = :order.Id LIMIT 1];
        
        Test.setCreatedDate(order.Id, DateTime.newInstance(2025, 1, 15, 0, 0, 0));
        
        Sales_Target__c salesTarget = new Sales_Target__c();
        salesTarget.OwnerId = accountOwner.Id;
        salesTarget.Assigned_To__c = accountOwner.Id;
        salesTarget.Number_of_Month__c = 1;
        salesTarget.Productive_Calls_Actual__c = 0;
        insert salesTarget;
        
        Test.startTest();
        UpdateSalesPerformanceLSAHandler.updateSalesPerformance(new List<Order__c>{order});
        Test.stopTest();
        
    }
}