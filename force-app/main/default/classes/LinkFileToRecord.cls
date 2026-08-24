public with sharing class LinkFileToRecord {
    @InvocableMethod(label='Link File to Record')
    public static void linkFileToRecordNotes(List<Request> requests) {
        for (Request req : requests) {
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = req.contentDocumentId;
            cdl.LinkedEntityId = req.newRecordId;
            cdl.ShareType = 'V';
            cdl.Visibility = 'AllUsers';
            insert cdl;
        }
    }

    public class Request {
        @InvocableVariable(label='Content Document Id')
        public String contentDocumentId;

        @InvocableVariable(label='New Record Id')
        public Id newRecordId;
    }
}