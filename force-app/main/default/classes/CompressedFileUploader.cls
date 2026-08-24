public with sharing class CompressedFileUploader {
    @AuraEnabled
    public static Id uploadCompressedImage(String base64Data, String fileName, Id recordId) {
      System.debug('entered ');
        ContentVersion cv = new ContentVersion();
        cv.VersionData = EncodingUtil.base64Decode(base64Data);
        cv.Title = getTitleFromFileName(fileName);
        cv.PathOnClient = fileName;
        insert cv;

      ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
      /*    cdl.LinkedEntityId = recordId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;
System.debug(cdl.ContentDocumentId);*/
        return  cdl.ContentDocumentId;
    }
    
    private static String getTitleFromFileName(String fileName) {
        if (fileName == null) return 'Untitled_Image';
        Integer dotIndex = fileName.lastIndexOf('.');
        return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    }
}