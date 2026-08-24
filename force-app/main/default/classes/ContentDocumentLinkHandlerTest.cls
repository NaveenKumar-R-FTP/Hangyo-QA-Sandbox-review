@isTest
public class ContentDocumentLinkHandlerTest {
    @isTest
    static void testHandleAfterInsert() {
        // Step 1: Set up test data
        Account testAccount = new Account(Name = 'Test Account',
                 PAN_Number__c='TGYKI5566J');
        insert testAccount;

        Product__c testProduct = new Product__c(Name = 'Test Product');
        insert testProduct;

        // Step 2: Create a test ContentVersion (ContentDocument is automatically created)
        ContentVersion testContentVersion = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.pdf',
            VersionData = Blob.valueOf('Test data') // Simulate file content
        );
        insert testContentVersion;

        // Retrieve the ContentDocumentId from the inserted ContentVersion
        ContentVersion insertedContentVersion = [
            SELECT Id, ContentDocumentId 
            FROM ContentVersion 
            WHERE Id = :testContentVersion.Id
        ];
        Id contentDocumentId = insertedContentVersion.ContentDocumentId;

        // Step 3: Create a ContentDocumentLink to associate the ContentDocument with the Product
        ContentDocumentLink testContentDocLink = new ContentDocumentLink(
            LinkedEntityId = testProduct.Id,
            ContentDocumentId = contentDocumentId,
            ShareType = 'V' // Viewer access
        );

        // Step 4: Trigger the handler by inserting the ContentDocumentLink
        Test.startTest();
        insert testContentDocLink; // This automatically calls the trigger
        Test.stopTest();

        // Step 5: Verify results
        // Verify that ContentDistribution records were created
        List<ContentDistribution> distributions = [
            SELECT Id, ContentVersionId, ContentDownloadUrl 
            FROM ContentDistribution
        ];
        System.assert(!distributions.isEmpty(), 'ContentDistribution records should have been created.');

        // Verify that the Product record was updated with the Image_Long__c field
        Product__c updatedProduct = [SELECT Id, Image_Long__c FROM Product__c WHERE Id = :testProduct.Id];
        System.assertNotEquals(null, updatedProduct.Image_Long__c, 'Product Image_Long__c should have been updated.');
    }
}