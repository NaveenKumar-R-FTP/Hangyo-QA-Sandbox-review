@isTest
private class SalesOrderAPI_Test {
    
    @testSetup
    static void setupTestData() {
        Sales_Office__c so = new Sales_Office__c(Sales_Office__C='AP',Sales_Organization__c = '1000',Name = 'Andhra Pradesh');
        insert so;
        Account acc = new Account(Name='Test Account', Code__c='1011000021',Sales_Office__C = so.Id,PAN_Number__c='ANZPN');
        insert acc;
        
        Order__c ord = new Order__c(
            AccountId__c=acc.Id,
            EffectiveDate__c=Date.today()
        );
        insert ord;

        // Create Product
        Product__c product = new Product__c(Name = 'Test Product', Product_Code__c = 'P001');        
        insert product;
        
        Order_Line_Item__c oli = new Order_Line_Item__c(
            Order__c=ord.Id,
            Products__c=product.Id,
            Ordered_Quantity__c=5
        );
        insert oli;
    }
    
    @isTest
    static void testPushOrderandOrderItems_Success() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        Order__c testOrder = [SELECT Id FROM Order__c LIMIT 1];
        
        // Act
        Test.startTest();
        SalesOrderAPI.pushOrderandOrderItems(testOrder.Id);
        SalesOrderAPI.pushOrderandOrderItems(null);
        Test.stopTest();
        
        // Assert
        Integration_Log__c log = [SELECT Status__c, Response__c FROM Integration_Log__c WHERE Record_Id__c = :testOrder.Id LIMIT 1];
        System.assertEquals('Success', log.Status__c, 'Expected log status to be Success');
        System.assertNotEquals(null, log.Response__c, 'Expected a response in log');
    }
    
    @isTest
    static void testPushOrderandOrderItems_Fail() {
        // Arrange
        Order__c testOrder = [SELECT Id FROM Order__c LIMIT 1];
        
        // Act
        Test.startTest();
        SalesOrderAPI.pushPrimaryOrderstoSAP(testOrder.Id);
        SalesOrderAPI.sendPrimaryOrderstoSAP(testOrder.Id);
        Test.stopTest();
        Integration_Log__c log = [SELECT Status__c, Error_Message__c FROM Integration_Log__c WHERE Record_Id__c = :testOrder.Id LIMIT 1];
        System.assertEquals('Fail', log.Status__c, 'Expected log status to be Fail');
        System.assertNotEquals(null, log.Error_Message__c, 'Expected an error message in log');
    }
    
}