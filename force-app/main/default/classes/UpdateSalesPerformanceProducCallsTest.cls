@isTest
public class UpdateSalesPerformanceProducCallsTest {
    @isTest
    static void testUpdateSalesPerformance() {
        
        Id secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Secondary_Order' LIMIT 1].Id;
        
        User accountOwner = [SELECT Id, UserRoleId FROM User WHERE IsActive = TRUE AND UserRoleId != null LIMIT 1];
        
        Id retailerRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Retailer' LIMIT 1].Id;
        
        Account retailerAccount = new Account();
        retailerAccount.RecordTypeId = retailerRecordType;
        retailerAccount.Name = 'Retailer Account';
        retailerAccount.OwnerId = accountOwner.Id;
        insert retailerAccount;
        
        Sales_Target__c salesTarget = new Sales_Target__c();
        salesTarget.OwnerId = accountOwner.Id;
        salesTarget.Assigned_To__c = accountOwner.Id;
        salesTarget.Number_of_Month__c = Date.today().month();
        salesTarget.Productive_Calls_Actual__c = 0;
        salesTarget.New_Outlet_Opened_Actual__c = 0;
        insert salesTarget;
        
        TriggerExecutionController__c tt = new TriggerExecutionController__c();
        tt.Name = 'OrderTrigger';
        tt.Is_Active__c = true;
        insert tt;
        
        Order__c order = new Order__c();
        order.Account__c = retailerAccount.Id;
        order.Total_Order_Value__c = 10000;
        order.RecordTypeId = secondaryInvoiceRT;
        insert order;
        
        
        order = [SELECT Id,RecordTypeId,Account__c,CreatedDate,Total_Order_Value__c FROM Order__c WHERE Id = :order.Id LIMIT 1];
        
        Test.setCreatedDate(order.Id, DateTime.newInstance(2025, 7, 10, 0, 0, 0));
        
        Test.startTest();
        UpdateSalesPerformanceProducCallsActual.updateSalesPerformance(new List<Order__c>{order});
        Test.stopTest();
        
    }
    
    @isTest
    static void testOrderUnDelete() {
        
        Id secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Secondary_Order' LIMIT 1].Id;
        
        User accountOwner = [SELECT Id, UserRoleId FROM User WHERE IsActive = TRUE AND UserRoleId != null LIMIT 1];
        
        Id retailerRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Retailer' LIMIT 1].Id;
        
        Account retailerAccount = new Account();
        retailerAccount.RecordTypeId = retailerRecordType;
        retailerAccount.Name = 'Retailer Account';
        retailerAccount.OwnerId = accountOwner.Id;
        insert retailerAccount;
        
        Sales_Target__c salesTarget = new Sales_Target__c();
        salesTarget.OwnerId = accountOwner.Id;
        salesTarget.Assigned_To__c = accountOwner.Id;
        salesTarget.Number_of_Month__c = Date.today().month();
        salesTarget.Productive_Calls_Actual__c = 0;
        salesTarget.New_Outlet_Opened_Actual__c = 0;
        insert salesTarget;
        
        TriggerExecutionController__c tt = new TriggerExecutionController__c();
        tt.Name = 'OrderTrigger';
        tt.Is_Active__c = true;
        insert tt;
        
        Order__c order = new Order__c();
        order.Account__c = retailerAccount.Id;
        order.Total_Order_Value__c = 10000;
        order.RecordTypeId = secondaryInvoiceRT;
        insert order;
        
        
        order = [SELECT Id,RecordTypeId,Account__c,CreatedDate,Total_Order_Value__c FROM Order__c WHERE Id = :order.Id LIMIT 1];
        
        Test.setCreatedDate(order.Id, DateTime.newInstance(2025, 7, 10, 0, 0, 0));        
        
        List<Order__c> orders = [SELECT Id, Status__c FROM Order__c Limit 1];
        
        for (Order__c ord : orders) {
            ord.Status__c = 'Order Placed';
        }
        
        delete orders;
        
        Test.startTest();
        Undelete orders;
        Test.stopTest();
        
    }
}