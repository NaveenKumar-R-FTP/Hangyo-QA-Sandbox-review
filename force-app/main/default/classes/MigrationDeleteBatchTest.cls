@isTest
private class MigrationDeleteBatchTest {
    
    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', RecordTypeId = disRecId, PAN_Number__c='1344',Primary_State__c='Karnataka');
        insert distributor;
        
        Id retailerRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer = new Account(Name = 'Retailer', Distributor__c = distributor.Id, RecordTypeId = retailerRecId,Primary_State__c='Karnataka',PAN_Number__c='1344');
        insert retailer;
		
        RecordType secondaryOrderRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Order' AND SObjectType = 'Order__c' LIMIT 1];
        // Create Test Order
        Order__c ord = new Order__c(Account__c = retailer.Id,AccountId__c =distributor.ID,RecordTypeId = secondaryOrderRT.Id );
        insert ord;
        
        List<Order_Line_Item__c> items = new List<Order_Line_Item__c>();
        for (Integer i = 0; i < 10; i++) {
            items.add(new Order_Line_Item__c(Order__c = ord.Id, Archived__c = true, Archived_Date__c = DateTime.now().addDays(-10)));
        }
        insert items;
        
       
    }
    
    @isTest
    public static void testMethod1(){
        Azure_Archive_Config__mdt metadata1 = new Azure_Archive_Config__mdt(Object_API_Name__c='',Batch_Scope_Size__c=200,Migration_Delete_Enabled__c=false,Soft_Archive_Days__c=7);
        test.StartTest();
        MigrationDeleteBatch batch = new MigrationDeleteBatch(metadata1);
        Database.executeBatch(batch, 50);
        
        MigrationDeleteBatch batch3 = new MigrationDeleteBatch();
        Database.executeBatch(batch3, 50);
        Test.StopTest();
                
       
    }
    
}