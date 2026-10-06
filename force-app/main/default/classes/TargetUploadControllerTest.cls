@isTest
private class TargetUploadControllerTest {

    // User (setup object) created in its own transaction to avoid mixed-DML with
    // the non-setup Sales_Target__c upsert done inside uploadTargets().
    @testSetup
    static void makeUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(System.now().getTime());
        insert new User(
            FirstName = 'MIS', LastName = 'Uploader',
            Email = 'misupload@hangyo.in',
            Username = 'misupload' + uniq + '@hangyo.in.invalid',
            Alias = 'misu', EmployeeNumber = 'TESTEMP1',
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = p.Id, IsActive = true
        );
    }

    @isTest
    static void template_notEmpty() {
        System.assert(String.isNotBlank(TargetUploadController.getTemplate()), 'template returned');
    }

    @isTest
    static void upload_createsAndUpdatesTarget() {
        User u = [SELECT Id, EmployeeNumber FROM User WHERE EmployeeNumber = 'TESTEMP1' LIMIT 1];

        Test.startTest();
        // create
        TargetUploadController.UploadResult r1 = TargetUploadController.uploadTargets(
            'Employee Code,Month,Year,Secondary Target\n' + u.EmployeeNumber + ',8,2026,160000\n');
        // update same employee+month -> upsert same row
        TargetUploadController.UploadResult r2 = TargetUploadController.uploadTargets(
            'Employee Code,Month,Year,Secondary Target\n' + u.EmployeeNumber + ',8,2026,175000\n');
        Test.stopTest();

        System.assertEquals(1, r1.success, 'first upload created one');
        System.assertEquals(1, r2.success, 'second upload updated one');
        List<Sales_Target__c> rows = [SELECT Secondary_Sales_Target__c FROM Sales_Target__c WHERE Assigned_To__c = :u.Id];
        System.assertEquals(1, rows.size(), 'still one row (upsert, not duplicate)');
        System.assertEquals(175000, rows[0].Secondary_Sales_Target__c, 'target updated to latest value');
    }

    @isTest
    static void upload_reportsRowErrors() {
        Test.startTest();
        TargetUploadController.UploadResult res = TargetUploadController.uploadTargets(
            'Employee Code,Month,Year,Secondary Target\n'
            + 'UNKNOWNCODE,8,2026,1000\n'   // code not found
            + 'TESTEMP1,13,2026,1000\n'     // bad month
            + 'TESTEMP1,8,2026,notanumber\n'// bad target
            + ',8,2026,1000\n');            // missing code
        Test.stopTest();

        System.assertEquals(4, res.total, 'four data rows parsed');
        System.assertEquals(0, res.success, 'none valid');
        System.assertEquals(4, res.failed, 'all four errored');
    }

    @isTest
    static void parseMonth_handlesNamesAndNumbers() {
        System.assertEquals(8, TargetUploadController.parseMonth('8'));
        System.assertEquals(8, TargetUploadController.parseMonth('August'));
        System.assertEquals(null, TargetUploadController.parseMonth('13'));
        System.assertEquals(null, TargetUploadController.parseMonth('xyz'));
    }

    @isTest
    static void upload_blankReturnsEmpty() {
        TargetUploadController.UploadResult res = TargetUploadController.uploadTargets('');
        System.assertEquals(0, res.total);
    }
}