@isTest
private class CompressedFileUploaderTest {

    @isTest
    static void testUploadCompressedImage() {
        // Step 1: Create a dummy record to link file to (optional here since it's commented out)
        Account testAccount = new Account(Name = 'File Target Account');
        insert testAccount;

        // Step 2: Mock base64 data (this represents the "compressed" file)
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('This is fake image content'));
        String fileName = 'testImage.jpg';

        // Step 3: Start test context
        Test.startTest();
        Id contentDocId = CompressedFileUploader.uploadCompressedImage(base64Data, fileName, testAccount.Id);
        Test.stopTest();

        // Step 4: Assertions
        System.assertNotEquals(null, contentDocId, 'ContentDocumentId should not be null');

        // Optionally, verify the ContentVersion exists
        ContentVersion cv = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE ContentDocumentId = :contentDocId LIMIT 1];
      //  System.assertEquals('test', cv.Title, 'Title should match the hardcoded value');
    }
}