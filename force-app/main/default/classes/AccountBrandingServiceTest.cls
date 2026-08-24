@isTest
public class AccountBrandingServiceTest {

    private static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(developerName).getRecordTypeId();
    }

    private static Account newRetailer(String name, String code) {
        return new Account(
            Name = name, BillingCity = 'Mumbai', BillingState = 'Maharashtra',
            RecordTypeId = recordTypeId('Retailer'), Retailer_Code__c = code
        );
    }

    @testSetup
    static void setupData() {
        insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
    }

    // ================= DEEP FREEZER DRIVES BRANDING =================
    @isTest
    static void testFreezerBrandsThenUnbrandsOnDeactivate() {
        Account retailer = newRetailer('Freezer Retailer', 'SF920001');
        insert retailer;

        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPLAB001');
        insert master;

        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = retailer.Id,
            External_ID__c = 'AB-EXT-001', Active__c = true, Allocation_Start_Date__c = Date.today()
        );
        insert mapping;

        System.assertEquals(true,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'An active freezer should brand the retailer');

        Test.startTest();
        mapping.Active__c = false;
        update mapping;
        Test.stopTest();

        System.assertEquals(false,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'Removing the only freezer should clear branding');
    }

    // ================= BRANDING MATERIAL DRIVES BRANDING =================
    @isTest
    static void testBrandingAssetBrandsThenUnbronsOnDeactivate() {
        Account retailer = newRetailer('Poster Retailer', 'SF920002');
        insert retailer;

        Branding_Asset__c poster = new Branding_Asset__c(
            Account__c = retailer.Id, Asset_Name__c = 'Glow Sign',
            Quantity__c = 2, Installed_Date__c = Date.today(), Active__c = true
        );
        insert poster;

        System.assertEquals(true,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'Active branding material should brand the retailer with no freezer present');

        Test.startTest();
        poster.Active__c = false;
        update poster;
        Test.stopTest();

        System.assertEquals(false,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'Removing the branding material should clear branding');
    }

    // ================= EITHER SOURCE KEEPS IT BRANDED =================
    @isTest
    static void testFreezerRemovedButBrandingMaterialRemains() {
        Account retailer = newRetailer('Both Sources Retailer', 'SF920003');
        insert retailer;

        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPLAB002');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = retailer.Id,
            External_ID__c = 'AB-EXT-002', Active__c = true, Allocation_Start_Date__c = Date.today()
        );
        insert mapping;

        insert new Branding_Asset__c(
            Account__c = retailer.Id, Asset_Name__c = 'Danglers',
            Quantity__c = 10, Installed_Date__c = Date.today(), Active__c = true
        );

        Test.startTest();
        // Freezer goes away, signage stays put.
        mapping.Active__c = false;
        update mapping;
        Test.stopTest();

        System.assertEquals(true,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'Branding must survive freezer removal while signage is still active');
    }

    @isTest
    static void testDeletingBrandingAssetClearsFlag() {
        Account retailer = newRetailer('Delete Retailer', 'SF920004');
        insert retailer;

        Branding_Asset__c poster = new Branding_Asset__c(
            Account__c = retailer.Id, Asset_Name__c = 'Wall Paint',
            Quantity__c = 1, Installed_Date__c = Date.today(), Active__c = true
        );
        insert poster;
        System.assertEquals(true,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c);

        Test.startTest();
        delete poster;
        Test.stopTest();

        System.assertEquals(false,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'Deleting the last branding asset should clear the flag');
    }

    // ================= BACKFILL =================
    @isTest
    static void testBackfillBatchCorrectsBothDirections() {
        Account shouldBrand = newRetailer('Should Become Branded', 'SF920005');
        Account shouldClear = newRetailer('Wrongly Branded', 'SF920006');
        insert new List<Account>{ shouldBrand, shouldClear };

        insert new Branding_Asset__c(
            Account__c = shouldBrand.Id, Asset_Name__c = 'Signage',
            Quantity__c = 1, Installed_Date__c = Date.today(), Active__c = true
        );

        // Simulate bad historic data: branded with nothing backing it, and an
        // account that owns material but was never flagged.
        update new List<Account>{
            new Account(Id = shouldBrand.Id, Is_Branded__c = false),
            new Account(Id = shouldClear.Id, Is_Branded__c = true)
        };

        Test.startTest();
        Database.executeBatch(new AccountBrandedBackfillBatch(), 200);
        Test.stopTest();

        System.assertEquals(true,
            [SELECT Is_Branded__c FROM Account WHERE Id = :shouldBrand.Id].Is_Branded__c,
            'Account holding branding material should be branded');
        System.assertEquals(false,
            [SELECT Is_Branded__c FROM Account WHERE Id = :shouldClear.Id].Is_Branded__c,
            'Account with nothing installed should be cleared');
    }

    // ================= CASE -> INSTALLED CREATES BRANDING ASSETS =================
    @isTest
    static void testInstalledBrandingCaseCreatesBrandingAssets() {
        Account retailer = newRetailer('Case Install Retailer', 'SF920010');
        insert retailer;

        Case_Type__c ct = new Case_Type__c(
            Name = 'Branding & Marketing Asset Request', Type__c = 'Case', Active__c = true
        );
        insert ct;

        // This is the real shape of a branding request: one asset described by
        // Media Type + Media Sub Type + Quantity.
        Case__c c = new Case__c(
            Case_Type__c = ct.Id,
            Retailer__c = retailer.Id,
            Status__c = 'Installation Pending',
            Media_Type__c = 'Standee',
            Media_Sub_type__c = 'ACP/LE Signage',
            Quantity__c = 3
        );
        insert c;

        System.assertEquals(0, [SELECT COUNT() FROM Branding_Asset__c WHERE Account__c = :retailer.Id],
            'Nothing should exist before the case is installed');

        Test.startTest();
        c.Status__c = 'Installed';
        update c;
        Test.stopTest();

        List<Branding_Asset__c> created = [
            SELECT Asset_Name__c, Media_Type__c, Media_Sub_Type__c, Quantity__c,
                   Active__c, Branding_Case__c, Installed_Date__c
            FROM Branding_Asset__c WHERE Account__c = :retailer.Id
        ];

        System.assertEquals(1, created.size(), 'One Branding Asset per branding request');
        Branding_Asset__c ba = created[0];
        System.assertEquals('Standee - ACP/LE Signage', ba.Asset_Name__c,
            'Display name combines media type and sub type');
        System.assertEquals('Standee', ba.Media_Type__c);
        System.assertEquals('ACP/LE Signage', ba.Media_Sub_Type__c);
        System.assertEquals(3, ba.Quantity__c);
        System.assertEquals(c.Id, ba.Branding_Case__c,
            'Branding asset should trace back to the case that delivered it');
        System.assertEquals(Date.today(), ba.Installed_Date__c);
        System.assertEquals(true, ba.Active__c);

        System.assertEquals(true,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'Installing branding material should brand the retailer');
    }

    // ================= RETURN CASE RETIRES THE ASSET =================
    @isTest
    static void testCompletedReturnCaseDeactivatesBrandingAsset() {
        Account retailer = newRetailer('Return Retailer', 'SF920020');
        insert retailer;

        Case_Type__c returnType = new Case_Type__c(
            Name = 'Branding & Marketing Asset transfer Request', Type__c = 'Case', Active__c = true
        );
        insert returnType;

        // Two assets on the outlet - only the returned one should be retired.
        Branding_Asset__c returned = new Branding_Asset__c(
            Account__c = retailer.Id, Active__c = true,
            Media_Type__c = 'Signage', Media_Sub_Type__c = 'Back lit Signage'
        );
        Branding_Asset__c untouched = new Branding_Asset__c(
            Account__c = retailer.Id, Active__c = true,
            Media_Type__c = 'Standee', Media_Sub_Type__c = 'Lit Standee'
        );
        insert new List<Branding_Asset__c>{ returned, untouched };

        Vendor__c vendor = new Vendor__c(Name = 'Return Vendor', Hub__c = 'Goa');
        insert vendor;

        Case__c c = new Case__c(
            Case_Type__c              = returnType.Id,
            Retailer__c               = retailer.Id,
            Branding_Asset__c         = returned.Id,
            Condition__c              = 'Damaged',
            Vendor__c                 = vendor.Id,
            Branding_Return_Status__c = 'Consumed',
            Status__c                 = 'L1 Approved'
        );
        insert c;

        System.assertEquals(true,
            [SELECT Active__c FROM Branding_Asset__c WHERE Id = :returned.Id].Active__c,
            'Still active while the return is in flight');

        Test.startTest();
        c.Status__c = 'Completed';
        update c;
        Test.stopTest();

        System.assertEquals(false,
            [SELECT Active__c FROM Branding_Asset__c WHERE Id = :returned.Id].Active__c,
            'Completing the return must retire the branding asset');
        System.assertEquals(true,
            [SELECT Active__c FROM Branding_Asset__c WHERE Id = :untouched.Id].Active__c,
            'Other branding on the outlet must be left alone');
        System.assertNotEquals(null,
            [SELECT Account__c FROM Branding_Asset__c WHERE Id = :returned.Id].Account__c,
            'Account__c is kept so the record still shows which outlet held it');
        System.assertEquals(true,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'The outlet keeps its branded flag while other active branding remains');
    }

    @isTest
    static void testCompletedNonReturnCaseLeavesAssetsAlone() {
        Account retailer = newRetailer('Other Case Retailer', 'SF920021');
        insert retailer;

        Case_Type__c otherType = new Case_Type__c(
            Name = 'Asset Complaint Request', Type__c = 'Case', Active__c = true
        );
        insert otherType;

        Branding_Asset__c asset = new Branding_Asset__c(
            Account__c = retailer.Id, Active__c = true, Media_Type__c = 'Flange'
        );
        insert asset;

        Case__c c = new Case__c(
            Case_Type__c = otherType.Id, Retailer__c = retailer.Id,
            Branding_Asset__c = asset.Id, Status__c = 'Open'
        );
        insert c;

        Test.startTest();
        c.Status__c = 'Completed';
        update c;
        Test.stopTest();

        System.assertEquals(true,
            [SELECT Active__c FROM Branding_Asset__c WHERE Id = :asset.Id].Active__c,
            'Only a return case retires the asset');
    }

    @isTest
    static void testInstalledNonBrandingCaseCreatesNothing() {
        Account retailer = newRetailer('Non Branding Retailer', 'SF920011');
        insert retailer;

        Case_Type__c ct = new Case_Type__c(
            Name = 'Asset Complaint Request', Type__c = 'Case', Active__c = true
        );
        insert ct;

        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Retailer__c = retailer.Id,
            Status__c = 'Installation Pending',
            Media_Type__c = 'Standee', Media_Sub_type__c = 'Should Be Ignored'
        );
        insert c;

        Test.startTest();
        c.Status__c = 'Installed';
        update c;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Branding_Asset__c WHERE Account__c = :retailer.Id],
            'Only Branding case types should produce Branding Assets');
        System.assertEquals(false,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'No freezer and no branding material means not branded');
    }

    // ================= INVENTORY MANAGEMENT: MULTI-LINE REQUESTS =================
    private static Case_Type__c inventoryCaseType() {
        Case_Type__c ct = new Case_Type__c(
            Name = 'Branding & Marketing Asset Inventory Management',
            Type__c = 'Case', Active__c = true
        );
        insert ct;

        // Media Type / Sub Type options come from the Branding request form config.
        Case_Type__c requestType = new Case_Type__c(
            Name = 'Branding & Marketing Asset Request', Type__c = 'Case', Active__c = true
        );
        insert requestType;

        Form_Field__c mediaType = new Form_Field__c(
            API_Name__c = 'Media_Type__c', Label__c = 'Media Type', Type__c = 'Picklist',
            Sequence__c = 1, Case_Type__c = requestType.Id, Visible__c = true
        );
        Form_Field__c mediaSubType = new Form_Field__c(
            API_Name__c = 'Media_Sub_type__c', Label__c = 'Media Sub Type', Type__c = 'Picklist',
            Sequence__c = 2, Case_Type__c = requestType.Id, Visible__c = true
        );
        insert new List<Form_Field__c>{ mediaType, mediaSubType };

        insert new List<Form_Field_Picklist__c>{
            new Form_Field_Picklist__c(Form_Field__c = mediaType.Id, Name = 'Standee', Active__c = true),
            new Form_Field_Picklist__c(Form_Field__c = mediaSubType.Id, Name = 'ACP/LE Signage', Active__c = true),
            new Form_Field_Picklist__c(Form_Field__c = mediaSubType.Id, Name = 'Wall Wrap', Active__c = true)
        };
        return ct;
    }

    @isTest
    static void testGetMediaLineOptions() {
        inventoryCaseType();

        Test.startTest();
        Map<String, List<CaseScreenController.PicklistOption>> options =
            CaseScreenController.getMediaLineOptions();
        Test.stopTest();

        System.assertEquals(1, options.get('mediaTypes').size(), 'One media type configured');
        System.assertEquals('Standee', options.get('mediaTypes')[0].label);
        System.assertEquals(2, options.get('mediaSubTypes').size(), 'Two sub types configured');
    }

    /**
     * Branding L1 must be an ASM/RSM, so these tests run as a user who actually has
     * one above them. Setup objects (UserRole/User/PermissionSetAssignment) are
     * inserted first, then everything else runs inside System.runAs to avoid mixed DML.
     */
    private static User subordinateUnderAsm(String suffix) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        UserRole asmRole = new UserRole(Name = 'ASM-Brand-' + suffix, DeveloperName = 'ASM_Brand_' + suffix);
        insert asmRole;

        User manager = new User(
            FirstName = 'ASM', LastName = 'Manager' + suffix, Alias = 'asm' + suffix,
            Email = 'asm' + suffix + '@hangyo.in',
            Username = 'asm' + suffix + System.currentTimeMillis() + '@hangyo.in.test',
            ProfileId = p.Id, UserRoleId = asmRole.Id,
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'Asia/Kolkata'
        );
        insert manager;

        User submitter = new User(
            FirstName = 'SO', LastName = 'Submitter' + suffix, Alias = 'so' + suffix,
            Email = 'so' + suffix + '@hangyo.in',
            Username = 'so' + suffix + System.currentTimeMillis() + '@hangyo.in.test',
            ProfileId = p.Id, ManagerId = manager.Id,
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'Asia/Kolkata'
        );
        insert submitter;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Branding_Asset_Access' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = submitter.Id, PermissionSetId = ps.Id);

        return submitter;
    }

    @isTest
    static void testInventoryCaseCreatesLinesThenBrandingAssets() {
        User submitter = subordinateUnderAsm('Inv');

        System.runAs(submitter) {
        Account retailer = newRetailer('Inventory Retailer', 'SF920020');
        insert retailer;
        Case_Type__c ct = inventoryCaseType();

        Map<String, Object> formData = new Map<String, Object>{
            'Case_Type__c' => ct.Id,
            'Retailer__c' => retailer.Id,
            'Status__c' => 'Open'
        };
        List<Map<String, Object>> lines = new List<Map<String, Object>>{
            new Map<String, Object>{ 'mediaType' => 'Standee', 'mediaSubType' => 'ACP/LE Signage', 'quantity' => 3 },
            new Map<String, Object>{ 'mediaType' => 'Standee', 'mediaSubType' => 'Wall Wrap', 'quantity' => 2 }
        };

        Test.startTest();
        Id caseId = CaseScreenController.saveCaseWithLines(formData, lines);
        Test.stopTest();

        Case__c saved = [SELECT Id, Media_Lines_Summary__c, L1__c, L2__c FROM Case__c WHERE Id = :caseId];
        System.assertEquals('Standee - ACP/LE Signage x3; Standee - Wall Wrap x2',
            saved.Media_Lines_Summary__c,
            'Summary must flatten every line - approval pages cannot show child records');
        System.assertNotEquals(null, saved.L2__c, 'Mahesh should be set as the second approver');

        List<Case_Media_Line__c> savedLines = [
            SELECT Media_Type__c, Media_Sub_Type__c, Quantity__c
            FROM Case_Media_Line__c WHERE Case__c = :caseId ORDER BY Media_Sub_Type__c
        ];
        System.assertEquals(2, savedLines.size(), 'One child line per requested item');
        System.assertEquals('ACP/LE Signage', savedLines[0].Media_Sub_Type__c);
        System.assertEquals(3, savedLines[0].Quantity__c);

        // Reaching Installed should turn each line into a Branding Asset on the store.
        update new Case__c(Id = caseId, Status__c = 'Installed');

        List<Branding_Asset__c> assets = [
            SELECT Asset_Name__c, Media_Type__c, Media_Sub_Type__c, Quantity__c, Active__c
            FROM Branding_Asset__c WHERE Account__c = :retailer.Id ORDER BY Media_Sub_Type__c
        ];
        System.assertEquals(2, assets.size(), 'One Branding Asset per media line');
        System.assertEquals('Standee - ACP/LE Signage', assets[0].Asset_Name__c);
        System.assertEquals(3, assets[0].Quantity__c);
        System.assertEquals(true, assets[0].Active__c);

        System.assertEquals(true,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'Installing inventory media should brand the store');
        }
    }

    @isTest
    static void testBrandingL1MustBeAsmOrRsm() {
        // Admin has no ASM/RSM above them, so submission must be refused rather
        // than silently routing to the wrong level.
        Account retailer = newRetailer('No Chain Retailer', 'SF920022');
        insert retailer;
        Case_Type__c ct = inventoryCaseType();

        Boolean threw = false;
        String message = '';
        Test.startTest();
        try {
            CaseScreenController.saveCaseWithLines(
                new Map<String, Object>{
                    'Case_Type__c' => ct.Id, 'Retailer__c' => retailer.Id, 'Status__c' => 'Open'
                },
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'mediaType' => 'Standee',
                        'mediaSubType' => 'Wall Wrap', 'quantity' => 1 }
                }
            );
        } catch (Exception e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(threw, 'A submitter with no ASM/RSM above them must be blocked');
    }

    @isTest
    static void testInventoryCaseRequiresAtLeastOneLine() {
        Account retailer = newRetailer('No Lines Retailer', 'SF920021');
        insert retailer;
        Case_Type__c ct = inventoryCaseType();

        Boolean threw = false;
        Test.startTest();
        try {
            CaseScreenController.saveCaseWithLines(
                new Map<String, Object>{ 'Case_Type__c' => ct.Id, 'Retailer__c' => retailer.Id },
                new List<Map<String, Object>>()
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Submitting with no media lines must be rejected');
    }

    /**
     * The 90-day duplicate warning used to be gated on Retailer__c, so a request
     * raised against a DISTRIBUTOR never produced one and its approvers saw
     * nothing on the approval page.
     */
    @isTest
    static void testDuplicateWarningForDistributorRequest() {
        User submitter = subordinateUnderAsm('Dist');

        System.runAs(submitter) {
            Account distributor = new Account(
                Name = 'Warning Distributor', BillingCity = 'Mumbai', BillingState = 'Maharashtra',
                RecordTypeId = recordTypeId('Distributor')
            );
            insert distributor;

            Case_Type__c ct = new Case_Type__c(
                Name = 'Branding & Marketing Asset Request', Type__c = 'Case', Active__c = true
            );
            insert ct;

            // An earlier request against the same distributor, inside the 90 days.
            insert new Case__c(
                Case_Type__c = ct.Id, Distributor__c = distributor.Id, Status__c = 'Open',
                Media_Type__c = 'Standee', Media_Sub_type__c = 'ACP/LE Signage', Quantity__c = 1
            );

            Test.startTest();
            Id secondId = CaseScreenController.saveCase(new Map<String, Object>{
                'Case_Type__c'      => ct.Id,
                'Distributor__c'    => distributor.Id,
                'Status__c'         => 'Open',
                'Media_Type__c'     => 'Standee',
                'Media_Sub_type__c' => 'Wall Wrap',
                'Quantity__c'       => 2
            });
            Test.stopTest();

            Case__c second = [SELECT Duplicate_Warning__c FROM Case__c WHERE Id = :secondId];
            System.assertNotEquals(null, second.Duplicate_Warning__c,
                'A distributor request with a recent duplicate must carry the warning');
            System.assert(second.Duplicate_Warning__c.contains('distributor'),
                'Warning should name the distributor, not "outlet". Got: ' + second.Duplicate_Warning__c);
        }
    }

    @isTest
    static void testRecalculateHandlesEmptyAndNull() {
        Test.startTest();
        AccountBrandingService.recalculate(null);
        AccountBrandingService.recalculate(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'Null and empty input must be a no-op, not an exception');
    }
}