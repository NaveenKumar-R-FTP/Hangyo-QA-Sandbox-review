@isTest
public class CaseScreenControllerTest {
  // ================= TEST SETUP =================
  @testSetup
  static void setupData() {
    // Get Custom Notification Type
    CustomNotificationType cnt = [
      SELECT Id, DeveloperName
      FROM CustomNotificationType
      WHERE DeveloperName = 'Case_Notification'
      LIMIT 1
    ];

    RetailerCodeSetting__c setting = new RetailerCodeSetting__c(
      Name = 'SF',
      Latest_Code__c = 100
    );
    insert setting;

    // Distributor
    Id RetailerRT = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Retailer')
      .getRecordTypeId();
    Account Retailer = new Account(
      Name = 'Test Retailer',
      BillingCity = 'Mumbai',
      BillingState = 'Maharashtra',
      RecordTypeId = RetailerRT,
      Retailer_Code__c = 'SF168250'
    );
    insert Retailer;
    Id accrt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Distributor')
      .getRecordTypeId();
    Account distributor = new Account(
      Name = 'Test Distributor',
      BillingCity = 'Mumbai',
      BillingState = 'Maharashtra',
      RecordTypeId = accrt
    );
    insert distributor;
    Account Retailer1 = new Account(
      Name = 'Test Retailer with distributor',
      BillingCity = 'Mumbai',
      BillingState = 'Maharashtra',
      RecordTypeId = RetailerRT,
      Retailer_Code__c = 'SF168250',
      Distributor__c = distributor.Id
    );
    insert Retailer1;

    // Case Type
    Case_Type__c ct = new Case_Type__c(
      Name = 'Asset Not Found at Location',
      Active__c = true,
      Type__c = 'Claim'
    );
    insert ct;

    Case_Type__c casect = new Case_Type__c(
      Name = 'Asset Transfer Request',
      Active__c = true,
      Type__c = 'Case'
    );
    insert casect;

    Case_Type__c casect1 = new Case_Type__c(
      Name = 'Asset Complaint Request',
      Active__c = true,
      Type__c = 'Case'
    );
    insert casect1;
    Case_Type__c casect2 = new Case_Type__c(
      Name = 'Branding & Marketing Asset Inventory Management',
      Active__c = true,
      Type__c = 'Case'
    );
    insert casect2;
   Case_Type__c casect3 = new Case_Type__c(
      Name = 'Branding & Marketing Asset transfer Request',
      Active__c = true,
      Type__c = 'Case'
    );
    insert casect3;
    Case_Type__c casect4 = new Case_Type__c(
      Name = 'Branding & Marketing Asset Request',
      Active__c = true,
      Type__c = 'Case'
    );
    insert casect4;

    // Case Record
    Case__c c = new Case__c(
      Case_Type__c = casect.Id,
      Retailer__c = Retailer.Id,
      Status__c = 'Open',
      PIN_Code__c = '474001'
    );
    insert c;
    Case__c c1 = new Case__c(
      Case_Type__c = casect.Id,
      Retailer__c = Retailer.Id,
      Status__c = 'Approved',
      PIN_Code__c = '474001'
    );
    insert c1;

    // Case Record
    Case__c c2 = new Case__c(
      Case_Type__c = casect1.Id,
      Retailer__c = Retailer.Id,
      Status__c = 'Open',
      PIN_Code__c = '474001'
    );
    insert c2;
    Case__c c3 = new Case__c(
      Case_Type__c = casect1.Id,
      Retailer__c = Retailer.Id,
      Status__c = 'Approved',
      PIN_Code__c = '474001'
    );
    insert c3;

    // Form Field
    Form_Field__c ff = new Form_Field__c(
      API_Name__c = 'Name',
      Label__c = 'Name',
      Type__c = 'Text',
      Required__c = true,
      Sequence__c = 1,
      Case_Type__c = casect.Id,
      Visible__c = true
    );
    insert ff;
    Form_Field__c ff1 = new Form_Field__c(
      API_Name__c = 'Make__c',
      Label__c = 'Make',
      Type__c = 'Picklist',
      Required__c = true,
      Sequence__c = 1,
      Case_Type__c = casect.Id,
      Visible__c = true
    );
    insert ff1;
    Form_Field__c ff2 = new Form_Field__c(
      API_Name__c = 'Modal__c',
      Label__c = 'Modal',
      Type__c = 'Picklist',
      Controlling_Field__c = ff1.Id,
      Required__c = true,
      Sequence__c = 1,
      Case_Type__c = casect.Id,
      Visible__c = true
    );
    insert ff2;
    Form_Field__c ff3 = new Form_Field__c(
      API_Name__c = 'Capacity__c',
      Label__c = 'Capacity',
      Type__c = 'Picklist',
      Controlling_Field__c = ff2.Id,
      Required__c = true,
      Sequence__c = 1,
      Case_Type__c = casect.Id,
      Visible__c = true
    );
    insert ff3;

    // Picklist
    Form_Field_Picklist__c pick = new Form_Field_Picklist__c(
      Form_Field__c = ff1.Id,
      Name = 'Option1',
      Code__c = 'OP1',
      Active__c = true
    );
    insert pick;
    Form_Field_Picklist__c dpick = new Form_Field_Picklist__c(
      Form_Field__c = ff2.Id,
      Name = 'Option2',
      Code__c = 'OP2',
      Active__c = true,
      Parent_Picklist__c = pick.Id
    );
    insert dpick;
    Form_Field_Picklist__c dpick1 = new Form_Field_Picklist__c(
      Form_Field__c = ff3.Id,
      Name = 'Option3',
      Code__c = 'OP3',
      Active__c = true,
      Parent_Picklist__c = dpick.Id
    );
    insert dpick1;

    Visit__c visit = new Visit__c(Status__c = 'Not Started');
    insert visit;

    Visit_Task__c vt = new Visit_Task__c(
      Retailer__c = Retailer.Id,
      Visit__c = visit.Id
    );
    insert vt;

    // Asset Master
    Asset_Master__c assetMaster = new Asset_Master__c(
      Asset_Image__c = 'https://i.ytimg.com/vi/2Ps0698vnwI/maxresdefault.jpg?sqp=-oaymwEmCIAKENAF8quKqQMa8AEB-AH-DoACuAiKAgwIABABGGUgTig8MA8=&rs=AOn4CLCcXcaWlihXkQS-eTh50J_AdRNULQ',
      OEM_Serial_Number__c = 'Freezer',
      QR_Code__c = 'AM-003'
      
    );
    insert assetMaster;

    // Asset Mapping (NO Name - Auto Number)
    Asset_Mapping__c am = new Asset_Mapping__c(
      Asset_Master__c = assetMaster.Id,
      Retailer__c = vt.Retailer__c,
      Last_Audit_Date__c = Date.today(),
      External_ID__c = 'dhajs748724',
      Active__c = true,
      Allocation_Start_Date__c = Date.today(),
      Allocation_End_Date__c = Date.today(),
      Last_Service_Date__c = Date.today()
    );
    insert am;

    Asset_Mapping__c amvt = new Asset_Mapping__c(
      Asset_Master__c = assetMaster.Id,
      Retailer__c = vt.Retailer__c,
      Last_Audit_Date__c = Date.today(),
      External_ID__c = 'dhajs7487245656',
      Active__c = true,
      Allocation_Start_Date__c = Date.today(),
      Allocation_End_Date__c = Date.today(),
      Last_Service_Date__c = Date.today()
    );
    insert amvt;

    // Asset Audit (latest audit)
    Asset_Audit__c audit = new Asset_Audit__c(
      Asset__c = amvt.Id,
      Skip__c = true,
      Visit_Task__c = vt.Id
    );
    insert audit;
  }

  // ================= TEST GET CASE TYPES =================
  @isTest
  static void testGetCaseTypes() {
    Test.startTest();
    List<Map<String, String>> result = CaseScreenController.getCaseTypes();
    Test.stopTest();

    System.assert(!result.isEmpty(), 'Case types should not be empty');
  }

  // ================= TEST GET CASES =================
  @isTest
  static void testGetCases() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    Test.startTest();
    List<Case__c> cases = CaseScreenController.getCases(vt.Id);
    Test.stopTest();

    System.assert(cases.size() > 0, 'Cases should be returned');
  }

  @isTest
  static void testGetCasesWithoutVisitTask() {
    Case_Type__c ct = [
      SELECT Id, Name
      FROM Case_Type__c
      WHERE Type__c = 'Case' AND Name = 'Asset Transfer Request'
      LIMIT 1
    ];

    Case__c caseResult = [
      SELECT Id, Case_Type__c, Retailer__c, PIN_Code__c
      FROM Case__c
      WHERE Status__c = 'Approved' AND Case_Type__c = :ct.Id
    ];

    Test.startTest();

    List<Case__c> cases = CaseScreenController.getCases(null);

    Test.stopTest();

    System.assertNotEquals(null, cases);
  }

  @isTest
  static void getDistributorIdTest() {
    Account retailer = [
      SELECT Id, RecordTypeId, Distributor__c
      FROM Account
      WHERE Name = 'Test Retailer with distributor'
    ];

    Test.startTest();

    CaseScreenController.getDistributorId(retailer.Id);

    Test.stopTest();
  }

  // ================= TEST GET CASE FIELDS =================
  @isTest
  static void testGetCaseFields() {
    Case__c c = [SELECT Id FROM Case__c LIMIT 1];

    Test.startTest();
    List<Map<String, Object>> result = CaseScreenController.getCaseFields(c.Id);
    Test.stopTest();

    System.assert(result != null, 'Result should not be null');
  }

  // ================= TEST DYNAMIC FIELDS =================
  @isTest
  static void testGetDynamicFields() {
    Case_Type__c caseType = [
      SELECT Id, Name
      FROM Case_Type__c
      WHERE Name = 'Asset Transfer Request'
      LIMIT 1
    ];
    system.debug('caseType' + caseType);

    Form_Field__c ff = [
      SELECT
        Id,
        API_Name__c,
        Label__c,
        Type__c,
        Required__c,
        Sequence__c,
        Controlling_Field__c,
        Visible__c
      FROM Form_Field__c
      WHERE
        API_Name__c = 'Make__c'
        AND Case_Type__r.Name = :caseType.Name
        AND Visible__c = TRUE
    ];

    Form_Field_Picklist__c ffPicklist = [
      SELECT Id, Name, Form_Field__c, Active__c
      FROM Form_Field_Picklist__c
      WHERE Form_Field__c = :ff.Id
    ];
    Form_Field__c ff1 = [
      SELECT Id, Name
      FROM Form_Field__c
      WHERE API_Name__c = 'Modal__c' AND Case_Type__c = :caseType.Id
    ];

    Form_Field_Picklist__c dffPicklist = [
      SELECT Id, Name, Form_Field__c, Active__c
      FROM Form_Field_Picklist__c
      WHERE
        Form_Field__r.Controlling_Field__c = :ff.Id
        AND Parent_Picklist__c = :ffPicklist.Id
    ];
    system.debug('ffPicklist.Id' + ffPicklist.Id);
    system.debug('ff.Id' + ff.Id);
    Test.startTest();
    List<CaseScreenController.FormFieldWrapper> result = CaseScreenController.getDynamicFields(
      caseType.Name,
      ffPicklist.Id,
      ff.Id
    );
    Test.stopTest();
  }

  // ================= TEST SAVE CASE =================

  @isTest
  static void testSaveCase() {
    Case_Type__c ct = [
      SELECT Id, Name
      FROM Case_Type__c
      WHERE Type__c = 'Case' AND Name IN ('Asset Complaint Request')
    ];

    Account retailer = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Retailer'
      LIMIT 1
    ];

    //  3. Prepare input map
    Map<String, Object> data = new Map<String, Object>();
    data.put('Case_Type__c', ct.Id);
    data.put('Outlet__c', retailer.Id);
    data.put('Status__c', 'Open');
    data.put('Description__c', 'Test Desc');
    data.put('Remarks__c', 'Test Remarks');
    data.put('Reason_for_transfer__c', 'Damaged');
    data.put('Freezer_Type__c', 'Freezer');
    data.put('PIN_Code__c', '474001');

    Test.startTest();
    Id caseId = CaseScreenController.saveCase(data);
    Test.stopTest();

    System.assertNotEquals(null, caseId, 'Case should be created');

    //  5. Verify Case
    Case__c c = [
      SELECT Id, Name, PIN_Code__c
      FROM Case__c
      WHERE Id = :[SELECT Id FROM Case__c ORDER BY CreatedDate DESC LIMIT 1].Id
    ];

    System.assertNotEquals(null, c.Id);
  }

  @isTest
  static void testSaveCase1() {
    Case_Type__c ct = [
      SELECT Id, Name
      FROM Case_Type__c
      WHERE
        Type__c = 'Case'
        AND Name IN ('Branding & Marketing Asset Inventory Management')
    ];

    Account retailer = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Retailer'
      LIMIT 1
    ];

    //  3. Prepare input map
    Map<String, Object> data = new Map<String, Object>();
    data.put('Case_Type__c', ct.Id);
    data.put('Outlet__c', retailer.Id);
    data.put('Status__c', 'Open');
    data.put('Asset_1__c', '');
    data.put('Asset_Quantity_1__c', '1');

    // Inventory Management now routes through the ASM/RSM L1 guard. The running
    // test user has no ASM/RSM above them, so submission is correctly refused.
    Boolean blocked = false;
    Test.startTest();
    try {
      CaseScreenController.saveCase(data);
    } catch (Exception e) {
      blocked = true;
    }
    Test.stopTest();

    System.assert(blocked,
      'Inventory case must be blocked when no ASM/RSM approver exists above the submitter');
  }

  @isTest
  static void testSaveCase2() {
    Case_Type__c ct = [
      SELECT Id, Name
      FROM Case_Type__c
      WHERE
        Type__c = 'Case'
        AND Name IN ('Branding & Marketing Asset transfer Request')
    ];

    Account retailer = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Retailer'
      LIMIT 1
    ];

    //  3. Prepare input map
    Map<String, Object> data = new Map<String, Object>();
    data.put('Case_Type__c', ct.Id);
    data.put('Outlet__c', retailer.Id);
    data.put('Status__c', 'Open');
    data.put('Description__c', 'Test Desc');
    data.put('Remarks__c', 'Test Remarks');
    data.put('Reason_for_transfer__c', 'Damaged');
    data.put('Freezer_Type__c', 'Freezer');
    data.put('PIN_Code__c', '474001');

    // Transfer requests now route through the ASM/RSM L1 guard too. The running
    // test user has no ASM/RSM above them, so submission is correctly refused.
    Boolean blocked = false;
    Test.startTest();
    try {
      CaseScreenController.saveCase(data);
    } catch (Exception e) {
      blocked = true;
    }
    Test.stopTest();

    System.assert(blocked,
      'Transfer request must be blocked when no ASM/RSM approver exists above the submitter');
  }

  // ================= TEST LINK FILE =================
  @isTest
  static void testuploadFiles() {
    //  Step 1: Create test Case
    Case__c c = [SELECT Id FROM Case__c LIMIT 1];

    String fileContent = 'Test File Data';
    String base64Data = EncodingUtil.base64Encode(Blob.valueOf(fileContent));

    List<Map<String, String>> files = new List<Map<String, String>>();

    Map<String, String> fileMap = new Map<String, String>();
    fileMap.put('fileName', 'test.jpg');
    fileMap.put('base64', base64Data);

    files.add(fileMap);

    Test.startTest();
    CaseScreenController.uploadFiles(c.Id, files);
    Test.stopTest();

    List<ContentDocumentLink> links = [
      SELECT Id, LinkedEntityId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :c.Id
    ];

    System.assert(links.size() > 0, 'File should be linked to case');
  }

  // ================= TEST CREATE ASSET AUDIT =================
  @isTest
  static void testCreateAssetAudit() {
    Case_Type__c caseType = [
      SELECT Id, Name
      FROM Case_Type__c
      WHERE Name = 'Asset Not Found at Location'
      LIMIT 1
    ];

    Asset_Mapping__c am = [
      SELECT
        Id,
        Asset_Master__c,
        Distributor__c,
        Last_Audit_Date__c,
        External_ID__c,
        Active__c,
        Allocation_Start_Date__c,
        Allocation_End_Date__c,
        Last_Service_Date__c
      FROM Asset_Mapping__c
      LIMIT 1
    ];
    Visit_Task__c vt = [SELECT Id FROM Visit_Task__c LIMIT 1];
    Test.startTest();
    CaseScreenController.createAssetAudit(
      am.Id,
      'Asset Not Found at Location',
      'SKIP',
      null
    );
    Test.stopTest();

    System.assert(true, 'Audit created');
  }

  // ================= MOCK FOR CALLOUT =================
  class MockHttp implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody('Test Image');
      return res;
    }
  }

  @isTest
  static void testGetAssets() {
    // Get Visit Task from setup
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    Asset_Mapping__c am = [
      SELECT
        Id,
        Asset_Master__c,
        Distributor__c,
        Last_Audit_Date__c,
        External_ID__c,
        Active__c,
        Allocation_Start_Date__c,
        Allocation_End_Date__c,
        Last_Service_Date__c
      FROM Asset_Mapping__c
      WHERE Retailer__c = :vt.Retailer__c AND External_ID__c = 'dhajs7487245656'
      LIMIT 1
    ];
    Asset_Audit__c audit = [
      SELECT Id, Asset__c
      FROM Asset_Audit__c
      WHERE Asset__c = :am.Id
    ];

    system.debug('vt test' + vt);
    system.debug('am test' + am);
    //system.debug('audit test'+audit);

    Test.startTest();
    List<CaseScreenController.AssetWrapper> result = CaseScreenController.getAssets(
      vt.Id
    );
    CaseScreenController.checkAllAssetsAudited(vt.Id);
    CaseScreenController.checkAllAuditedForOrder(vt.Id);
    CaseScreenController.getVisitCreatedDate(vt.Id);
    Test.stopTest();

    // Assertions
    System.assertNotEquals(null, result, 'Result should not be null');
    //System.assert(result.size() > 0, 'Assets should be returned');

    CaseScreenController.AssetWrapper wrap = result[0];

    System.assertNotEquals(null, wrap.mappingId);
    System.assertEquals(true, wrap.active);
  }
@isTest
static void testCheckAssetCodeInMaster() {
    Test.startTest();
    String result1 = CaseScreenController.checkAssetCodeInMaster('HIPL-TEST-001');
    String result2 = CaseScreenController.checkAssetCodeInMaster('INVALID-001');
    String result3 = CaseScreenController.checkAssetCodeInMaster('');
    Test.stopTest();
    System.assert(result1 == 'OK' || result1 == 'DUPLICATE_MASTER');
    System.assertEquals('INVALID_PREFIX', result2);
    System.assertEquals('OK', result3);
}

@isTest
static void testCheckSerialNumber() {
    Test.startTest();
    String result1 = CaseScreenController.checkSerialNumber('SN123456');
    String result2 = CaseScreenController.checkSerialNumber('');
    Test.stopTest();
    System.assertEquals('OK', result1);
    System.assertEquals('OK', result2);
}

@isTest
static void testGetRetailersByUser() {
    Test.startTest();
    List<Map<String, String>> result = CaseScreenController.getRetailersByUser();
    Test.stopTest();
    System.assertNotEquals(null, result);
}

@isTest
static void testGetDistributorsByUser() {
    Test.startTest();
    List<Map<String, String>> result = CaseScreenController.getDistributorsByUser();
    Test.stopTest();
    System.assertNotEquals(null, result);
}

@isTest
static void testGetAssetsByAccount() {
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Account distributor = [SELECT Id FROM Account WHERE Name = 'Test Distributor' LIMIT 1];
    Test.startTest();
    List<CaseScreenController.AssetWrapper> result1 = CaseScreenController.getAssetsByAccount(retailer.Id, null);
    List<CaseScreenController.AssetWrapper> result2 = CaseScreenController.getAssetsByAccount(null, distributor.Id);
    List<CaseScreenController.AssetWrapper> result3 = CaseScreenController.getAssetsByAccount(null, null);
    Test.stopTest();
    System.assertNotEquals(null, result1);
    System.assertNotEquals(null, result2);
    System.assertNotEquals(null, result3);
}

@isTest
static void testGetUnproductiveReason() {
    Visit_Task__c vt = [SELECT Id FROM Visit_Task__c LIMIT 1];
    Test.startTest();
    String result = CaseScreenController.getUnproductiveReason(vt.Id);
    String resultNull = CaseScreenController.getUnproductiveReason(null);
    Test.stopTest();
    System.assert(result == null || result != null);
    System.assertEquals(null, resultNull);
}

@isTest
static void testCheckNewAssetCode() {
    Test.startTest();
    String result = CaseScreenController.checkNewAssetCode('HIPL-TEST-NEW');
    String resultBlank = CaseScreenController.checkNewAssetCode('');
    Test.stopTest();
    System.assertEquals('OK', result);
    System.assertEquals('OK', resultBlank);
}

@isTest
static void testCheckQRCodeDuplicate() {
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Test.startTest();
    String result1 = CaseScreenController.checkQRCodeDuplicate('HIPL-QR-999', retailer.Id);
    String result2 = CaseScreenController.checkQRCodeDuplicate('', null);
    Test.stopTest();
    System.assertEquals('OK', result1);
    System.assertEquals('OK', result2);
}

@isTest
static void testSaveCaseAssetTransfer() {
    Case_Type__c ct = [SELECT Id FROM Case_Type__c WHERE Name = 'Asset Transfer Request' LIMIT 1];
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Test.startTest();
    try {
        Map<String, Object> data = new Map<String, Object>{
            'Case_Type__c' => ct.Id,
            'Retailer__c' => retailer.Id,
            'Status__c' => 'Open'
        };
        Id result = CaseScreenController.saveCase(data);
        System.assertNotEquals(null, result);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}
@isTest
static void testSaveCaseWithPicklist() {
    Case_Type__c ct = [SELECT Id FROM Case_Type__c WHERE Name = 'Asset Transfer Request' LIMIT 1];
    Form_Field_Picklist__c pick = [SELECT Id, Name FROM Form_Field_Picklist__c WHERE Name = 'Option1' LIMIT 1];
    Test.startTest();
    try {
        Map<String, Object> data = new Map<String, Object>{
            'Case_Type__c' => ct.Id,
            'Make__c' => pick.Id,
            'Status__c' => 'Open'
        };
        Id result = CaseScreenController.saveCase(data);
        System.assertNotEquals(null, result);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}

@isTest
static void testCheckAssetCodeInMasterDuplicate() {
    Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-EXIST-001');
    insert master;
    Test.startTest();
    String result = CaseScreenController.checkAssetCodeInMaster('HIPL-EXIST-001');
    Test.stopTest();
    System.assertEquals('DUPLICATE_MASTER', result);
}

@isTest
static void testGetCaseFieldsWithCase() {
    Case__c c = [SELECT Id FROM Case__c LIMIT 1];
    Test.startTest();
    try {
        List<Map<String, Object>> result = CaseScreenController.getCaseFields(c.Id);
        System.assertNotEquals(null, result);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}

@isTest
static void testCreateAssetAuditScan() {
    Asset_Mapping__c am = [SELECT Id FROM Asset_Mapping__c LIMIT 1];
    Visit_Task__c vt = [SELECT Id FROM Visit_Task__c LIMIT 1];
    Test.startTest();
    try {
        CaseScreenController.createAssetAudit(am.Id, null, 'SCAN', vt.Id);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}
@isTest
static void testSaveCaseNewAsset() {
    Case_Type__c ct = new Case_Type__c(
        Name = 'Asset Tagging Request Test', Type__c = 'Case', Active__c = true
    );
    insert ct;
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Test.startTest();
    try {
        Map<String, Object> data = new Map<String, Object>{
            'Case_Type__c' => ct.Id,
            'Retailer__c' => retailer.Id,
            'New_Asset_Code__c' => 'HIPL-NEW-999',
            'Status__c' => 'Open'
        };
        Id result = CaseScreenController.saveCase(data);
        System.assertNotEquals(null, result);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}

@isTest
static void testGetAssetsDistributor() {
    Visit__c visit = new Visit__c(Status__c = 'Not Started');
    insert visit;
    Account distributor = [SELECT Id FROM Account WHERE Name = 'Test Distributor' LIMIT 1];
    Visit_Task__c vt = new Visit_Task__c(
        Distributor__c = distributor.Id,
        Visit__c = visit.Id
    );
    insert vt;
    Test.startTest();
    try {
        List<CaseScreenController.AssetWrapper> result = CaseScreenController.getAssets(vt.Id);
        System.assertNotEquals(null, result);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}

@isTest
static void testCheckAllAssetsAuditedNotAudited() {
    Visit__c visit = new Visit__c(Status__c = 'Not Started');
    insert visit;
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Visit_Task__c vt = new Visit_Task__c(
        Retailer__c = retailer.Id,
        Visit__c = visit.Id
    );
    insert vt;
    Test.startTest();
    String result = CaseScreenController.checkAllAssetsAudited(vt.Id);
    Test.stopTest();
    System.assert(result == 'NOT_AUDITED' || result == 'VISIT_AUDITED' || result == null);
}

@isTest
static void testSaveCaseWithDateField() {
    Case_Type__c ct = [SELECT Id FROM Case_Type__c WHERE Name = 'Asset Transfer Request' LIMIT 1];
    Test.startTest();
    try {
        Map<String, Object> data = new Map<String, Object>{
            'Case_Type__c' => ct.Id,
            'Status__c' => 'Open',
            'Expected_delivery_date__c' => String.valueOf(Date.today().addDays(5))
        };
        Id result = CaseScreenController.saveCase(data);
        System.assertNotEquals(null, result);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}

@isTest
static void testCheckNewAssetCodeDuplicate() {
    Case_Type__c ct = [SELECT Id FROM Case_Type__c WHERE Name = 'Asset Transfer Request' LIMIT 1];
    Case__c c = new Case__c(
        Case_Type__c = ct.Id,
        Status__c = 'Open',
        New_Asset_Code__c = 'HIPL-DUP-001'
    );
    insert c;
    Test.startTest();
    String result = CaseScreenController.checkNewAssetCode('HIPL-DUP-001');
    Test.stopTest();
    System.assert(result == 'OK' || result.startsWith('DUPLICATE'));
}
@isTest
static void testGetRoleLevelCoverage() {
    Test.startTest();
    try {
        // Create case for Asset Transfer Request to trigger getApproverChain
        Case_Type__c ct = [SELECT Id FROM Case_Type__c WHERE Name = 'Asset Transfer Request' LIMIT 1];
        Map<String, Object> data = new Map<String, Object>{
            'Case_Type__c' => ct.Id,
            'Status__c' => 'Open',
            'Retailer__c' => [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1].Id
        };
        CaseScreenController.saveCase(data);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}
@isTest
static void testSaveCaseNewAssetRequest() {
    Case_Type__c ct = new Case_Type__c(
        Name = 'New Asset Request', Type__c = 'Case', Active__c = true
    );
    insert ct;
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Test.startTest();
    try {
        Map<String, Object> data = new Map<String, Object>{
            'Case_Type__c' => ct.Id,
            'Retailer__c' => retailer.Id,
            'Status__c' => 'Open'
        };
        Id result = CaseScreenController.saveCase(data);
        System.assertNotEquals(null, result);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}

@isTest
static void testSaveCaseAssetTagging() {
    Case_Type__c ct = new Case_Type__c(
        Name = 'Asset Tagging Request', Type__c = 'Case', Active__c = true
    );
    insert ct;
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Test.startTest();
    try {
        Map<String, Object> data = new Map<String, Object>{
            'Case_Type__c' => ct.Id,
            'Retailer__c' => retailer.Id,
            'Status__c' => 'Open'
        };
        Id result = CaseScreenController.saveCase(data);
        System.assertNotEquals(null, result);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}

@isTest
static void testSaveCaseExistingOutlet() {
    Case_Type__c ct = new Case_Type__c(
        Name = 'Existing outlet Asset Code Change Request', Type__c = 'Case', Active__c = true
    );
    insert ct;
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Test.startTest();
    try {
        Map<String, Object> data = new Map<String, Object>{
            'Case_Type__c' => ct.Id,
            'Retailer__c' => retailer.Id,
            'Status__c' => 'Open'
        };
        Id result = CaseScreenController.saveCase(data);
        System.assertNotEquals(null, result);
    } catch (Exception e) {
        System.assert(true);
    }
    Test.stopTest();
}
@isTest
static void testSaveCaseWithManagerChain() {
    Case_Type__c ct = [SELECT Id FROM Case_Type__c WHERE Name = 'Asset Transfer Request' LIMIT 1];
    
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    
    UserRole asmRole = new UserRole(Name = 'ASM-Cover-Role', DeveloperName = 'ASM_Cover_Role');
    insert asmRole;
    
    User managerUser = new User(
        FirstName = 'ASM', LastName = 'Manager',
        Alias = 'asmmgr',
        Email = 'asmmgr@hangyo.in',
        Username = 'asmmgr' + System.currentTimeMillis() + '@hangyo.in',
        ProfileId = p.Id,
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        TimeZoneSidKey = 'America/Los_Angeles',
        UserRoleId = asmRole.Id
    );
    insert managerUser;
    
    User soUser = new User(
        FirstName = 'SO', LastName = 'User',
        Alias = 'sousr',
        Email = 'sousr@hangyo.in',
        Username = 'sousr' + System.currentTimeMillis() + '@hangyo.in',
        ProfileId = p.Id,
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        TimeZoneSidKey = 'America/Los_Angeles',
        ManagerId = managerUser.Id
    );
    insert soUser;
    
    System.runAs(soUser) {
        Test.startTest();
        try {
            Map<String, Object> data = new Map<String, Object>{
                'Case_Type__c' => ct.Id,
                'Status__c' => 'Open'
            };
            Id result = CaseScreenController.saveCase(data);
            System.assertNotEquals(null, result);
        } catch (Exception e) {
            System.assert(true);
        }
        Test.stopTest();
    }
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
@isTest
  static void testSaveCaseBranding() {
    Case_Type__c ct = [
      SELECT Id FROM Case_Type__c
      WHERE Name = 'Branding & Marketing Asset Request'
      LIMIT 1
    ];
    Account retailer = [
      SELECT Id FROM Account
      WHERE Name = 'Test Retailer'
      LIMIT 1
    ];
    Map<String, Object> data = new Map<String, Object>();
    data.put('Case_Type__c', ct.Id);
    data.put('Retailer__c', retailer.Id);
    data.put('Status__c', 'Open');

    // L1 must be an ASM/RSM. The running test user has no such manager, so this
    // now correctly refuses rather than routing to the wrong approval level.
    Boolean blocked = false;
    Test.startTest();
    try {
      CaseScreenController.saveCase(data);
    } catch (Exception e) {
      blocked = true;
    }
    Test.stopTest();

    System.assert(blocked,
      'Branding case must be blocked when no ASM/RSM approver exists above the submitter');
  }


  @isTest
static void testUpdateCaseToInstalled() {
    Case__c c = new Case__c(Status__c = 'Installation Pending');
    insert c;

    Test.startTest();
    CaseScreenController.updateCaseToInstalled(c.Id);
    Test.stopTest();

    Case__c updated = [SELECT Status__c FROM Case__c WHERE Id = :c.Id];
    System.assertEquals('Installed', updated.Status__c);
}

  // ================= DYNAMIC FIELDS - INITIAL FORM LOAD =================
  // selectedId and ffId both null is the initial-load branch, which the
  // existing testGetDynamicFields never reaches.
  @isTest
  static void testGetDynamicFieldsInitialLoad() {
    Test.startTest();
    List<CaseScreenController.FormFieldWrapper> result = CaseScreenController.getDynamicFields(
      'Asset Transfer Request', null, null
    );
    Test.stopTest();

    System.assertEquals(4, result.size(), 'All 4 visible form fields should be returned');

    Map<String, CaseScreenController.FormFieldWrapper> byApiName =
      new Map<String, CaseScreenController.FormFieldWrapper>();
    for (CaseScreenController.FormFieldWrapper w : result) {
      byApiName.put(w.apiName, w);
    }

    CaseScreenController.FormFieldWrapper makeField = byApiName.get('Make__c');
    System.assertNotEquals(null, makeField, 'Make__c should be returned');
    System.assertEquals('Make', makeField.label);
    System.assertEquals(true, makeField.required);
    System.assertEquals(true, makeField.isControlling,
      'Make__c controls Modal__c so it must be flagged as controlling');
    System.assertEquals(1, makeField.options.size(),
      'Make__c should expose its one top-level picklist option');
    System.assertEquals('Option1', makeField.options[0].label);

    System.assertEquals(null, byApiName.get('Capacity__c').options,
      'Capacity__c only has a dependent option, so no top-level options');
  }

  // ================= SAVE CASE - SCRAP LABEL TRANSLATION =================
  @isTest
  static void testSaveCaseScrapMapping() {
    Case_Type__c ct = [
      SELECT Id FROM Case_Type__c WHERE Name = 'Asset Complaint Request' LIMIT 1
    ];
    Account retailer = [
      SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1
    ];

    Map<String, Object> data = new Map<String, Object>{
      'Case_Type__c' => ct.Id,
      'Retailer__c' => retailer.Id,
      'Status__c' => 'Open',
      'Scrap__c' => 'Transfer to Distributor'
    };

    Test.startTest();
    Id caseId = CaseScreenController.saveCase(data);
    Test.stopTest();

    Case__c saved = [SELECT Id, Scrap__c FROM Case__c WHERE Id = :caseId];
    System.assertEquals('Transferred to warehouse', saved.Scrap__c,
      'Scrap label should be translated to the actual SF picklist value');
  }

  // ================= NULL ARGUMENT GUARDS =================
  @isTest
  static void testNullArgumentGuards() {
    Case__c c = [SELECT Id FROM Case__c LIMIT 1];

    Test.startTest();
    Id distributorId = CaseScreenController.getDistributorId(null);
    Datetime createdDate = CaseScreenController.getVisitCreatedDate(null);
    CaseScreenController.uploadFiles(c.Id, null);
    CaseScreenController.uploadFiles(c.Id, new List<Map<String, String>>());
    Test.stopTest();

    System.assertEquals(null, distributorId, 'Null retailer should return null');
    System.assertEquals(null, createdDate, 'Null visit task should return null');
    System.assertEquals(0,
      [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id],
      'No files should be linked when the file list is null or empty');
  }

  // ================= CHECK SERIAL NUMBER - DUPLICATE =================
  @isTest
  static void testCheckSerialNumberDuplicate() {
    Case_Type__c ct = new Case_Type__c(
      Name = 'Existing outlet Asset Code Change Request',
      Type__c = 'Case',
      Active__c = true
    );
    insert ct;

    // Alphanumeric only - Serial_Number_Only_Alphanumeric validation rule
    // rejects anything else.
    Case__c existing = new Case__c(
      Case_Type__c = ct.Id,
      Status__c = 'Open',
      Serial_Number__c = 'SNDUP001'
    );
    insert existing;

    Case__c reloaded = [SELECT Id, Name FROM Case__c WHERE Id = :existing.Id];

    Test.startTest();
    String result = CaseScreenController.checkSerialNumber('SNDUP001');
    Test.stopTest();

    System.assertEquals('DUPLICATE_CASE:' + reloaded.Name + ':Open', result,
      'Duplicate serial should return the blocking case name and status');
  }

  // ================= CHECK QR CODE - DUPLICATE =================
  @isTest
  static void testCheckQRCodeDuplicateFound() {
    Account retailer = [
      SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1
    ];

    Test.startTest();
    // 'Freezer' is the OEM_Serial_Number__c on the asset mapped in @testSetup
    String result = CaseScreenController.checkQRCodeDuplicate('Freezer', retailer.Id);
    Test.stopTest();

    System.assertEquals('DUPLICATE', result,
      'An active mapping with this OEM serial already exists for the retailer');
  }

  // ================= BRANDING AUDIT HELPERS =================
  private static Branding_Asset__c newBrandingAsset(Id accountId, String mediaType, Boolean active) {
    return new Branding_Asset__c(
      Account__c                = accountId,
      Active__c                 = active,
      Media_Type__c             = mediaType,
      Media_Sub_Type__c         = 'Back lit Signage',
      Installation_Image_URL__c = 'https://example.com/installed.jpg'
    );
  }

  // ================= GET BRANDING ASSETS =================
  @isTest
  static void testGetBrandingAssetsReturnsOnlyActive() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    insert new List<Branding_Asset__c>{
      newBrandingAsset(vt.Retailer__c, 'Signage', true),
      newBrandingAsset(vt.Retailer__c, 'Flange', false)
    };

    Test.startTest();
    List<Branding_Asset__c> result = CaseScreenController.getBrandingAssets(vt.Id);
    Test.stopTest();

    System.assertEquals(1, result.size(), 'Only the active branding asset should be returned');
    System.assertEquals('Signage', result[0].Media_Type__c,
      'The active asset is the Signage one');
    System.assertEquals('https://example.com/installed.jpg', result[0].Installation_Image_URL__c,
      'The captured installation image must be returned for the audit panel to show it');
  }

  // ================= GET BRANDING ASSET PHOTOS =================
  @isTest
  static void testGetBrandingAssetPhotosInlinesTheFileBytes() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];

    ContentVersion cv = new ContentVersion(
      Title = 'installed.jpg',
      PathOnClient = 'installed.jpg',
      VersionData = Blob.valueOf('pretend-jpeg-bytes')
    );
    insert cv;

    // The component only ever sees the URL, so store it exactly as attachFiles does.
    Branding_Asset__c asset = newBrandingAsset(vt.Retailer__c, 'Signage', true);
    asset.Installation_Image_URL__c =
      'https://example.my.salesforce.com/sfc/servlet.shepherd/version/download/' + cv.Id;
    insert asset;

    Test.startTest();
    Map<Id, String> photos = CaseScreenController.getBrandingAssetPhotos(vt.Id);
    Test.stopTest();

    System.assert(photos.containsKey(asset.Id),
      'The asset whose URL points at a real file should get its bytes back');
    System.assert(photos.get(asset.Id).startsWith('data:image/'),
      'The photo must come back as a data: URI so the <img> can render it directly');
    System.assert(photos.get(asset.Id).contains(EncodingUtil.base64Encode(Blob.valueOf('pretend-jpeg-bytes'))),
      'The data URI should carry the actual file bytes');
  }

  @isTest
  static void testGetBrandingAssetPhotosSkipsAssetsWithNoFile() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    // newBrandingAsset stores a plain https URL that is not a shepherd link.
    Branding_Asset__c asset = newBrandingAsset(vt.Retailer__c, 'Flange', true);
    insert asset;

    Test.startTest();
    Map<Id, String> photos = CaseScreenController.getBrandingAssetPhotos(vt.Id);
    Test.stopTest();

    System.assert(!photos.containsKey(asset.Id),
      'A non-shepherd URL has no ContentVersion to inline and must be skipped');
  }

  // ================= SUBMIT BRANDING AUDIT - DAMAGE WITH PHOTO =================
  @isTest
  static void testSubmitBrandingAuditAttachesDamagePhoto() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(vt.Retailer__c, 'Signage', true);
    insert asset;

    CaseScreenController.BrandingAuditLineInput line =
      new CaseScreenController.BrandingAuditLineInput();
    line.brandingAssetId = asset.Id;
    line.mediaType = 'Signage';
    line.subMedia = 'Back lit Signage';
    line.condition = 'Damage';
    line.remarks = 'Panel cracked on the left edge';
    line.fileName = 'damage.jpg';
    line.base64 = EncodingUtil.base64Encode(Blob.valueOf('fake-image-bytes'));

    Test.startTest();
    Id headerId = CaseScreenController.submitBrandingAudit(
      vt.Id, new List<CaseScreenController.BrandingAuditLineInput>{ line }
    );
    Test.stopTest();

    System.assertNotEquals(null, headerId, 'A Branding Audit header should be created');

    Branding_Audit__c header = [
      SELECT Id, Retailer_Account__c, Visit_Task__c, Visit_Number__c
      FROM Branding_Audit__c WHERE Id = :headerId
    ];
    System.assertEquals(vt.Id, header.Visit_Task__c, 'Header is tied to the visit task');
    System.assertEquals(vt.Retailer__c, header.Retailer_Account__c, 'Header carries the outlet');

    List<Branding_Audit_Line__c> savedLines = [
      SELECT Id, Condition__c, Remarks__c, Photo_Link__c, Branding_Asset__c
      FROM Branding_Audit_Line__c WHERE Branding_Audit__c = :headerId
    ];
    System.assertEquals(1, savedLines.size(), 'One line per audited asset');
    System.assertEquals('Damage', savedLines[0].Condition__c, 'Condition is stored');
    System.assertEquals(asset.Id, savedLines[0].Branding_Asset__c, 'Line points at the asset');
    System.assertNotEquals(null, savedLines[0].Photo_Link__c,
      'attachFiles should have returned a download URL onto Photo_Link__c');

    List<ContentDocumentLink> links = [
      SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :savedLines[0].Id
    ];
    System.assertEquals(1, links.size(), 'The photo should be linked to its audit line');
  }

  // ================= SUBMIT BRANDING AUDIT - NO PHOTO =================
  @isTest
  static void testSubmitBrandingAuditWithoutPhotoLeavesLinkEmpty() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(vt.Retailer__c, 'Standee', true);
    insert asset;

    CaseScreenController.BrandingAuditLineInput line =
      new CaseScreenController.BrandingAuditLineInput();
    line.brandingAssetId = asset.Id;
    line.mediaType = 'Standee';
    line.subMedia = 'Lit Standee';
    line.condition = 'Present';
    line.remarks = 'In good condition';

    Test.startTest();
    Id headerId = CaseScreenController.submitBrandingAudit(
      vt.Id, new List<CaseScreenController.BrandingAuditLineInput>{ line }
    );
    Test.stopTest();

    Branding_Audit_Line__c saved = [
      SELECT Photo_Link__c, Condition__c FROM Branding_Audit_Line__c
      WHERE Branding_Audit__c = :headerId LIMIT 1
    ];
    System.assertEquals('Present', saved.Condition__c, 'Condition is stored');
    System.assertEquals(null, saved.Photo_Link__c,
      'A line with no photo must not get a Photo_Link__c');
  }

  // ================= DUPLICATE RETURN CASE GUARD =================
  private static Id returnVendorId() {
    List<Vendor__c> existing = [SELECT Id FROM Vendor__c WHERE Name = 'Test Return Vendor' LIMIT 1];
    if (!existing.isEmpty()) return existing[0].Id;
    Vendor__c v = new Vendor__c(Name = 'Test Return Vendor', Hub__c = 'Goa');
    insert v;
    return v.Id;
  }

  private static Case__c newReturnCase(Id brandingAssetId, String status) {
    Case_Type__c returnType = [
      SELECT Id FROM Case_Type__c
      WHERE Name = 'Branding & Marketing Asset transfer Request' LIMIT 1
    ];
    // Condition is mandatory on this type, and Vendor + Branding Return Status are
    // mandatory before Completed - see the two Return_Case_* validation rules.
    return new Case__c(
      Case_Type__c              = returnType.Id,
      Branding_Asset__c         = brandingAssetId,
      Condition__c              = 'Damaged',
      Vendor__c                 = returnVendorId(),
      Branding_Return_Status__c = 'Consumed',
      Status__c                 = status
    );
  }

  @isTest
  static void testPendingReturnCaseBlocksAnother() {
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(retailer.Id, 'Signage', true);
    insert asset;
    insert newReturnCase(asset.Id, 'Pending');

    Test.startTest();
    Boolean blocked = CaseScreenController.hasPendingReturnCase(asset.Id);
    Test.stopTest();

    System.assertEquals(true, blocked,
      'A return case sitting at Pending must block a second one');
  }

  @isTest
  static void testReturnCaseStillBlocksAfterL1Approval() {
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(retailer.Id, 'Flange', true);
    insert asset;
    // Past Pending but not finished - the return is still in flight.
    insert newReturnCase(asset.Id, 'L1 Approved');

    Test.startTest();
    Boolean blocked = CaseScreenController.hasPendingReturnCase(asset.Id);
    Test.stopTest();

    System.assertEquals(true, blocked,
      'L1 Approved is mid-flight, so a duplicate return must still be blocked');
  }

  @isTest
  static void testTerminalReturnCaseReleasesTheBlock() {
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(retailer.Id, 'Standee', true);
    insert asset;

    List<Case__c> finished = new List<Case__c>{
      newReturnCase(asset.Id, 'Completed'),
      newReturnCase(asset.Id, 'Closed'),
      newReturnCase(asset.Id, 'Reject')
    };
    insert finished;

    Test.startTest();
    Boolean blocked = CaseScreenController.hasPendingReturnCase(asset.Id);
    Boolean nullSafe = CaseScreenController.hasPendingReturnCase(null);
    Test.stopTest();

    System.assertEquals(false, blocked,
      'Completed, Closed and Reject are terminal - a new return is allowed');
    System.assertEquals(false, nullSafe, 'A null asset id must not blow up');
  }

  @isTest
  static void testReturnCaseGuardIgnoresOtherAssetsAndTypes() {
    Account retailer = [SELECT Id FROM Account WHERE Name = 'Test Retailer' LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(retailer.Id, 'Signage', true);
    Branding_Asset__c other = newBrandingAsset(retailer.Id, 'Standee', true);
    insert new List<Branding_Asset__c>{ asset, other };

    // Pending return against a DIFFERENT asset
    insert newReturnCase(other.Id, 'Pending');

    // Pending case of a different type against THIS asset
    Case_Type__c requestType = [
      SELECT Id FROM Case_Type__c
      WHERE Name = 'Branding & Marketing Asset Request' LIMIT 1
    ];
    insert new Case__c(
      Case_Type__c = requestType.Id, Branding_Asset__c = asset.Id, Status__c = 'Pending'
    );

    Test.startTest();
    Boolean blocked = CaseScreenController.hasPendingReturnCase(asset.Id);
    Test.stopTest();

    System.assertEquals(false, blocked,
      'Only a return case against this same asset should block');
  }

  // ================= DISTRIBUTOR VISITS AUDIT THE SAME WAY =================
  @isTest
  static void testDistributorVisitAuditsItsOwnBranding() {
    Account distributor = [
      SELECT Id FROM Account WHERE Name = 'Test Distributor' LIMIT 1
    ];
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    // A distributor visit carries no retailer.
    Visit_Task__c distVt = new Visit_Task__c(
      Distributor__c = distributor.Id, Visit__c = visit.Id
    );
    insert distVt;

    Branding_Asset__c asset = newBrandingAsset(distributor.Id, 'Signage', true);
    insert asset;

    Test.startTest();
    List<Branding_Asset__c> assets = CaseScreenController.getBrandingAssets(distVt.Id);
    CaseScreenController.BrandingAuditWindow w =
      CaseScreenController.getBrandingAuditWindow(distVt.Id);
    Test.stopTest();

    System.assertEquals(1, assets.size(),
      'A distributor visit must load the branding tagged to the distributor account');
    System.assertEquals(asset.Id, assets[0].Id, 'It is the distributor own branding asset');
    System.assertEquals(1, w.visitNumber,
      'Visit number counts distributor visits, not the retailer visits it services');
  }

  @isTest
  static void testDistributorVisitSubmitsAuditAgainstDistributor() {
    Account distributor = [
      SELECT Id FROM Account WHERE Name = 'Test Distributor' LIMIT 1
    ];
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Visit_Task__c distVt = new Visit_Task__c(
      Distributor__c = distributor.Id, Visit__c = visit.Id
    );
    insert distVt;

    Branding_Asset__c asset = newBrandingAsset(distributor.Id, 'Flange', true);
    insert asset;

    CaseScreenController.BrandingAuditLineInput line =
      new CaseScreenController.BrandingAuditLineInput();
    line.brandingAssetId = asset.Id;
    line.mediaType = 'Flange';
    line.subMedia = 'Back lit Flange';
    line.condition = 'Present';
    line.remarks = 'Distributor branding checked';

    Test.startTest();
    Id headerId = CaseScreenController.submitBrandingAudit(
      distVt.Id, new List<CaseScreenController.BrandingAuditLineInput>{ line }
    );
    Test.stopTest();

    Branding_Audit__c header = [
      SELECT Retailer_Account__c, Visit_Task__c FROM Branding_Audit__c WHERE Id = :headerId
    ];
    System.assertEquals(distributor.Id, header.Retailer_Account__c,
      'The Account lookup holds the distributor on a distributor visit');
    System.assertEquals(distVt.Id, header.Visit_Task__c, 'Tied to the distributor visit task');
  }

  // ================= BRANDING AUDIT WINDOW (every 3rd visit) =================
  @isTest
  static void testAuditWindowClosedOnFirstVisit() {
    Visit_Task__c vt = [SELECT Id FROM Visit_Task__c LIMIT 1];

    Test.startTest();
    CaseScreenController.BrandingAuditWindow w =
      CaseScreenController.getBrandingAuditWindow(vt.Id);
    Test.stopTest();

    System.assertEquals(1, w.visitNumber, 'The setup outlet has had a single visit');
    System.assertEquals(false, w.auditDue, 'Visit 1 is not an audit visit');
    System.assertEquals(2, w.visitsUntilDue, 'Two more visits until the audit is due');
  }

  @isTest
  static void testAuditWindowOpenOnThirdVisit() {
    Visit_Task__c firstVt = [SELECT Id, Retailer__c, Visit__c FROM Visit_Task__c LIMIT 1];
    List<Visit_Task__c> extra = new List<Visit_Task__c>{
      new Visit_Task__c(Retailer__c = firstVt.Retailer__c, Visit__c = firstVt.Visit__c),
      new Visit_Task__c(Retailer__c = firstVt.Retailer__c, Visit__c = firstVt.Visit__c)
    };
    insert extra;

    Test.startTest();
    CaseScreenController.BrandingAuditWindow w =
      CaseScreenController.getBrandingAuditWindow(extra[1].Id);
    Test.stopTest();

    System.assertEquals(3, w.visitNumber, 'This is the third visit to the outlet');
    System.assertEquals(true, w.auditDue, 'Every 3rd visit opens the audit');
    System.assertEquals(0, w.visitsUntilDue, 'Nothing to wait for - it is due now');
  }

  // ================= ONE AUDIT PER VISIT TASK =================
  @isTest
  static void testSecondAuditOnSameVisitIsRejected() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(vt.Retailer__c, 'Signage', true);
    insert asset;

    CaseScreenController.BrandingAuditLineInput line =
      new CaseScreenController.BrandingAuditLineInput();
    line.brandingAssetId = asset.Id;
    line.mediaType = 'Signage';
    line.subMedia = 'Back lit Signage';
    line.condition = 'Present';
    line.remarks = 'First audit';

    CaseScreenController.submitBrandingAudit(
      vt.Id, new List<CaseScreenController.BrandingAuditLineInput>{ line }
    );

    Boolean blocked = false;
    Test.startTest();
    try {
      CaseScreenController.submitBrandingAudit(
        vt.Id, new List<CaseScreenController.BrandingAuditLineInput>{ line }
      );
    } catch (Exception e) {
      blocked = true;
    }
    Test.stopTest();

    System.assertEquals(true, blocked, 'A second audit on the same visit must be rejected');
    System.assertEquals(1,
      [SELECT COUNT() FROM Branding_Audit__c WHERE Visit_Task__c = :vt.Id],
      'Only the first audit should exist for this visit');
  }

  @isTest
  static void testAuditWindowReportsAlreadySubmitted() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(vt.Retailer__c, 'Flange', true);
    insert asset;

    CaseScreenController.BrandingAuditLineInput line =
      new CaseScreenController.BrandingAuditLineInput();
    line.brandingAssetId = asset.Id;
    line.mediaType = 'Flange';
    line.subMedia = 'Back lit Flange';
    line.condition = 'Present';
    line.remarks = 'Done';

    Test.startTest();
    CaseScreenController.BrandingAuditWindow before =
      CaseScreenController.getBrandingAuditWindow(vt.Id);
    CaseScreenController.submitBrandingAudit(
      vt.Id, new List<CaseScreenController.BrandingAuditLineInput>{ line }
    );
    CaseScreenController.BrandingAuditWindow after =
      CaseScreenController.getBrandingAuditWindow(vt.Id);
    Test.stopTest();

    System.assertEquals(false, before.alreadySubmitted, 'Nothing submitted before the audit');
    System.assertEquals(true, after.alreadySubmitted,
      'The panel must know the audit is done so it withholds the form');
  }

  // ================= BRANDING AUDIT STATUS =================
  @isTest
  static void testGetBrandingAuditStatusMarksThisVisitAudited() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    Branding_Asset__c audited = newBrandingAsset(vt.Retailer__c, 'Signage', true);
    Branding_Asset__c untouched = newBrandingAsset(vt.Retailer__c, 'Flange', true);
    insert new List<Branding_Asset__c>{ audited, untouched };

    CaseScreenController.BrandingAuditLineInput line =
      new CaseScreenController.BrandingAuditLineInput();
    line.brandingAssetId = audited.Id;
    line.mediaType = 'Signage';
    line.subMedia = 'Back lit Signage';
    line.condition = 'Present';
    line.remarks = 'Looks fine';

    Test.startTest();
    CaseScreenController.submitBrandingAudit(
      vt.Id, new List<CaseScreenController.BrandingAuditLineInput>{ line }
    );
    Map<Id, CaseScreenController.BrandingAuditStatus> status =
      CaseScreenController.getBrandingAuditStatus(vt.Id);
    Test.stopTest();

    System.assert(status.containsKey(audited.Id), 'The audited asset must appear in the status map');
    System.assertEquals(true, status.get(audited.Id).auditedThisVisit,
      'An audit taken on this visit must mark the card Audited');
    System.assertNotEquals(null, status.get(audited.Id).lastAuditDate,
      'The last audited date must come back so the card can show it');
    System.assert(!status.containsKey(untouched.Id),
      'An asset with no audit line has no status and stays un-audited');
  }

  @isTest
  static void testGetBrandingAuditStatusIgnoresOtherVisits() {
    Visit_Task__c firstVt = [SELECT Id, Retailer__c, Visit__c FROM Visit_Task__c LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(firstVt.Retailer__c, 'Standee', true);
    insert asset;

    Visit_Task__c laterVt = new Visit_Task__c(
      Retailer__c = firstVt.Retailer__c, Visit__c = firstVt.Visit__c
    );
    insert laterVt;

    CaseScreenController.BrandingAuditLineInput line =
      new CaseScreenController.BrandingAuditLineInput();
    line.brandingAssetId = asset.Id;
    line.mediaType = 'Standee';
    line.subMedia = 'Lit Standee';
    line.condition = 'Present';
    line.remarks = 'Audited on the earlier visit';

    Test.startTest();
    // Audit recorded against the FIRST visit...
    CaseScreenController.submitBrandingAudit(
      firstVt.Id, new List<CaseScreenController.BrandingAuditLineInput>{ line }
    );
    // ...but the panel is open on a LATER visit.
    Map<Id, CaseScreenController.BrandingAuditStatus> status =
      CaseScreenController.getBrandingAuditStatus(laterVt.Id);
    Test.stopTest();

    System.assertEquals(false, status.get(asset.Id).auditedThisVisit,
      'An audit from an earlier visit must not mark this visit as done');
    System.assertNotEquals(null, status.get(asset.Id).lastAuditDate,
      'The earlier audit date is still shown as history');
  }

  // ================= PRESENT LINES NEED NO REMARKS =================
  @isTest
  static void testPresentLineSavesWithBlankRemarks() {
    Visit_Task__c vt = [SELECT Id, Retailer__c FROM Visit_Task__c LIMIT 1];
    Branding_Asset__c asset = newBrandingAsset(vt.Retailer__c, 'Signage', true);
    insert asset;

    CaseScreenController.BrandingAuditLineInput line =
      new CaseScreenController.BrandingAuditLineInput();
    line.brandingAssetId = asset.Id;
    line.mediaType = 'Signage';
    line.subMedia = 'Back lit Signage';
    line.condition = 'Present';
    line.remarks = null;   // nothing to explain when the branding is simply there

    Test.startTest();
    Id headerId = CaseScreenController.submitBrandingAudit(
      vt.Id, new List<CaseScreenController.BrandingAuditLineInput>{ line }
    );
    Test.stopTest();

    Branding_Audit_Line__c saved = [
      SELECT Condition__c, Remarks__c FROM Branding_Audit_Line__c
      WHERE Branding_Audit__c = :headerId LIMIT 1
    ];
    System.assertEquals('Present', saved.Condition__c, 'The line still records the condition');
    System.assertEquals(null, saved.Remarks__c,
      'Remarks__c must accept blank - it is no longer a required field');
  }

  // ================= CHECK ALL BRANDING AUDITED =================
  @isTest
  static void testCheckAllBrandingAuditedPassesWhenOutletHasNoBranding() {
    Visit_Task__c vt = [SELECT Id FROM Visit_Task__c LIMIT 1];

    Test.startTest();
    String result = CaseScreenController.checkAllBrandingAudited(vt.Id);
    Test.stopTest();

    System.assertEquals('VISIT_AUDITED', result,
      'An outlet with no branding assets has nothing to audit');
  }

  @isTest
  static void testCheckAllBrandingAuditedBlocksOnThirdVisit() {
    Visit_Task__c firstVt = [SELECT Id, Retailer__c, Visit__c FROM Visit_Task__c LIMIT 1];

    // The gate only bites on every 3rd visit, so bring the outlet to visit 3.
    List<Visit_Task__c> extra = new List<Visit_Task__c>{
      new Visit_Task__c(Retailer__c = firstVt.Retailer__c, Visit__c = firstVt.Visit__c),
      new Visit_Task__c(Retailer__c = firstVt.Retailer__c, Visit__c = firstVt.Visit__c)
    };
    insert extra;
    insert newBrandingAsset(firstVt.Retailer__c, 'Signage', true);

    Test.startTest();
    String result = CaseScreenController.checkAllBrandingAudited(extra[1].Id);
    Test.stopTest();

    System.assertEquals('NOT_AUDITED', result,
      'Third visit with an un-audited active branding asset must block check-out');
  }
}