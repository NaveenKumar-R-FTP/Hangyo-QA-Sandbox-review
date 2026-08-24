@isTest
public class ClaimHeaderPDFController_Test {
    
    @testSetup
    static void setupData() {
        // Create test Distributor (Account)
         Id accrt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Distributor').getRecordTypeId();
        Account acc = new Account( 
            Name = 'Test Distributor',
            BillingCity = 'Mumbai',
            BillingState = 'Maharashtra',
            RecordTypeId = accrt
        );
        insert acc;

        // Create Claim Header
        Claim_Header__c claimHeader = new Claim_Header__c(
            Distributor__c = acc.Id,
            Month__c = 'January',
            Year__c = '2025',
            Approved_Amount__c = 5000,
            Claim_Action_Date__c = Date.newInstance(2025, 1, 10),
            
            Submitted_date__c = Date.newInstance(2025, 1, 2),
            SO_Approved_Date__c = Date.newInstance(2025, 1, 3),
            RSM_Approved_Date__c = Date.newInstance(2025, 1, 4),
            ASM_Approved_Date__c = Date.newInstance(2025, 1, 5),
            MIS_Approved_Date__c = Date.newInstance(2025, 1, 6),
            ZSM_Approved_Date__c = Date.newInstance(2025, 1, 7),
            Head_Approved_Date__c = Date.newInstance(2025, 1, 8)
        );
        insert claimHeader;

        // ✅ Record Type for Case_Type__c
        Id recordTypeId;
        try {
            recordTypeId = Schema.SObjectType.Case_Type__c
                .getRecordTypeInfosByDeveloperName()
                .get('Claim').getRecordTypeId();
        } catch (Exception e) {
            recordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Case_Type__c' LIMIT 1].Id;
        }

        // Create Claim Types
        Case_Type__c typeA = new Case_Type__c(
            Name = 'Discount Claim',
            RecordTypeId = recordTypeId
        );
        Case_Type__c typeB = new Case_Type__c(
            Name = 'Marketing Claim',
            RecordTypeId = recordTypeId
        );
        insert new List<Case_Type__c>{ typeA, typeB };

        // Create Claim Line Items
        List<Claim_Line_Item__c> lineItems = new List<Claim_Line_Item__c>{
            new Claim_Line_Item__c(
                Claim__c = claimHeader.Id,
                Case_Type__c = typeA.Id,
                Amount__c = 1000,
                Remark__c = 'Discount offer',
                Claim_Date__c = Date.newInstance(2025, 1, 1)
            ),
            new Claim_Line_Item__c(
                Claim__c = claimHeader.Id,
                Case_Type__c = typeB.Id,
                Amount__c = 4000,
                Remark__c = 'Marketing campaign',
                Claim_Date__c = Date.newInstance(2025, 1, 5)
            )
        };
        insert lineItems;

        // Create Visualforce PDF config record
        Visualforce_PDF__c pdfCfg = new Visualforce_PDF__c(
            Name = 'claimheaderpdf',
            PDF_Url__c = 'https://example.com/ClaimPDF'
        );
        insert pdfCfg;
    }

    @isTest
    static void testControllerLogic() {
        // Get Claim Header Id
        Id claimId = [SELECT Id FROM Claim_Header__c LIMIT 1].Id;

        Test.startTest();
        PageReference pageRef = Page.ClaimPDFVFpage; 
        pageRef.getParameters().put('id', claimId); 
        Test.setCurrentPage(pageRef);

        // Instantiate controller
        ClaimHeaderPDFController controller = new ClaimHeaderPDFController();
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, controller.claimWrapper);
        System.assertNotEquals(null, controller.claimWrapper.claimHeader);
        System.assertNotEquals(0, controller.claimWrapper.aggregatedLineItems.size());

        Boolean foundDiscount = false;
        for (ClaimHeaderPDFController.AggregatedLineItem item : controller.claimWrapper.aggregatedLineItems) {
            if (item.typeName == 'Discount Claim') {
                foundDiscount = true;
                System.assertEquals(1000, item.total);
                System.assertEquals('Discount offer', item.remark);
            }
        }
        System.assert(foundDiscount);
    }

    @isTest
    static void testGetInvoicePdfUrl() {
        Test.startTest();
        String pdfUrl = ClaimHeaderPDFController.getInvoicePdfUrl();
        Test.stopTest();

        System.assertNotEquals(null, pdfUrl);
        System.assert(pdfUrl.contains('https://example.com'));
    }
}