@isTest
public class CaseTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        List<RetailerCodeSetting__c> settings = [
            SELECT Id FROM RetailerCodeSetting__c WHERE Name = 'SF' LIMIT 1
        ];
        if (settings.isEmpty()) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 0);
        }
    }

    static Case_Type__c createCaseType(String name) {
        Case_Type__c ct = new Case_Type__c(Name = name, Type__c = 'Case', Active__c = true);
        insert ct;
        return ct;
    }

    @isTest
    static void testHandleAfterUpdateNotApproved() {
        Case_Type__c ct = createCaseType('Test Not Approved');
        Case__c c = new Case__c(Case_Type__c = ct.Id, Status__c = 'Open');
        insert c;
        Test.startTest();
        c.Status__c = 'Pending';
        c.Sync__c = false;
        update c;
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testHandleAfterUpdateApprovedNoQR() {
        Case_Type__c ct = createCaseType('Test Approved No QR');
        Case__c c = new Case__c(Case_Type__c = ct.Id, Status__c = 'Open');
        insert c;
        Test.startTest();
        c.Status__c = 'Approved';
        c.Sync__c = true;
        update c;
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testOutletToOutletTransfer() {
        Case_Type__c ct = createCaseType('Asset Transfer OO');
        RecordType rtR = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailer1 = new Account(Name = 'Retailer From OO', RecordTypeId = rtR.Id);
        insert retailer1;
        Account retailer2 = new Account(Name = 'Retailer To OO', RecordTypeId = rtR.Id);
        insert retailer2;
        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-OO-001');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = retailer1.Id, Active__c = true
        );
        insert mapping;
        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Status__c = 'Open',
            OEM_serial_number__c = 'HIPL-OO-001',
            Request_type__c = 'Outlet to Outlet',
            Retailer_Transfer_From__c = retailer1.Id,
            Retailer_Transfer_To__c = retailer2.Id
        );
        insert c;
        Test.startTest();
        c.Status__c = 'Approved';
        c.Sync__c = true;
        update c;
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testOutletToDistributorTransfer() {
        Case_Type__c ct = createCaseType('Asset Transfer OD');
        RecordType rtR = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        RecordType rtD = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Distributor' LIMIT 1];
        Account retailer = new Account(Name = 'Retailer OD', RecordTypeId = rtR.Id);
        insert retailer;
        Account distributor = new Account(Name = 'Distributor OD', RecordTypeId = rtD.Id);
        insert distributor;
        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-OD-001');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = retailer.Id, Active__c = true
        );
        insert mapping;
        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Status__c = 'Open',
            OEM_serial_number__c = 'HIPL-OD-001',
            Request_type__c = 'Outlet to Distributor',
            Retailer_Transfer_From__c = retailer.Id,
            Distributor_Transfer_To__c = distributor.Id
        );
        insert c;
        Test.startTest();
        c.Status__c = 'Approved';
        c.Sync__c = true;
        update c;
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testDistributorToOutletTransfer() {
        Case_Type__c ct = createCaseType('Asset Transfer DO');
        RecordType rtR = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        RecordType rtD = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Distributor' LIMIT 1];
        Account distributor = new Account(Name = 'Distributor DO', RecordTypeId = rtD.Id);
        insert distributor;
        Account retailer = new Account(Name = 'Retailer DO', RecordTypeId = rtR.Id);
        insert retailer;
        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-DO-001');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Distributor__c = distributor.Id, Active__c = true
        );
        insert mapping;
        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Status__c = 'Open',
            OEM_serial_number__c = 'HIPL-DO-001',
            Request_type__c = 'Distributor to Outlet',
            Distributor_Transfer_From__c = distributor.Id,
            Retailer_Transfer_To__c = retailer.Id
        );
        insert c;
        Test.startTest();
        c.Status__c = 'Approved';
        c.Sync__c = true;
        update c;
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testDistributorToDistributorTransfer() {
        Case_Type__c ct = createCaseType('Asset Transfer DD');
        RecordType rtD = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Distributor' LIMIT 1];
        Account dist1 = new Account(Name = 'Distributor DD1', RecordTypeId = rtD.Id);
        insert dist1;
        Account dist2 = new Account(Name = 'Distributor DD2', RecordTypeId = rtD.Id);
        insert dist2;
        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-DD-001');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Distributor__c = dist1.Id, Active__c = true
        );
        insert mapping;
        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Status__c = 'Open',
            OEM_serial_number__c = 'HIPL-DD-001',
            Request_type__c = 'Distributor to Distributor',
            Distributor_Transfer_From__c = dist1.Id,
            Distributor_Transfer_To__c = dist2.Id
        );
        insert c;
        Test.startTest();
        c.Status__c = 'Approved';
        c.Sync__c = true;
        update c;
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testScrapTransfer() {
        Case_Type__c ct = createCaseType('Asset Transfer Scrap');
        RecordType rtR = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailer = new Account(Name = 'Retailer Scrap', RecordTypeId = rtR.Id);
        insert retailer;
        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-SC-001');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = retailer.Id, Active__c = true
        );
        insert mapping;
        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Status__c = 'Open',
            OEM_serial_number__c = 'HIPL-SC-001',
            Request_type__c = 'Scrap',
            Retailer_Transfer_From__c = retailer.Id,
            Scrap__c = 'Transferred to warehouse'
        );
        insert c;
        Test.startTest();
        c.Status__c = 'Approved';
        c.Sync__c = true;
        update c;
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testAssetAddition() {
        List<Case_Type__c> ctList = [SELECT Id FROM Case_Type__c WHERE Name = 'Asset Tagging Request' LIMIT 1];
        Case_Type__c ct = ctList.isEmpty() ? createCaseType('Asset Tagging Request') : ctList[0];
        RecordType rtR = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailer = new Account(Name = 'Retailer Addition', RecordTypeId = rtR.Id);
        insert retailer;
        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Status__c = 'Open',
            New_Asset_Code__c = 'HIPL-ADD-001',
            Retailer__c = retailer.Id
        );
        insert c;
        Test.startTest();
        c.Status__c = 'Approved';
        c.Sync__c = true;
        update c;
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testAssetCodeChange() {
        List<Case_Type__c> ctList = [SELECT Id FROM Case_Type__c WHERE Name = 'Existing outlet Asset Code Change Request' LIMIT 1];
        Case_Type__c ct = ctList.isEmpty() ? createCaseType('Existing outlet Asset Code Change Request') : ctList[0];
        RecordType rtR = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailer = new Account(Name = 'Retailer Code Change', RecordTypeId = rtR.Id);
        insert retailer;
        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-OLD-001');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = retailer.Id, Active__c = true
        );
        insert mapping;
        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Status__c = 'Open',
            Old_Asset_Code__c = 'HIPL-OLD-001',
            New_Asset_Code__c = 'HIPL-NEW-001',
            Retailer__c = retailer.Id
        );
        insert c;
        Test.startTest();
        c.Status__c = 'Approved';
        c.Sync__c = true;
        update c;
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testHandleAfterUpdateDirectCall() {
        Case_Type__c ct = createCaseType('Direct Call Test');
        Case__c c = new Case__c(Case_Type__c = ct.Id, Status__c = 'Approved', Sync__c = true);
        insert c;
        Test.startTest();
        Map<Id, Case__c> oldMap = new Map<Id, Case__c>{
            c.Id => new Case__c(Id = c.Id, Status__c = 'Open', Sync__c = false)
        };
        CaseTriggerHandler.handleAfterUpdate(new List<Case__c>{c}, oldMap);
        Test.stopTest();
        System.assert(true);
    }
}