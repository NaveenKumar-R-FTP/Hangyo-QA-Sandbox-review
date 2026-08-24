@isTest
public class ContentDocumentLinkTriggerTest {
    @isTest
    static void testContentDocumentLinkTrigger() {
        // Create a test Product
        Product__c testProduct = new Product__c(
            Name = 'Test Product',
            Image_Long__c = null
        );
        insert testProduct;

        // Create a test ContentVersion (ContentDocument is automatically created)
        ContentVersion testContentVersion = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.pdf',
            VersionData = Blob.valueOf('Test data') // Simulating file content
        );
        insert testContentVersion;

        // Retrieve the ContentDocumentId from the inserted ContentVersion
        ContentVersion insertedContentVersion = [
            SELECT Id, ContentDocumentId 
            FROM ContentVersion 
            WHERE Id = :testContentVersion.Id
        ];
        Id contentDocumentId = insertedContentVersion.ContentDocumentId;

        // Create a ContentDocumentLink to associate the ContentDocument with the Product
        ContentDocumentLink testContentDocumentLink = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = testProduct.Id,
            ShareType = 'V'
        );

        Test.startTest();
        // Insert ContentDocumentLink to trigger the logic
        insert testContentDocumentLink;
        Test.stopTest();

        // Verify that the Product__c record is updated with the ContentDownloadUrl
        Product__c updatedProduct = [
            SELECT Id, Image_Long__c 
            FROM Product__c 
            WHERE Id = :testProduct.Id
        ];

        // Assert that the Image_Long__c field was updated
        System.assertNotEquals(null, updatedProduct.Image_Long__c, 'The Image_Long__c field should have been updated with the ContentDownloadUrl.');
        System.debug('Updated Product Image_Long__c: ' + updatedProduct.Image_Long__c);
    }
}