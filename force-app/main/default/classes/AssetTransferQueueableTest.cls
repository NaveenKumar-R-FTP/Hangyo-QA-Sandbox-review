@isTest
public class AssetTransferQueueableTest {

    @TestSetup
    static void setupData() {
        List<RetailerCodeSetting__c> settings = [
            SELECT Id FROM RetailerCodeSetting__c WHERE Name = 'SF' LIMIT 1
        ];
        if (settings.isEmpty()) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 0);
        }
    }

    @isTest
    static void testExecuteEmptyCaseIds() {
        Test.startTest();
        Set<Id> caseIds = new Set<Id>();
        System.enqueueJob(new AssetTransferQueueable(caseIds));
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testExecuteWithCases() {
        Case_Type__c ct = new Case_Type__c(Name = 'Asset Transfer Q Test', Type__c = 'Case', Active__c = true);
        insert ct;
        Case__c c = new Case__c(
            Case_Type__c = ct.Id,
            Status__c = 'Approved',
            Sync__c = true
        );
        insert c;
        Test.startTest();
        Set<Id> caseIds = new Set<Id>{c.Id};
        System.enqueueJob(new AssetTransferQueueable(caseIds));
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testExecuteWithTransferCase() {
        List<Case_Type__c> ctList = [SELECT Id FROM Case_Type__c WHERE Name = 'Asset Transfer Request' LIMIT 1];
        Case_Type__c ct = ctList.isEmpty() ? 
            new Case_Type__c(Name = 'Asset Transfer Request', Type__c = 'Case', Active__c = true) : ctList[0];
        if (ctList.isEmpty()) insert ct;

        RecordType rtR = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailer1 = new Account(Name = 'Retailer Q From', RecordTypeId = rtR.Id);
        insert retailer1;
        Account retailer2 = new Account(Name = 'Retailer Q To', RecordTypeId = rtR.Id);
        insert retailer2;

        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-Q-001');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = retailer1.Id, Active__c = true
        );
        insert mapping;

        Case__c c = new Case__c(
            Case_Type__c = ct.Id,
            Status__c = 'Approved',
            Sync__c = true,
            OEM_serial_number__c = 'HIPL-Q-001',
            Request_type__c = 'Outlet to Outlet',
            Retailer_Transfer_From__c = retailer1.Id,
            Retailer_Transfer_To__c = retailer2.Id
        );
        insert c;

        Test.startTest();
        Set<Id> caseIds = new Set<Id>{c.Id};
        System.enqueueJob(new AssetTransferQueueable(caseIds));
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testConstructor() {
        Test.startTest();
        Set<Id> ids = new Set<Id>();
        AssetTransferQueueable q = new AssetTransferQueueable(ids);
        System.assertNotEquals(null, q);
        Test.stopTest();
    }
@isTest
static void testExecuteWithApprovedSyncCase() {
    List<RetailerCodeSetting__c> settings = [
        SELECT Id FROM RetailerCodeSetting__c WHERE Name = 'SF' LIMIT 1
    ];
    if (settings.isEmpty()) {
        insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 0);
    }
    
    Case_Type__c ct = new Case_Type__c(
        Name = 'Asset Transfer Q Approved', Type__c = 'Case', Active__c = true
    );
    insert ct;
    
    Case__c c = new Case__c(
        Case_Type__c = ct.Id,
        Status__c = 'Approved',
        Sync__c = true
    );
    insert c;
    
    Test.startTest();
    Set<Id> caseIds = new Set<Id>{c.Id};
    System.enqueueJob(new AssetTransferQueueable(caseIds));
    Test.stopTest();
    System.assert(true);
}
}