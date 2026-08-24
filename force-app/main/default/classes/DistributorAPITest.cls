@isTest
private class DistributorAPITest {
    
    @testSetup
    static void setupTestData() {
        // Create necessary records for lookup
        Id distributorRTId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        
        Account acc = new Account(Name='Test Distributor', Code__c='D12345', RecordTypeId=distributorRTId,PAN_Number__c='ANZPN');
        insert acc;

        Distribution_Channel__c distChannel = new Distribution_Channel__c(Name='Retail', Distribution_Channel__c='DC001');
        insert distChannel;
        
        Pricing_Group__c pricingGroup = new Pricing_Group__c(Name='Wholesale', Code__c='PG001',Type__c='Customer');
        insert pricingGroup;
        
        Sales_Office__c salesOffice = new Sales_Office__c(Name='North Zone', Sales_Office__c='Z001');
        insert salesOffice;
        
        Region__c region = new Region__c(Name='West Region', Region__c='R001');
        insert region;
    }
    
    @isTest
    static void testLoadDirectDistributorsFromSapSuccess() {
        List<DistributorAPI.DistributorInfo> distributorData = new List<DistributorAPI.DistributorInfo>();
        DistributorAPI.DistributorInfo disInfo = new DistributorAPI.DistributorInfo();
            disInfo.code = 'D12345';
            disInfo.pAN = 'PAN123';
            disInfo.name = 'Test Distributor';
            disInfo.distributionChannelCode = 'DC001';
            disInfo.distributionChannelName = 'Retail';
            disInfo.categoryCode = 'PG001';
            disInfo.categoryName = 'Wholesale';
            disInfo.zoneCode = 'Z001';
            disInfo.zoneName = 'North Zone';
            disInfo.regionCode = 'R001';
            disInfo.regionName = 'West Region';
            disInfo.email = 'test@example.com';
            disInfo.creditLimit = '50000';
            disInfo.paymentTerms = 'Net 30';
            disInfo.paymentMode = 'Online';
            disInfo.gSTApplicable = 'true';
        distributorData.add(disInfo);

        Test.startTest();
        DistributorAPI.DistributorResponseData response = DistributorAPI.loadDirectDistributorsFromSAP(distributorData);
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(1, response.data.size(), 'Should return one response');
        System.assertNotEquals(null, response.data[0].id, 'Record ID should be present');
        System.assertEquals('Success', response.data[0].status, 'Record should be updated');
    }
    
    @isTest
    static void testLoadDirectDistributorsFromSAPEmptyData() {
        List<DistributorAPI.DistributorInfo> emptyData = new List<DistributorAPI.DistributorInfo>();

        Test.startTest();
        DistributorAPI.DistributorResponseData response = DistributorAPI.loadDirectDistributorsFromSAP(emptyData);
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(0, response.data.size(), 'Should return empty response');
    }
    
    @isTest
    static void testLoadDirectDistributorsFromSAPInvalidData() {
        List<DistributorAPI.DistributorInfo> invalidData = new List<DistributorAPI.DistributorInfo>();
        DistributorAPI.DistributorInfo invData =  new DistributorAPI.DistributorInfo();
            invData.code = 'D99999'; // Non-existing account
            invData.name = 'Invalid Distributor';
            invData.email = 'invalid@example.com';
        invalidData.add(invData);
        Test.startTest();
        DistributorAPI.DistributorResponseData response = DistributorAPI.loadDirectDistributorsFromSAP(invalidData);
        Test.stopTest();
        
        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(1, response.data.size(), 'Should return one response'); 
    }
}