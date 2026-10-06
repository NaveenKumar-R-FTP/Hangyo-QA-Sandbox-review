@isTest
private class ApproveReturnCaseActionTest {

    private static User newApprover(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            FirstName = 'Ret', LastName = 'Approver ' + alias, Alias = alias,
            Email = 'ret.approver@hangyo.in',
            Username = 'ret.' + alias + DateTime.now().getTime() + '@hangyo.test.invalid',
            ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
    }

    /** Retailer, vendor and branding asset all in the same hub, or the
     *  hub-match rule rejects the vendor before the approval is reached. */
    private static Map<String, SObject> scenario(String code) {
        insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);

        Account retailer = new Account(
            Name = 'Return Approver Retailer ' + code,
            BillingCity = 'Panaji', BillingState = 'Goa', Hub__c = 'Goa',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Retailer').getRecordTypeId(),
            Retailer_Code__c = code
        );
        insert retailer;

        Vendor__c vendor = new Vendor__c(Name = 'Goa Return Vendor', Hub__c = 'Goa', Active__c = true);
        insert vendor;

        Case_Type__c ct = new Case_Type__c(
            Name = 'Branding & Marketing Asset transfer Request', Type__c = 'Case', Active__c = true);
        insert ct;

        Branding_Asset__c asset = new Branding_Asset__c(
            Account__c = retailer.Id, Active__c = true,
            Media_Type__c = 'Signage', Media_Sub_Type__c = 'Back lit Signage');
        insert asset;

        return new Map<String, SObject>{
            'retailer' => retailer, 'vendor' => vendor, 'caseType' => ct, 'asset' => asset
        };
    }

    private static Case__c submitReturnCase(Map<String, SObject> s, Id approverId) {
        Case__c c = new Case__c(
            Case_Type__c = s.get('caseType').Id,
            Retailer__c = s.get('retailer').Id,
            Branding_Asset__c = s.get('asset').Id,
            Condition__c = 'Outlet Closed',
            L1__c = approverId, L2__c = approverId,
            Status__c = 'Open'
        );
        insert c;

        Approval.ProcessSubmitRequest sr = new Approval.ProcessSubmitRequest();
        sr.setObjectId(c.Id);
        sr.setProcessDefinitionNameOrId('Branding_Marketing_Transfer_Approval');
        Approval.process(sr);
        return c;
    }

    /**
     * Covers the action itself: it stamps both fields and approves the running
     * user's own step.
     *
     * Only the first step is driven here. Carrying the case all the way to
     * Completed inside System.runAs trips a platform quirk - the untag cascade
     * (CaseTrigger -> BrandingAssetTrigger -> AccountBrandingService) throws
     * "Variable does not exist: tmpVar1" on a SOQL bind when it runs under
     * runAs. The same cascade works correctly as a real user in the org, and the
     * Completed -> untag behaviour is covered by
     * AccountBrandingServiceTest.testCompletedReturnCaseUntagsBrandingAsset.
     */
    @isTest
    static void testApproveStampsValuesAndAdvancesStep() {
        User approver = newApprover('appr1');
        insert approver;
        Map<String, SObject> s = scenario('SF930001');
        Case__c c = submitReturnCase(s, approver.Id);

        Test.startTest();
        List<ApproveReturnCaseAction.Result> out;
        System.runAs(approver) {
            ApproveReturnCaseAction.Request req = new ApproveReturnCaseAction.Request();
            req.caseId = c.Id;
            req.vendorId = s.get('vendor').Id;
            req.returnStatus = 'Re Use';
            req.comments = 'approved by test';
            out = ApproveReturnCaseAction.approve(new List<ApproveReturnCaseAction.Request>{ req });
        }
        Test.stopTest();

        System.assertEquals(true, out[0].success, out[0].message);
        Case__c fin = [SELECT Status__c, Vendor__c, Branding_Return_Status__c FROM Case__c WHERE Id = :c.Id];
        System.assertEquals(s.get('vendor').Id, fin.Vendor__c, 'Vendor must be stamped by the action');
        System.assertEquals('Re Use', fin.Branding_Return_Status__c, 'Return status must be stamped');
        System.assertEquals('L1 Approved', fin.Status__c, 'The approver\u0027s step must be approved');
    }

    @isTest
    static void testNonApproverIsRefused() {
        User approver = newApprover('appr2');
        User bystander = newApprover('appr3');
        insert new List<User>{ approver, bystander };
        Map<String, SObject> s = scenario('SF930002');
        Case__c c = submitReturnCase(s, approver.Id);

        Test.startTest();
        List<ApproveReturnCaseAction.Result> out;
        System.runAs(bystander) {
            ApproveReturnCaseAction.Request req = new ApproveReturnCaseAction.Request();
            req.caseId = c.Id;
            req.vendorId = s.get('vendor').Id;
            req.returnStatus = 'Re Use';
            out = ApproveReturnCaseAction.approve(new List<ApproveReturnCaseAction.Request>{ req });
        }
        Test.stopTest();

        System.assertEquals(false, out[0].success, 'Someone with no pending step must be refused');
        System.assertNotEquals('Completed',
            [SELECT Status__c FROM Case__c WHERE Id = :c.Id].Status__c,
            'The case must not advance for a non-approver');
    }

    @isTest
    static void testFailureIsReturnedNotThrown() {
        Map<String, SObject> s = scenario('SF930003');
        ApproveReturnCaseAction.Request req = new ApproveReturnCaseAction.Request();
        req.caseId = s.get('asset').Id;   // deliberately the wrong sobject type
        req.vendorId = s.get('vendor').Id;
        req.returnStatus = 'Re Use';

        Test.startTest();
        List<ApproveReturnCaseAction.Result> out =
            ApproveReturnCaseAction.approve(new List<ApproveReturnCaseAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, out[0].success, 'A bad id should come back as a failed result');
        System.assertNotEquals(null, out[0].message, 'The caller needs the reason');
    }

    /**
     * The New Branding Request path: vendor only, no return status.
     *
     * Branding_Return_Status__c must be left alone rather than blanked - the
     * field belongs to the transfer type, and the action is shared.
     */
    @isTest
    static void testApproveWithoutReturnStatusStampsVendorOnly() {
        User approver = newApprover('appr4');
        insert approver;
        Map<String, SObject> s = scenario('SF930004');
        Case__c c = submitReturnCase(s, approver.Id);

        Test.startTest();
        List<ApproveReturnCaseAction.Result> out;
        System.runAs(approver) {
            ApproveReturnCaseAction.Request req = new ApproveReturnCaseAction.Request();
            req.caseId = c.Id;
            req.vendorId = s.get('vendor').Id;
            // returnStatus deliberately left null - this is the new-request shape
            out = ApproveReturnCaseAction.approve(new List<ApproveReturnCaseAction.Request>{ req });
        }
        Test.stopTest();

        System.assertEquals(true, out[0].success, out[0].message);
        Case__c fin = [SELECT Status__c, Vendor__c, Branding_Return_Status__c FROM Case__c WHERE Id = :c.Id];
        System.assertEquals(s.get('vendor').Id, fin.Vendor__c, 'Vendor must still be stamped');
        System.assertEquals(null, fin.Branding_Return_Status__c,
            'With no status passed the field must be left untouched, not blanked');
        System.assertEquals('L1 Approved', fin.Status__c, 'The pending step must still be approved');
    }

    /** A blank string must behave the same as null - the field stays untouched. */
    @isTest
    static void testBlankReturnStatusDoesNotOverwrite() {
        User approver = newApprover('appr5');
        insert approver;
        Map<String, SObject> s = scenario('SF930005');
        Case__c c = submitReturnCase(s, approver.Id);
        update new Case__c(Id = c.Id, Branding_Return_Status__c = 'Re Use');

        Test.startTest();
        System.runAs(approver) {
            ApproveReturnCaseAction.Request req = new ApproveReturnCaseAction.Request();
            req.caseId = c.Id;
            req.vendorId = s.get('vendor').Id;
            req.returnStatus = '';
            ApproveReturnCaseAction.approve(new List<ApproveReturnCaseAction.Request>{ req });
        }
        Test.stopTest();

        System.assertEquals('Re Use',
            [SELECT Branding_Return_Status__c FROM Case__c WHERE Id = :c.Id].Branding_Return_Status__c,
            'A blank status must not wipe a value that is already there');
    }
}