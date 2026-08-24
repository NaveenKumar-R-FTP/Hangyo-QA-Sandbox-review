trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {
    if (Trigger.isInsert && Trigger.isAfter) {
        ContentDocumentLinkHandler.handleAfterInsert(Trigger.new);
    }
}