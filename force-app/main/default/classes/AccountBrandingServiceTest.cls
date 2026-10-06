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

    // ================= APPROVAL CANNOT SKIP THE VENDOR =================
    @isTest
    static void testApprovalBlockedWithoutVendor() {
        Account retailer = newRetailer('Approval Guard Retailer', 'SF920030');
        insert retailer;
        Case_Type__c rt = new Case_Type__c(
            Name = 'Branding & Marketing Asset transfer Request', Type__c = 'Case', Active__c = true);
        insert rt;
        Branding_Asset__c asset = new Branding_Asset__c(
            Account__c = retailer.Id, Active__c = true, Media_Type__c = 'Flange');
        insert asset;

        Case__c c = new Case__c(Case_Type__c = rt.Id, Retailer__c = retailer.Id,
            Branding_Asset__c = asset.Id, Condition__c = 'Damaged', Status__c = 'L1 Approved');
        insert c;

        // The transition the approval final action performs, with no vendor.
        Boolean blocked = false;
        String msg = '';
        Test.startTest();
        try {
            update new Case__c(Id = c.Id, Status__c = 'Completed');
        } catch (Exception e) {
            blocked = true; msg = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, blocked,
            'Completing without a vendor must be blocked by the trigger guard');
        System.assert(msg.contains('Vendor'), 'Error should name the vendor: ' + msg);
        System.assertNotEquals(null,
            [SELECT Account__c FROM Branding_Asset__c WHERE Id = :asset.Id].Account__c,
            'A blocked approval must not untag the asset');
    }

    @isTest
    static void testRejectionNeedsNoVendor() {
        Account retailer = newRetailer('Reject Guard Retailer', 'SF920031');
        insert retailer;
        Case_Type__c rt = new Case_Type__c(
            Name = 'Branding & Marketing Asset transfer Request', Type__c = 'Case', Active__c = true);
        insert rt;
        Branding_Asset__c asset = new Branding_Asset__c(
            Account__c = retailer.Id, Active__c = true, Media_Type__c = 'Signage');
        insert asset;
        Case__c c = new Case__c(Case_Type__c = rt.Id, Retailer__c = retailer.Id,
            Branding_Asset__c = asset.Id, Condition__c = 'Damaged', Status__c = 'Pending');
        insert c;

        Test.startTest();
        update new Case__c(Id = c.Id, Status__c = 'Closed');
        Test.stopTest();

        System.assertEquals('Closed', [SELECT Status__c FROM Case__c WHERE Id = :c.Id].Status__c,
            'Rejection must go through with no vendor');
        System.assertNotEquals(null,
            [SELECT Account__c FROM Branding_Asset__c WHERE Id = :asset.Id].Account__c,
            'Rejection must leave the asset tagged');
    }

    // ================= RETURN CASE RETIRES THE ASSET =================
    @isTest
    static void testCompletedReturnCaseRetiresBrandingAsset() {
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

        Branding_Asset__c after = [SELECT Active__c, Account__c FROM Branding_Asset__c WHERE Id = :returned.Id];
        System.assertEquals(false, after.Active__c,
            'Completing the return must retire the branding asset');
        System.assertNotEquals(null, after.Account__c,
            'Account__c is kept so the record still shows which outlet held it');
        Branding_Asset__c other = [SELECT Active__c, Account__c FROM Branding_Asset__c WHERE Id = :untouched.Id];
        System.assertEquals(true, other.Active__c,
            'Other branding on the outlet must be left alone');
        System.assertNotEquals(null, other.Account__c,
            'Other branding must stay tagged to the outlet');
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
        // Both side photos are mandatory on every line - see saveCaseWithLines.
        List<Map<String, Object>> lines = new List<Map<String, Object>>{
            withBothSides(new Map<String, Object>{ 'mediaType' => 'Standee',
                'mediaSubType' => 'ACP/LE Signage', 'quantity' => 3 }),
            withBothSides(new Map<String, Object>{ 'mediaType' => 'Standee',
                'mediaSubType' => 'Wall Wrap', 'quantity' => 2 })
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
                    withBothSides(new Map<String, Object>{ 'mediaType' => 'Standee',
                        'mediaSubType' => 'Wall Wrap', 'quantity' => 1 })
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

    // ================= SKIN CHANGE =================
    /**
     * A skin change re-faces the asset already on the outlet: no new asset is
     * created, the counter goes up, the history gains a dated line and the
     * asset's image is replaced.
     */
    @isTest
    static void testSkinChangeUpdatesExistingAssetAndCreatesNone() {
        Account retailer = newRetailer('Skin Change Retailer', 'SF970001');
        insert retailer;

        Case_Type__c ct = new Case_Type__c(
            Name = 'Branding & Marketing Asset Request', Type__c = 'Case', Active__c = true);
        insert ct;

        Branding_Asset__c existing = new Branding_Asset__c(
            Account__c = retailer.Id, Active__c = true,
            Media_Type__c = 'Standee', Media_Sub_Type__c = 'ACP/LE Signage',
            Installation_Image_URL__c = 'https://example.com/old-skin.jpg'
        );
        insert existing;

        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Retailer__c = retailer.Id,
            Request_type__c = 'Skin Change',
            Branding_Asset__c = existing.Id,
            Media_Type__c = 'Standee', Media_Sub_type__c = 'Skin Change',
            Installation_Image_URL__c = 'https://example.com/new-skin.jpg',
            Status__c = 'Installation Pending'
        );
        insert c;

        Integer assetsBefore = [SELECT COUNT() FROM Branding_Asset__c WHERE Account__c = :retailer.Id];

        Test.startTest();
        update new Case__c(Id = c.Id, Status__c = 'Installed');
        Test.stopTest();

        System.assertEquals(assetsBefore,
            [SELECT COUNT() FROM Branding_Asset__c WHERE Account__c = :retailer.Id],
            'A skin change must not create a new branding asset');

        Branding_Asset__c after = [
            SELECT Skin_Change_Count__c, Skin_Change_History__c, Installation_Image_URL__c
            FROM Branding_Asset__c WHERE Id = :existing.Id
        ];
        System.assertEquals(1, after.Skin_Change_Count__c, 'The counter must go up by one');
        System.assertEquals('https://example.com/new-skin.jpg', after.Installation_Image_URL__c,
            'The new skin replaces the image on the asset');
        System.assertNotEquals(null, after.Skin_Change_History__c, 'A history line must be written');
        System.assert(after.Skin_Change_History__c.contains('new-skin.jpg'),
            'The history line carries the photo URL, got: ' + after.Skin_Change_History__c);
        System.assert(after.Skin_Change_History__c.contains('changed by'),
            'The history line names who changed it, got: ' + after.Skin_Change_History__c);
        System.assert(after.Skin_Change_History__c.contains(Datetime.now().format('dd-MMM-yyyy')),
            'The history line is dated DD-Mon-YYYY, got: ' + after.Skin_Change_History__c);
    }

    /** A second skin change appends rather than replacing the history. */
    @isTest
    static void testSecondSkinChangeAppendsToHistory() {
        Account retailer = newRetailer('Skin Twice Retailer', 'SF970002');
        insert retailer;
        Case_Type__c ct = new Case_Type__c(
            Name = 'Branding & Marketing Asset Request', Type__c = 'Case', Active__c = true);
        insert ct;

        Branding_Asset__c existing = new Branding_Asset__c(
            Account__c = retailer.Id, Active__c = true,
            Media_Type__c = 'Signage', Media_Sub_Type__c = 'Back lit Signage',
            Skin_Change_Count__c = 1,
            Skin_Change_History__c = '01-Jan-2026 | https://example.com/first.jpg | changed by Someone'
        );
        insert existing;

        Case__c c = new Case__c(
            Case_Type__c = ct.Id, Retailer__c = retailer.Id,
            Request_type__c = 'Skin Change', Branding_Asset__c = existing.Id,
            Media_Type__c = 'Signage', Media_Sub_type__c = 'Skin Change',
            Installation_Image_URL__c = 'https://example.com/second.jpg',
            Status__c = 'Installation Pending'
        );
        insert c;

        Test.startTest();
        update new Case__c(Id = c.Id, Status__c = 'Installed');
        Test.stopTest();

        Branding_Asset__c after = [
            SELECT Skin_Change_Count__c, Skin_Change_History__c
            FROM Branding_Asset__c WHERE Id = :existing.Id
        ];
        System.assertEquals(2, after.Skin_Change_Count__c, 'The counter continues from 1');
        System.assert(after.Skin_Change_History__c.contains('first.jpg'),
            'The earlier line must survive');
        System.assert(after.Skin_Change_History__c.contains('second.jpg'),
            'The new line must be appended');
    }

    /** Adds the two mandatory side photos to a media line map. */
    private static Map<String, Object> withBothSides(Map<String, Object> line) {
        line.put('photoName', 'side1.jpg');
        line.put('photoBase64', 'aGVsbG8=');
        line.put('photoName2', 'side2.jpg');
        line.put('photoBase642', 'aGVsbG8=');
        return line;
    }

    /**
     * The server guard, not just the LWC: a line carrying only Side 1 must be
     * refused however saveCaseWithLines is called.
     */
    @isTest
    static void testMediaLineWithOnlyOneSidePhotoIsRejected() {
        Account retailer = newRetailer('Two Side Retailer', 'SF960011');
        insert retailer;
        Case_Type__c ct = inventoryCaseType();

        Boolean threw = false;
        String message = '';   // captured for debugging; not asserted - see below
        Test.startTest();
        try {
            CaseScreenController.saveCaseWithLines(
                new Map<String, Object>{
                    'Case_Type__c' => ct.Id, 'Retailer__c' => retailer.Id, 'Status__c' => 'Open'
                },
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'mediaType' => 'Standee', 'mediaSubType' => 'Wall Wrap', 'quantity' => 1,
                        'photoName' => 'side1.jpg', 'photoBase64' => 'aGVsbG8='
                        // Side 2 deliberately absent
                    }
                }
            );
        } catch (Exception e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        // AuraHandledException.getMessage() is "Script-thrown exception" inside a
        // test, so only the refusal itself can be asserted here.
        System.assert(threw, 'A line with only one side photo must be rejected');
    }

    /**
     * A deep-freezer skin change carries Assigned_Asset__c and no
     * Branding_Asset__c by design, so the "nothing to re-skin" guard must not
     * fire on it. One photo is enough, as for any skin change.
     */
    @isTest
    static void testSubmitInstallationAcceptsDeepFreezerSkinChange() {
        Account retailer = newRetailer('Freezer Skin Retailer', 'SF960013');
        insert retailer;

        Case_Type__c ct = new Case_Type__c(
            Name = 'Branding & Marketing Asset Request', Type__c = 'Case', Active__c = true
        );
        insert ct;

        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-FRZSKIN-1');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = retailer.Id, Active__c = true
        );
        insert mapping;

        Case__c c = new Case__c(
            Case_Type__c = ct.Id,
            Retailer__c = retailer.Id,
            Status__c = 'Installation Pending',
            Request_type__c = 'Skin Change',
            Skin_Change_Asset_Type__c = 'Deep Freezer',
            Assigned_Asset__c = mapping.Id      // no Branding_Asset__c - the whole point
        );
        insert c;

        Boolean threw = false;
        Test.startTest();
        try {
            CaseScreenController.submitInstallation(c.Id, new List<Map<String, String>>{
                new Map<String, String>{ 'fileName' => 'newskin.jpg', 'base64' => 'aGVsbG8=' }
            });
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(!threw,
            'A deep-freezer skin change has no branding asset and must still install');
        System.assertEquals('Installed',
            [SELECT Status__c FROM Case__c WHERE Id = :c.Id].Status__c,
            'The case should reach Installed');

        // The point of a re-skin: the master now shows the new face.
        Asset_Master__c reskinned = [
            SELECT Asset_Image__c FROM Asset_Master__c WHERE Id = :master.Id
        ];
        String caseUrl = [
            SELECT Installation_Image_URL__c FROM Case__c WHERE Id = :c.Id
        ].Installation_Image_URL__c;
        System.assert(String.isNotBlank(reskinned.Asset_Image__c),
            'The Asset Master image must be set by a deep-freezer re-skin');
        System.assertEquals(caseUrl, reskinned.Asset_Image__c,
            'The master should carry the same photo the installation captured');
    }

    /**
     * Parity with a branding re-skin: the second one increments the counter and
     * appends to the history rather than replacing what came before.
     */
    @isTest
    static void testSecondFreezerSkinChangeAppendsToHistory() {
        Account retailer = newRetailer('Freezer Rskin Twice', 'SF960015');
        insert retailer;

        Case_Type__c ct = new Case_Type__c(
            Name = 'Branding & Marketing Asset Request', Type__c = 'Case', Active__c = true
        );
        insert ct;

        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-FRZSKIN-2');
        insert master;
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = retailer.Id, Active__c = true
        );
        insert mapping;

        Test.startTest();
        for (Integer i = 1; i <= 2; i++) {
            Case__c c = new Case__c(
                Case_Type__c = ct.Id,
                Retailer__c = retailer.Id,
                Status__c = 'Installation Pending',
                Request_type__c = 'Skin Change',
                Skin_Change_Asset_Type__c = 'Deep Freezer',
                Assigned_Asset__c = mapping.Id
            );
            insert c;
            CaseScreenController.submitInstallation(c.Id, new List<Map<String, String>>{
                new Map<String, String>{ 'fileName' => 'skin' + i + '.jpg', 'base64' => 'aGVsbG8=' }
            });
        }
        Test.stopTest();

        Asset_Master__c after = [
            SELECT Skin_Change_Count__c, Skin_Change_History__c
            FROM Asset_Master__c WHERE Id = :master.Id
        ];

        System.assertEquals(2, after.Skin_Change_Count__c,
            'Two re-skins should leave the counter at two');
        System.assertEquals(2, after.Skin_Change_History__c.split('\n').size(),
            'Each re-skin should add its own history line, not replace the last');
    }

    /**
     * The same guard still bites when neither asset is set - a skin change with
     * nothing at all to re-skin cannot be installed.
     */
    @isTest
    static void testSubmitInstallationRejectsSkinChangeWithNoAsset() {
        Account retailer = newRetailer('No Asset Skin Retailer', 'SF960014');
        insert retailer;

        Case_Type__c ct = new Case_Type__c(
            Name = 'Branding & Marketing Asset Request', Type__c = 'Case', Active__c = true
        );
        insert ct;

        Case__c c = new Case__c(
            Case_Type__c = ct.Id,
            Retailer__c = retailer.Id,
            Status__c = 'Installation Pending',
            Request_type__c = 'Skin Change'      // neither asset set
        );
        insert c;

        Boolean threw = false;
        Test.startTest();
        try {
            CaseScreenController.submitInstallation(c.Id, new List<Map<String, String>>{
                new Map<String, String>{ 'fileName' => 'newskin.jpg', 'base64' => 'aGVsbG8=' }
            });
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'A skin change with no asset at all must be refused');
        System.assertNotEquals('Installed',
            [SELECT Status__c FROM Case__c WHERE Id = :c.Id].Status__c,
            'The case must not reach Installed');
    }

    /** The installation guard needs two files, not one. */
    @isTest
    static void testSubmitInstallationNeedsBothSidePhotos() {
        Account retailer = newRetailer('Install Guard Retailer', 'SF960012');
        insert retailer;
        Case_Type__c ct = inventoryCaseType();
        Case__c c = new Case__c(Case_Type__c = ct.Id, Retailer__c = retailer.Id, Status__c = 'Open');
        insert c;

        Boolean threw = false;
        String message = '';   // captured for debugging; not asserted - see below
        Test.startTest();
        try {
            CaseScreenController.submitInstallation(c.Id, new List<Map<String, String>>{
                new Map<String, String>{ 'fileName' => 'side1.jpg', 'base64' => 'aGVsbG8=' }
            });
        } catch (Exception e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(threw, 'One photo must not be enough to complete installation');
        System.assertNotEquals('Installed',
            [SELECT Status__c FROM Case__c WHERE Id = :c.Id].Status__c,
            'The case must not move to Installed on a rejected submission');
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