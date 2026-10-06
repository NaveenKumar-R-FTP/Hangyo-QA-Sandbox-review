/**
 * Hands Azure-fetched Invoice_Line_Item__c data from InvoicePDFWrapperController
 * across to the PDF-rendering controller (SecondaryInvoiceDownloaderCtl /
 * SecondaryUnderSsInvoiceDownloaderCtl), which is invoked via
 * PageReference.getContent(). That invocation path does not support making
 * its own HTTP callout, so the wrapper must fetch from Azure BEFORE calling
 * getContent() and stash the result somewhere the nested page can read
 * without calling out itself. A plain Apex variable/static does not survive
 * across that boundary (getContent() renders in its own execution context),
 * so this uses Platform Cache (org-scoped) as the hand-off mechanism.
 *
 * REQUIRED CONFIG: a Platform Cache partition must exist in this org - see
 * PARTITION_NAME below and the deployment notes provided alongside this class.
 *
 * This class never throws: if Platform Cache is not provisioned/available,
 * put()/get()/remove() all degrade to no-ops (get() returns null), and the
 * callers fall back to their own handling (SecondaryInvoiceDownloaderCtl
 * falls back to a direct Azure callout when accessed outside the wrapper;
 * InvoicePDFWrapperController surfaces a clear error rather than rendering
 * an incomplete PDF).
 */
public without sharing class InvoiceLineItemCacheHelper {

    // Adjust to match the Platform Cache partition created in Setup. If this
    // org has no custom namespace, the partition name in Cache.Org.getPartition
    // is typically 'local.<PartitionName>'.
    private static final String PARTITION_NAME = 'local.InvoicePdfCache';
    private static final Integer TTL_SECONDS = 300; // 5 minutes - comfortably covers one synchronous getContent() call

    public static void put(Id invoiceId, List<Invoice_Line_Item__c> lineItems) {
        if (invoiceId == null || lineItems == null) {
            return;
        }
        try {
            Cache.OrgPartition part = getPartition();
            if (part != null) {
                part.put(cacheKey(invoiceId), JSON.serialize(lineItems), TTL_SECONDS);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'InvoiceLineItemCacheHelper.put failed: ' + e.getMessage());
        }
    }

    public static List<Invoice_Line_Item__c> get(Id invoiceId) {
        if (invoiceId == null) {
            return null;
        }
        try {
            Cache.OrgPartition part = getPartition();
            if (part != null && part.contains(cacheKey(invoiceId))) {
                Object cached = part.get(cacheKey(invoiceId));
                if (cached instanceof String) {
                    return (List<Invoice_Line_Item__c>) JSON.deserialize((String) cached, List<Invoice_Line_Item__c>.class);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'InvoiceLineItemCacheHelper.get failed: ' + e.getMessage());
        }
        return null;
    }

    public static void remove(Id invoiceId) {
        if (invoiceId == null) {
            return;
        }
        try {
            Cache.OrgPartition part = getPartition();
            if (part != null && part.contains(cacheKey(invoiceId))) {
                part.remove(cacheKey(invoiceId));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'InvoiceLineItemCacheHelper.remove failed: ' + e.getMessage());
        }
    }

    private static Cache.OrgPartition getPartition() {
        try {
            
            return Cache.Org.getPartition(PARTITION_NAME);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'InvoiceLineItemCacheHelper: Platform Cache partition unavailable - ' + e.getMessage());
            return null;
        }
    }

    // Scoped by both invoice and running user, so two people generating the
    // same invoice's PDF at the same moment can't collide.
    private static String cacheKey(Id invoiceId) {
        return 'AzureLI_' + invoiceId + '_' + UserInfo.getUserId();
    }
}