@isTest
private class LinkFileToRecordTest {
    
    @isTest
    static void testLinkFileToRecordNotes() {
        // Step 1: Create a test Account (or any sObject)
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        // Step 2: Create a ContentVersion (this is how you upload a file in test context)
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'TestFile.txt',
            VersionData = Blob.valueOf('This is a test file.')
        );
        insert cv;

        // Step 3: Retrieve the ContentDocumentId from the inserted ContentVersion
        ContentVersion insertedCV = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        // Step 4: Prepare the request
        LinkFileToRecord.Request req = new LinkFileToRecord.Request();
        req.contentDocumentId = insertedCV.ContentDocumentId;
        req.newRecordId = testAccount.Id;

        // Step 5: Call the method
        Test.startTest();
        LinkFileToRecord.linkFileToRecordNotes(new List<LinkFileToRecord.Request>{ req });
        Test.stopTest();

        // Step 6: Assert that ContentDocumentLink was created
        List<ContentDocumentLink> links = [
            SELECT Id, LinkedEntityId, ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :testAccount.Id
        ];

        System.assertEquals(1, links.size(), 'One ContentDocumentLink should be created.');
        System.assertEquals(insertedCV.ContentDocumentId, links[0].ContentDocumentId, 'ContentDocumentId should match.');
        System.assertEquals(testAccount.Id, links[0].LinkedEntityId, 'LinkedEntityId should match the Account.');
    }
}