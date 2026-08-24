@isTest
public class UpdateSalesPerformancePSAHandlerTest {
    @isTest
    static void testUpdateSalesPerformance() {
        
        Id secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Primary_Order' LIMIT 1].Id;
        
        User accountOwner = [SELECT Id, UserRoleId FROM User WHERE IsActive = TRUE AND UserRoleId != null LIMIT 1];
        
        Id distributorRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Distributor' LIMIT 1].Id;
        
        Account distributorAccount = new Account();
        distributorAccount.RecordTypeId = distributorRecordType;
        distributorAccount.Name = 'Distributor Account';
        distributorAccount.OwnerId = accountOwner.Id;
        insert distributorAccount;
        
        Test.setCreatedDate(distributorAccount.Id, DateTime.newInstance(2025, 7, 10, 0, 0, 0));
        
        Sales_Target__c salesTarget = new Sales_Target__c();
        salesTarget.OwnerId = accountOwner.Id;
        salesTarget.Assigned_To__c = accountOwner.Id;
        salesTarget.Number_of_Month__c = Date.today().month();
        salesTarget.Primary_Sales_Actual__c = 0;
        salesTarget.Litre_Sold_Actual__c = 0;
        salesTarget.New_Outlet_Opened_Actual__c = 0;
        insert salesTarget;
        
        Test.setCreatedDate(salesTarget.Id, DateTime.newInstance(2025, 7, 10, 0, 0, 0));
        
        TriggerExecutionController__c tt = new TriggerExecutionController__c();
        tt.Name = 'OrderTrigger';
        tt.Is_Active__c = true;
        insert tt;
        
         Order__c order = new Order__c();
        order.AccountId__c = distributorAccount.Id;
        order.Total_Order_Value__c = 10000;
        order.RecordTypeId = secondaryInvoiceRT;
        order.Status__c = 'Order Placed';
        insert order;
        
        order = [SELECT Id,RecordTypeId,AccountId__c,CreatedDate,Total_Order_Value__c FROM Order__c WHERE Id = :order.Id LIMIT 1];
        
        Test.setCreatedDate(order.Id, DateTime.newInstance(2025, 7, 10, 0, 0, 0));
        
       // Test.startTest();
        UpdateSalesPerformancePSAHandler.updateSalesPerformance(new List<Order__c>{order});
        //Test.stopTest();
        
    }
    
    @isTest
    static void testNoMatchingSalesTarget() {
        Id secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Primary_Order' LIMIT 1].Id;
        
        User accountOwner = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
        
        Id distributorRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Distributor' LIMIT 1].Id;
        
        Account distributorAccount = new Account();
        distributorAccount.RecordTypeId = distributorRecordType;
        distributorAccount.Name = 'Distributor Account';
        distributorAccount.OwnerId = accountOwner.Id;
        insert distributorAccount;
        
        Sales_Target__c salesTarget = new Sales_Target__c();
        salesTarget.OwnerId = accountOwner.Id;
        salesTarget.Assigned_To__c = accountOwner.Id;
        salesTarget.Number_of_Month__c = Date.today().month();
        salesTarget.Primary_Sales_Actual__c = 0;
        salesTarget.Litre_Sold_Actual__c = 0;
        salesTarget.New_Outlet_Opened_Actual__c = 0;
        insert salesTarget;
        
        TriggerExecutionController__c tt = new TriggerExecutionController__c();
        tt.Name = 'OrderTrigger';
        tt.Is_Active__c = true;
        insert tt;
        
        Order__c order = new Order__c();
        order.AccountId__c = distributorAccount.Id;
        order.Total_Order_Value__c = 1000;
        order.RecordTypeId = secondaryInvoiceRT;
        insert order;
        
        order = [SELECT Id,RecordTypeId,AccountId__c,CreatedDate,Total_Order_Value__c FROM Order__c WHERE Id = :order.Id LIMIT 1];
        
        Test.setCreatedDate(order.Id, DateTime.newInstance(2023, 1, 15, 0, 0, 0));
        
        Test.startTest();
        UpdateSalesPerformancePSAHandler.updateSalesPerformance(new List<Order__c>{order});
        Test.stopTest();
    }
    
    @isTest
    static void testOrderUpdate() {
        
        Id secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Primary_Order' LIMIT 1].Id;
        
        User accountOwner = [SELECT Id, UserRoleId FROM User WHERE IsActive = TRUE AND UserRoleId != null LIMIT 1];
        
        Id distributorRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Distributor' LIMIT 1].Id;
        
        Account distributorAccount = new Account();
        distributorAccount.RecordTypeId = distributorRecordType;
        distributorAccount.Name = 'Distributor Account';
        distributorAccount.OwnerId = accountOwner.Id;
        insert distributorAccount;
        
        Sales_Target__c salesTarget = new Sales_Target__c();
        salesTarget.OwnerId = accountOwner.Id;
        salesTarget.Assigned_To__c = accountOwner.Id;
        salesTarget.Number_of_Month__c = Date.today().month();
        salesTarget.Primary_Sales_Actual__c = 0;
        salesTarget.Litre_Sold_Actual__c = 0;
        salesTarget.New_Outlet_Opened_Actual__c = 0;
        insert salesTarget;
        
        TriggerExecutionController__c tt = new TriggerExecutionController__c();
        tt.Name = 'OrderTrigger';
        tt.Is_Active__c = true;
        insert tt;
        
        Order__c order = new Order__c();
        order.AccountId__c = distributorAccount.Id;
        order.Total_Order_Value__c = 10000;
        order.RecordTypeId = secondaryInvoiceRT;
        order.Status__c = 'Order Placed';
        insert order;
        
        List<Order__c> orders = [SELECT Id, Status__c FROM Order__c Limit 1];
        
        for (Order__c ord : orders) {
            ord.Status__c = 'Partially Invoiced';
        }
        
        Test.startTest();
        Update orders;
        Test.stopTest();
        
    }
    
    @isTest
    static void testOrderDelete() {
        Id secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Primary_Order' LIMIT 1].Id;
        
        User accountOwner = [SELECT Id, UserRoleId FROM User WHERE IsActive = TRUE AND UserRoleId != null LIMIT 1];
        
        Id distributorRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Distributor' LIMIT 1].Id;
        
        Account distributorAccount = new Account();
        distributorAccount.RecordTypeId = distributorRecordType;
        distributorAccount.Name = 'Distributor Account';
        distributorAccount.OwnerId = accountOwner.Id;
        insert distributorAccount;
        
        Sales_Target__c salesTarget = new Sales_Target__c();
        salesTarget.OwnerId = accountOwner.Id;
        salesTarget.Assigned_To__c = accountOwner.Id;
        salesTarget.Number_of_Month__c = Date.today().month();
        salesTarget.Primary_Sales_Actual__c = 0;
        salesTarget.Litre_Sold_Actual__c = 0;
        salesTarget.New_Outlet_Opened_Actual__c = 0;
        insert salesTarget;
        
        TriggerExecutionController__c tt = new TriggerExecutionController__c();
        tt.Name = 'OrderTrigger';
        tt.Is_Active__c = true;
        insert tt;
        
        Order__c order = new Order__c();
        order.AccountId__c = distributorAccount.Id;
        order.Total_Order_Value__c = 10000;
        order.RecordTypeId = secondaryInvoiceRT;
        order.Status__c = 'Order Placed';
        insert order;
        
        List<Order__c> orders = [SELECT Id, Status__c FROM Order__c Limit 1];
        
        for (Order__c ord : orders) {
            ord.Status__c = 'Order Placed';
        }
        
        Test.startTest();
        delete orders;
        Test.stopTest();
        
    }
    
    @isTest
    static void testOrderUnDelete() {
        Id secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Primary_Order' LIMIT 1].Id;
        
        User accountOwner = [SELECT Id, UserRoleId FROM User WHERE IsActive = TRUE AND UserRoleId != null LIMIT 1];
        
        Id distributorRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Distributor' LIMIT 1].Id;
        
        Account distributorAccount = new Account();
        distributorAccount.RecordTypeId = distributorRecordType;
        distributorAccount.Name = 'Distributor Account';
        distributorAccount.OwnerId = accountOwner.Id;
        insert distributorAccount;
        
        Sales_Target__c salesTarget = new Sales_Target__c();
        salesTarget.OwnerId = accountOwner.Id;
        salesTarget.Assigned_To__c = accountOwner.Id;
        salesTarget.Number_of_Month__c = Date.today().month();
        salesTarget.Primary_Sales_Actual__c = 0;
        salesTarget.Litre_Sold_Actual__c = 0;
        salesTarget.New_Outlet_Opened_Actual__c = 0;
        insert salesTarget;
        
        TriggerExecutionController__c tt = new TriggerExecutionController__c();
        tt.Name = 'OrderTrigger';
        tt.Is_Active__c = true;
        insert tt;
        
        Order__c order = new Order__c();
        order.AccountId__c = distributorAccount.Id;
        order.Total_Order_Value__c = 10000;
        order.RecordTypeId = secondaryInvoiceRT;
        order.Status__c = 'Order Placed';
        insert order;
        
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