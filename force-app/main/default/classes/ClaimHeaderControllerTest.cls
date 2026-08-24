/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClaimHeaderControllerTest
 * Author          : <YourName>
 * Created Date    : Mar 23, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Mar 23, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 23, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@isTest
public class ClaimHeaderControllerTest {

    @testSetup
    static void setupData() {
          Id accrt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Distributor').getRecordTypeId();

        // Create Active Account
        Account acc = new Account(
            Name = 'Test Distributor',
            Code__c = 'ACC001',
            Status__c = 'Active',
             RecordTypeId = accrt
        );
        insert acc;
        
        Account accTest = new Account(
            Name = 'Test Distributor1',
            Code__c = 'ACC002',
            Status__c = 'Active',
             RecordTypeId = accrt
        );
        insert accTest;

        // Create Case Type RecordType
        Id rt = Schema.SObjectType.Case_Type__c.getRecordTypeInfosByDeveloperName().get('Claim').getRecordTypeId();

        // Create Case Type
        Case_Type__c ct = new Case_Type__c(
            Name = 'Test Claim Type',
            RecordTypeId = rt,
            Active__c = true
            
        );
        insert ct;
        
        

        // Create a user (non-portal)
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@hangyo.com',
            Username = 'testuser' + DateTime.now().getTime() + '@test.com',
            Alias = 'tstusr',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;
    }

    @isTest
    static void testGetMultiplePicklistValues() {
        Test.startTest();
        Map<String, List<getPicklistHelper.PicklistOption>> res = ClaimHeaderController.getMultiplePicklistValues();
        Test.stopTest();
    }

    @isTest
    static void testGetAccountsAndCaseTypesMap() {
        Test.startTest();
        Map<String, List<Object>> res = ClaimHeaderController.getAccountsAndCaseTypesMap();
        Test.stopTest();
    }

    @isTest
    static void testCreateClaimWithAttachment_success() {
        // Prepare Base64 file
        Blob bodyBlob = Blob.valueOf('Test File');
        String base64Data = EncodingUtil.base64Encode(bodyBlob);

        // Build request data
        Map<String, Object> header = new Map<String, Object>{
            'distributorId' => [SELECT Id FROM Account Where Name = 'Test Distributor' LIMIT 1 ].Id,
            'claimMonth' => 'March',
            'claimYear' => '2025',
            'claimDescription' => 'Test claim desc',
            'submittedDate' => String.valueOf(Date.today()),
            'claimStatus' => 'Draft'
        };

        List<Object> lines = new List<Object>();
        lines.add(new Map<String, Object>{
            'lineId' => 'frontend-1',
            'caseTypeId' => [SELECT Id FROM Case_Type__c LIMIT 1 ].Id,
            'amount' => '1000',
            'date' => String.valueOf(Date.today()),
            'remarks' => 'Test remark',
            'files' => new List<Object>{
                new Map<String,Object>{
                    'base64' => base64Data,
                    'name' => 'testFile.txt'
                }
            }
        });

        Map<String, Object> request = new Map<String, Object>{
            'header' => header,
            'lines' => lines
        };

        Test.startTest();
        Map<String,String> response = ClaimHeaderController.createClaimWithAttachment(JSON.serialize(request));
        Test.stopTest();

       
    }
    @isTest
    static void testCreateClaimWithAttachment_success1() {
        // Prepare Base64 file
        Blob bodyBlob = Blob.valueOf('Test File');
        String base64Data = EncodingUtil.base64Encode(bodyBlob);
        
     Account acc = [SELECT Id, Name FROM Account Where Name = 'Test Distributor1' LIMIT 1];
        Claim_Header__c ch = new Claim_Header__c(
            Distributor__c = acc.Id,
            Month__c = 'March',
            Year__c = '2025',
            Status__c = 'Draft'
        );
        insert ch;
        // Build request data
        Map<String, Object> header = new Map<String, Object>{
            'distributorId' => acc.Id,
            'claimMonth' => 'March',
            'claimYear' => '2025',
            'claimDescription' => 'Test claim desc',
            'submittedDate' => String.valueOf(Date.today()),
            'claimStatus' => 'Draft'
        };

        List<Object> lines = new List<Object>();
        lines.add(new Map<String, Object>{
            'lineId' => 'frontend-1',
            'caseTypeId' => [SELECT Id FROM Case_Type__c LIMIT 1 ].Id,
            'amount' => '1000',
            'date' => String.valueOf(Date.today()),
            'remarks' => 'Test remark',
            'files' => new List<Object>{
                new Map<String,Object>{
                    'base64' => base64Data,
                    'name' => 'testFile.txt'
                }
            }
        });
        
        Map<String, Object> request = new Map<String, Object>{
            'header' => header,
            'lines' => lines
        };

        Test.startTest();
        Map<String,String> response = ClaimHeaderController.createClaimWithAttachment(JSON.serialize(request));
        Test.stopTest();

       
    }

    @isTest
    static void testCreateClaimWithAttachment_success2() {
        // Prepare Base64 file
        Blob bodyBlob = Blob.valueOf('Test File');
        String base64Data = EncodingUtil.base64Encode(bodyBlob);
        
     Account acc = [SELECT Id, Name FROM Account Where Name = 'Test Distributor1' LIMIT 1];
        Claim_Header__c ch = new Claim_Header__c(
            Distributor__c = acc.Id,
            Month__c = 'March',
            Year__c = '2025',
            Status__c = 'Approved'
        );
        insert ch;
        // Build request data
        Map<String, Object> header = new Map<String, Object>{
            'distributorId' => acc.Id,
            'claimMonth' => 'March',
            'claimYear' => '2025',
            'claimDescription' => 'Test claim desc',
            'submittedDate' => String.valueOf(Date.today()),
            'claimStatus' => 'Draft'
        };

        List<Object> lines = new List<Object>();
        lines.add(new Map<String, Object>{
            'lineId' => 'frontend-1',
            'caseTypeId' => [SELECT Id FROM Case_Type__c LIMIT 1 ].Id,
            'amount' => '1000',
            'date' => String.valueOf(Date.today()),
            'remarks' => 'Test remark',
            'files' => new List<Object>{
                new Map<String,Object>{
                    'base64' => base64Data,
                    'name' => 'testFile.txt'
                }
            }
        });
        
        Map<String, Object> request = new Map<String, Object>{
            'header' => header,
            'lines' => lines
        };

        Test.startTest();
        Map<String,String> response = ClaimHeaderController.createClaimWithAttachment(JSON.serialize(request));
        Test.stopTest();

       
    }

    @isTest
    static void testCreateClaimWithAttachment_error() {
        // Invalid request (missing caseTypeId and files)
        Map<String, Object> header = new Map<String, Object>{
            'distributorId' => [SELECT Id FROM Account LIMIT 1].Id,
            'claimMonth' => 'March',
            'claimYear' => '2025',
            'claimDescription' => 'Invalid claim',
            'claimStatus' => 'Draft'
        };

        List<Object> lines = new List<Object>();
        lines.add(new Map<String, Object>{
            'lineId' => 'frontend-2',
            'amount' => '2000',
            'remarks' => 'Missing caseTypeId',
            'files' => new List<Object>() // Empty files
        });

        Map<String, Object> request = new Map<String, Object>{
            'header' => header,
            'lines' => lines
        };

        Test.startTest();
        Map<String,String> response = ClaimHeaderController.createClaimWithAttachment(JSON.serialize(request));
        Test.stopTest();

        
    }
    
    @isTest
static void testIsClaimHeaderApproved() {

    Account acc = [
        SELECT Id
        FROM Account
        WHERE Name = 'Test Distributor1'
        LIMIT 1
    ];

    Claim_Header__c ch = new Claim_Header__c(
        Distributor__c = acc.Id,
        Month__c = 'June',
        Year__c = '2025',
        Status__c = 'Approved'
    );
    insert ch;

    Test.startTest();
    Boolean result = ClaimHeaderController.isClaimHeaderApproved(
        acc.Id,
        'June',
        '2025'
    );
    Test.stopTest();

    System.assertEquals(true, result);
}
    
    
}