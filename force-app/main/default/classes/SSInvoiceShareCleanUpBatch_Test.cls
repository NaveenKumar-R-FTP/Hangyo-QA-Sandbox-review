@isTest
public class SSInvoiceShareCleanUpBatch_Test {

    @testSetup
    static void setupData() {

        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

        // RecordType
        RecordType rt = [
            SELECT Id 
            FROM RecordType 
            WHERE SobjectType = 'Invoice__c'
            AND Name = 'Secondary Invoice Under SS'
            LIMIT 1
        ];

        // Account (Under SS)
        Account acc = new Account(Name = 'SS Account');
        insert acc;

        Contact c = new Contact(LastName = 'Test', AccountId = acc.Id);
        insert c;

        // Partner User
        Profile partnerProfile = [
            SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1
        ];

        User partnerUser = new User(
            Alias = 'ptu',
            Email = 'partner1@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Partner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = partnerProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'partner1_' + System.currentTimeMillis() + '@test.com',
            ContactId = c.Id,
            IsActive = true
        );
        insert partnerUser;

        // Non-Partner User
        Profile std = [SELECT Id FROM Profile WHERE Name LIKE '%Standard%' LIMIT 1];

        User otherUser = new User(
            FirstName = 'Other',
            LastName  = 'User',
            Email = 'other_' + System.currentTimeMillis() + '@email.com',
            Username  = 'otheruser_' + System.currentTimeMillis() + '@test.com',
            Alias = 'oth',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey   = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = std.Id,
            IsActive = true
        );
        insert otherUser;

        // Invoice
        // Invoice (create but do not set dates yet)
        Invoice__c inv = new Invoice__c(
            Name = 'Test Invoice',
            RecordTypeId = rt.Id,
            Under_SS__c = acc.Id,
            Transaction_Type_Sale__c = 'Sale to Under S',
            Transaction_Type_Purchase__c = 'Purchased from Super Stockist'
        );
        insert inv;
        
        // Set CreatedDate = 2 days ago
        Test.setCreatedDate(inv.Id, System.now().addDays(-5));
        
        // Trick to sync LastModifiedDate = CreatedDate
        delete inv;
        undelete inv;


        // Insert sharing rows (must use runAs)
        //System.runAs(partnerUser) {
            // Valid share
            Invoice__Share validShare = new Invoice__Share(
                ParentId = inv.Id,
                UserOrGroupId = partnerUser.Id,
                AccessLevel = 'Read'
            );
            insert validShare;

            // Invalid share
            /*Invoice__Share invalidShare = new Invoice__Share(
                ParentId = inv.Id,
                UserOrGroupId = otherUser.Id,
                AccessLevel = 'Read'
            );
            insert invalidShare;*/
        //}
    }

    @isTest
    static void testBatchShareCleanup() {

        Test.startTest();
        SSInvoiceShareCleanUpBatch batch = new SSInvoiceShareCleanUpBatch();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // After batch, only partner user share should remain
        List<Invoice__Share> remaining = [
            SELECT ParentId, UserOrGroupId
            FROM Invoice__Share
        ];

    }
}