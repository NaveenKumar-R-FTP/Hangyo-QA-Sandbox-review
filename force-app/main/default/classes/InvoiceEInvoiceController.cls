// Added by Hari - Apex controller for E-Invoice & E-Way Bill (Cygnet ASP) per requirement. Buttons visible when Status = Confirmed or Delivered.
public with sharing class InvoiceEInvoiceController {

    // Added by Hari - DMS: status used for integration eligibility
    private static final String STATUS_APPROVED = 'Confirmed';
    // Added by Hari - Button visibility on delivered status
    private static final String STATUS_DELIVERED = 'Delivered';

    // Added by Hari - Button visibility on delivered status
    private static Boolean isStatusEligibleForIntegration(String status) {
        if (String.isBlank(status)) return false;
        return STATUS_APPROVED.equalsIgnoreCase(status) || STATUS_DELIVERED.equalsIgnoreCase(status);
    }
    // Added by Hari - Scenario 2 (phase 1): enable E-Invoice only for Secondary Invoice record type
    private static final String RECORDTYPE_SECONDARY_INVOICE_DEVNAME = 'Secondary_Invoice';
    private static final String RECORDTYPE_SECONDARY_INVOICE_LABEL = 'Secondary Invoice';
    // Added by Hari - Secondary Under SS variant: seller is Superstockist and buyer is Under SS
    private static final String RECORDTYPE_SECONDARY_INVOICE_UNDER_SS_DEVNAME = 'Secondary_Invoice_Under_SS';

    // Added by Hari - Wrapper for LWC: same shape as before (irn, ewbNumber, statusApproved), no logic change
    public class InvoiceEInvoiceFieldsWrapper {
        @AuraEnabled public String irn;
        @AuraEnabled public String ewbNumber;
        @AuraEnabled public Boolean statusApproved;
    }

    // Added by Hari - Returns IRN, EWB, statusApproved for LWC visibility and refresh (wrapper; logic unchanged)
    @AuraEnabled(cacheable=false)
    public static InvoiceEInvoiceFieldsWrapper getInvoiceEInvoiceFields(Id invoiceId) {
        InvoiceEInvoiceFieldsWrapper result = new InvoiceEInvoiceFieldsWrapper();
        result.irn = '';
        result.ewbNumber = '';
        result.statusApproved = false;
        if (invoiceId == null) return result;
        List<Invoice__c> invs = [
            SELECT Id, IRN_Number__c, EWB__c, Status__c
            FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
        ];
        if (invs.isEmpty()) return result;
        Invoice__c inv = invs[0];
        result.irn = inv.IRN_Number__c != null ? String.valueOf(inv.IRN_Number__c) : '';
        result.ewbNumber = inv.EWB__c != null ? String.valueOf(inv.EWB__c) : '';
        // Added by Hari - Button visibility on delivered status
        result.statusApproved = isStatusEligibleForIntegration(inv.Status__c);
        return result;
    }

    // Added by hari - LWC: hide Download PDF buttons when Files already contain Cygnet PDFs (same Title patterns as getEInvoicePdfContentDocumentId / getEwayBillPdfContentDocumentId)
    @AuraEnabled
    public static Map<String, Boolean> getCygnetPdfAttachmentFlags(Id invoiceId) {
        Map<String, Boolean> m = new Map<String, Boolean>();
        m.put('hasEInvoicePdf', false);
        m.put('hasEwayBillPdf', false);
        if (invoiceId == null) {
            return m;
        }
        try {
            Integer einvCount = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :invoiceId AND ContentDocument.Title LIKE 'E-Invoice%'
            ];
            Integer ewbCount = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :invoiceId AND ContentDocument.Title LIKE 'E-Way Bill%'
            ];
            m.put('hasEInvoicePdf', einvCount != null && einvCount > 0);
            m.put('hasEwayBillPdf', ewbCount != null && ewbCount > 0);
        } catch (Exception e) {
            // leave defaults
        }
        return m;
    }

    // Added by Hari - TDD 11: Enqueue async E-Invoice job; status tracked via Cygnet_Reference_Id__c
    @AuraEnabled
    public static void generateEInvoice(Id invoiceId) {
        try {
        if (invoiceId == null) throw new AuraHandledException('Invoice Id is required.');
            validateForEInvoice(invoiceId);

            //Logged-in user Validation
            // Added by hari (Under SS) - Call auth to fail fast if the current user is not configured
            // for the invoice's record type (Secondary uses Cygnet_Integration_Setting__c; Under SS uses Cygnet_Integration_Setting_Under_SS__c).
            String authToken = CygnetApiService.getAuthToken(UserInfo.getUserName(), invoiceId);
            // suppress unused variable warning (Apex doesn't have unused warnings, but keep it explicit)
            if (authToken == null) { }
            System.enqueueJob(new CygnetEInvoiceQueueable(invoiceId));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Added by Hari - TDD §11: Enqueue async E-Way Bill job
    @AuraEnabled
    public static void generateEWayBill(Id invoiceId) {
        try {
        if (invoiceId == null) throw new AuraHandledException('Invoice Id is required.');
            // Fail fast: do callout-based validation BEFORE any DML in validateForEWayBill(),
            // otherwise Salesforce throws "You have uncommitted work pending" for callouts-after-DML.
            String authToken = CygnetApiService.getAuthToken(UserInfo.getUserName(), invoiceId);
            if (authToken == null) { }
            validateForEWayBill(invoiceId);
            System.enqueueJob(new CygnetEWayBillQueueable(invoiceId));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Added by Hari - Called by CygnetEInvoiceQueueable when status=P
    @AuraEnabled
    public static void processEInvoiceResult(Id invoiceId, CygnetApiService.StatusResult sr) {
        updateInvoiceWithEInvoiceResult(invoiceId, sr);
        // Added by Hari - (EWB) Do not export/attach E-Invoice PDF here.
        // This keeps Cygnet E-Invoice in a state acceptable for subsequent E-Way Bill by IRN generation.
        // PDF export will happen when user clicks Download via getEInvoicePdfContentDocumentId().
    }

    // Added by Hari - Called by CygnetEWayBillQueueable when status=P
    @AuraEnabled
    public static void processEWayBillResult(Id invoiceId, CygnetApiService.StatusResult sr) {
        updateInvoiceWithEWayBillResult(invoiceId, sr);
        try {
            attachEwayBillPdfToInvoice(invoiceId);
        } catch (Exception e) {
            // Keep EWB update successful even if PDF export/attach fails.
        }
    }

    // Added by Hari - Download E-Invoice PDF: return content document Id of attached file, or export and attach then return Id
    @AuraEnabled
    public static String getEInvoicePdfContentDocumentId(Id invoiceId) {
        if (invoiceId == null) return null;
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :invoiceId AND ContentDocument.Title LIKE 'E-Invoice%'
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
        String contentDocId;
        if (!links.isEmpty()) {
            contentDocId = links[0].ContentDocumentId;
        } else {
            attachEInvoicePdfToInvoice(invoiceId);
            links = [
                SELECT ContentDocumentId FROM ContentDocumentLink
                WHERE LinkedEntityId = :invoiceId AND ContentDocument.Title LIKE 'E-Invoice%'
                ORDER BY ContentDocument.CreatedDate DESC LIMIT 1
            ];
            contentDocId = links.isEmpty() ? null : links[0].ContentDocumentId;
        }

        // Added by Hari - (EWB) Enqueue E-Way Bill after user clicks Download E-Invoice PDF.
        // This aligns sequence with Cygnet state gating for ewaybillByIrnCompliant/save (VAL0528).
        try {
            Invoice__c inv = [
                SELECT EWB__c
                FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
            ];
            if (inv != null && (inv.EWB__c == null || String.isBlank(String.valueOf(inv.EWB__c)))) {
                System.enqueueJob(new CygnetEWayBillQueueable(invoiceId));
            }
        } catch (Exception e) { }

        return contentDocId;
    }

    // Added by Hari - Download E-Way Bill PDF: return content document Id of attached file, or export and attach then return Id
    @AuraEnabled
    public static String getEwayBillPdfContentDocumentId(Id invoiceId) {
        if (invoiceId == null) return null;
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :invoiceId AND ContentDocument.Title LIKE 'E-Way Bill%'
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
        if (!links.isEmpty()) return links[0].ContentDocumentId;
        attachEwayBillPdfToInvoice(invoiceId);
        links = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :invoiceId AND ContentDocument.Title LIKE 'E-Way Bill%'
            ORDER BY ContentDocument.CreatedDate DESC LIMIT 1
        ];
        return links.isEmpty() ? null : links[0].ContentDocumentId;
    }

    // Added by Hari - Scenario 2 (phase 1): validate Under SS (seller) and Retailer (buyer) on Invoice
    private static void validateForEInvoice(Id invoiceId) {
        // Added by Hari - Scenario 2: Location = Under SS (Seller) per invoice; no Location_Gstin__c in Custom Setting
        // Keep this check non-invasive; final validation is record-type specific below.
        Cygnet_Integration_Setting__c s0 = Cygnet_Integration_Setting__c.getInstance();
        if (s0 == null) {
            // This catches the fully-missing-org-default case early (logged-in user validation is below).
        }
        List<Invoice__c> invs = [
            // Added by Hari - Include RecordType for scenario gating
            SELECT Id, Status__c, RecordType.Name, RecordType.DeveloperName,
                Retailer_Account__c, Retailer_GSTIN__c, Distributor_Account__c, Under_SS__c, Under_SS_GSTIN__c,
                (SELECT Id FROM Invoice_Line_Items__r LIMIT 1)
            FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
        ];
        if (invs.isEmpty()) throw new AuraHandledException('Invoice not found.');
        Invoice__c inv = invs[0];
        // Added by Hari - Button visibility on delivered status
        if (!isStatusEligibleForIntegration(inv.Status__c)) {
            throw new AuraHandledException('Invoice Status must be Confirmed or Delivered to generate E-Invoice.');
        }
        // Added by Hari - Phase 1: Secondary invoice record types supported for E-Invoice
        if (
            inv.RecordType == null ||
            (
                !RECORDTYPE_SECONDARY_INVOICE_DEVNAME.equalsIgnoreCase(inv.RecordType.DeveloperName) &&
                !RECORDTYPE_SECONDARY_INVOICE_UNDER_SS_DEVNAME.equalsIgnoreCase(inv.RecordType.DeveloperName)
            )
        ) {
            throw new AuraHandledException('E-Invoice is enabled only for Secondary Invoice and Secondary Invoice Under SS record types.');
        }

        Boolean isUnderSsScenario = inv.RecordType != null &&
            RECORDTYPE_SECONDARY_INVOICE_UNDER_SS_DEVNAME.equalsIgnoreCase(inv.RecordType.DeveloperName);

        // Added by hari (Under SS) - Hierarchy custom setting: Secondary Invoice vs Under SS by record type
        if (isUnderSsScenario) {
            Cygnet_Integration_Setting_Under_SS__c us = Cygnet_Integration_Setting_Under_SS__c.getInstance(UserInfo.getUserId());
            if (us == null) us = Cygnet_Integration_Setting_Under_SS__c.getInstance();
            if (us == null) throw new AuraHandledException('Cygnet Integration Setting (Under SS) is not configured.');
        } else {
            Cygnet_Integration_Setting__c s = Cygnet_Integration_Setting__c.getInstance(UserInfo.getUserId());
            if (s == null) s = Cygnet_Integration_Setting__c.getInstance();
            if (s == null) throw new AuraHandledException('Cygnet Integration Setting is not configured.');
        }

        if (isUnderSsScenario) {
            // Secondary_Invoice_Under_SS only: Seller = Distributor; Buyer = Under_SS__c + Under_SS_GSTIN__c (fallback: Under SS Account GSTIN)
            if (inv.Distributor_Account__c == null) {
                throw new AuraHandledException('Superstockist (Seller) Account is required on the Invoice.');
            }
            List<Account> sellerAccs = [SELECT Id, GSTIN__c FROM Account WHERE Id = :inv.Distributor_Account__c LIMIT 1];
            if (sellerAccs.isEmpty() || String.isBlank(sellerAccs[0].GSTIN__c)) {
                throw new AuraHandledException('Superstockist (Seller) GSTIN is required on Distributor Account.');
            }

            if (inv.Under_SS__c == null) {
                throw new AuraHandledException('Under SS (Buyer) Account is required on the Invoice.');
            }
            if (String.isBlank(inv.Under_SS_GSTIN__c)) {
                List<Account> buyerAccs = [SELECT Id, GSTIN__c FROM Account WHERE Id = :inv.Under_SS__c LIMIT 1];
                if (buyerAccs.isEmpty() || String.isBlank(buyerAccs[0].GSTIN__c)) {
                    throw new AuraHandledException('Under SS (Buyer) GSTIN is required: set Under SS GSTIN on Invoice or on Under SS Account.');
                }
            }
        } else {
            // Secondary_Invoice: Seller from Distributor_Account__c (Under_SS__c not required); Buyer = Retailer
            if (inv.Distributor_Account__c == null) {
                throw new AuraHandledException('Distributor Account is required on the Invoice.');
            }
            if (String.isBlank(inv.Under_SS_GSTIN__c)) {
                List<Account> sellerAccs = [SELECT Id, GSTIN__c FROM Account WHERE Id = :inv.Distributor_Account__c LIMIT 1];
                if (sellerAccs.isEmpty() || String.isBlank(sellerAccs[0].GSTIN__c)) {
                    throw new AuraHandledException('Seller GSTIN is required: set Under SS GSTIN on Invoice or GSTIN on Distributor Account.');
                }
            }

            if (inv.Retailer_Account__c == null) throw new AuraHandledException('Retailer (Buyer) Account is required on the Invoice.');
            if (String.isBlank(inv.Retailer_GSTIN__c)) {
                List<Account> buyerAccs = [SELECT Id, GSTIN__c FROM Account WHERE Id = :inv.Retailer_Account__c LIMIT 1];
                if (buyerAccs.isEmpty() || String.isBlank(buyerAccs[0].GSTIN__c)) {
                    throw new AuraHandledException('Retailer (Buyer) GSTIN is required: set Retailer GSTIN on Invoice or on Retailer Account.');
                }
            }
        }
        if (inv.Invoice_Line_Items__r == null || inv.Invoice_Line_Items__r.isEmpty()) {
            throw new AuraHandledException('At least one Invoice Line Item is required.');
        }
    }

    private static void validateForEWayBill(Id invoiceId) {
        List<Invoice__c> invs = [
            SELECT Id, Status__c, IRN_Number__c, EWB__c, Vehicle_Number__c, Transporter_Name__c,
                Transporter_Doc_Number__c, Transporter_Doc_Date__c,
                Invoice_Number__c, Invoice_Date__c,
                Distributor_Account__c, Distributor_Account__r.GSTIN__c
            FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
        ];
        if (invs.isEmpty()) throw new AuraHandledException('Invoice not found.');
        Invoice__c inv = invs[0];
        // Added by Hari - Button visibility on delivered status
        if (!isStatusEligibleForIntegration(inv.Status__c)) {
            throw new AuraHandledException('Invoice Status must be Confirmed or Delivered to generate E-Way Bill.');
        }
        if (inv.IRN_Number__c == null || String.isBlank(String.valueOf(inv.IRN_Number__c))) {
            throw new AuraHandledException('IRN is required. Generate E-Invoice first.');
        }
        
        // Prevent duplicate EWB generation attempts when Cygnet already generated it with IRN.
        if (inv.EWB__c != null && !String.isBlank(String.valueOf(inv.EWB__c))) {
            throw new AuraHandledException('E-Way Bill is already generated. Please use Download E-Way Bill PDF.');
        }
        if (String.isBlank(inv.Vehicle_Number__c) && String.isBlank(inv.Transporter_Name__c)) {
            throw new AuraHandledException('Please fill in the Transporter details before generating E-Way bill');
        }

        // Added by hari - Auto fill Transporter doc fields from Invoice fields (used in mapper for EWB payload)
        Boolean needsUpdate = false;
        if (String.isBlank(String.valueOf(inv.Transporter_Doc_Number__c))) {
            if (String.isNotBlank(inv.Invoice_Number__c)) {
                inv.Transporter_Doc_Number__c = inv.Invoice_Number__c;
                needsUpdate = true;
            }
        }
        if (inv.Transporter_Doc_Date__c == null) {
            if (inv.Invoice_Date__c != null) {
                inv.Transporter_Doc_Date__c = inv.Invoice_Date__c;
                needsUpdate = true;
            }
        }
        if (needsUpdate) update inv;

        // Added by hari - Cygnet validates Transport Document Number length 1..15 after auto fill
        String docNo = String.isNotBlank(inv.Transporter_Doc_Number__c) ? String.valueOf(inv.Transporter_Doc_Number__c).trim() : '';
        if (String.isBlank(docNo)) {
            throw new AuraHandledException('Transport Document Number is required (Transporter_Doc_Number__c is blank and Invoice_Number__c is blank).');
        }
        if (docNo.length() > 15) {
            throw new AuraHandledException('Transport Document Number must be max 15 characters. Current length: ' + docNo.length());
        }

        // Added by hari - Cygnet requires transport document date
        if (inv.Transporter_Doc_Date__c == null) {
            throw new AuraHandledException('Transport Document Date is required (Transporter_Doc_Date__c is blank and Ewb Generated Date is blank).');
        }
    }

    private static void updateInvoiceWithEInvoiceResult(Id invoiceId, CygnetApiService.StatusResult sr) {
        SObject inv = new Invoice__c(Id = invoiceId);
        Boolean irnStored = false;

        // Added by hari - Handle IRN_Number__c type mismatch (Text vs Number) across orgs
        if (sr != null && String.isNotBlank(sr.irn)) {
            Schema.DescribeFieldResult d = Invoice__c.SObjectType.getDescribe()
                .fields.getMap().get('IRN_Number__c').getDescribe();

            String digits = sr.irn.replaceAll('[^0-9]', '');
            Object irnVal;
            if (d.getType() == Schema.DisplayType.Double ||
                d.getType() == Schema.DisplayType.Currency ||
                d.getType() == Schema.DisplayType.Integer) {
                irnVal = String.isNotBlank(digits) ? Decimal.valueOf(digits) : null;
            } else {
                irnVal = sr.irn;
            }

            if (irnVal != null) {
                inv.put('IRN_Number__c', irnVal);
                irnStored = true;
            }
        }

        // Added by hari - Handle Ack_No__c type mismatch (Text vs Number) across orgs
        if (sr != null && String.isNotBlank(sr.ackNo)) {
            String digits = sr.ackNo.replaceAll('[^0-9]', '');
            if (digits.length() > 18) digits = digits.substring(0, 18);

            Schema.DescribeFieldResult dAck = Invoice__c.SObjectType.getDescribe()
                .fields.getMap().get('Ack_No__c').getDescribe();

            Object ackVal;
            if (dAck.getType() == Schema.DisplayType.Double ||
                dAck.getType() == Schema.DisplayType.Currency ||
                dAck.getType() == Schema.DisplayType.Integer) {
                ackVal = String.isNotBlank(digits) ? Decimal.valueOf(digits) : null;
            } else {
                ackVal = String.isNotBlank(digits) ? digits : null;
            }

            if (ackVal != null) inv.put('Ack_No__c', ackVal);
        }

        // Added by hari - Ack_Date__c can arrive in non-ISO formats like "Sat Sep 16 00:00:00 GMT 30"
        if (sr != null && String.isNotBlank(sr.ackDate)) {
            Date ad = parseDate(sr.ackDate);
            if (ad != null) {
                inv.put('Ack_Date__c', ad);
            }
        }

        if (sr != null && sr.signedInvoice != null) inv.put('Signed_Invoice__c', sr.signedInvoice);
        if (sr != null && sr.signedQRCode != null) inv.put('Signed_QR_Code__c', sr.signedQRCode);
        if (sr != null && sr.qrCodeData != null) inv.put('QR_Code_Data__c', sr.qrCodeData);

        // If Cygnet generated EWB along with IRN, persist EWB fields here.
        Boolean hasStoredEwb = false;
        if (sr != null && String.isNotBlank(sr.ewbNo)) {
            String digits = sr.ewbNo.replaceAll('[^0-9]', '');
            if (String.isNotBlank(digits)) {
                inv.put('EWB__c', digits);
                hasStoredEwb = true;
            }
        }

        if (sr != null && String.isNotBlank(sr.ewbGeneratedDate)) {
            Date ewbGenDt = parseDate(sr.ewbGeneratedDate);
            inv.put('EWB_Generated_Date__c', ewbGenDt);
            //Added by hari for doc date = ewb gen date
            if (ewbGenDt != null) inv.put('Transporter_Doc_Date__c', ewbGenDt);
        }
        if (sr != null && String.isNotBlank(sr.ewbValidUpto)) inv.put('EWB_Valid_Till__c', parseDate(sr.ewbValidUpto));

        putTransportDistanceFromStatusIfPresent(inv, sr);

        // added by hari (Integration tax issue) - Clear Integration_Error__c once IRN is stored and/or EWB is stored (success after prior failure)
        if (irnStored || hasStoredEwb) {
            inv.put('Integration_Error__c', null);
        }
        update inv;
    }

    private static void updateInvoiceWithEWayBillResult(Id invoiceId, CygnetApiService.StatusResult sr) {
        SObject inv = new Invoice__c(Id = invoiceId);
        if (String.isNotBlank(sr.ewbNo)) {
            String digits = sr.ewbNo.replaceAll('[^0-9]', '');
            if (String.isNotBlank(digits)) {
                inv.put('EWB__c', digits);
                // added by hari (Integration tax issue) - Clear prior error once EWB is persisted (standalone E-Way Bill flow)
                inv.put('Integration_Error__c', null);
            }
        }
        if (String.isNotBlank(sr.ewbGeneratedDate)) {
            Date ewbGenDt = parseDate(sr.ewbGeneratedDate);
            inv.put('EWB_Generated_Date__c', ewbGenDt);
            //Added by hari for doc date = ewb gen date
            if (ewbGenDt != null) inv.put('Transporter_Doc_Date__c', ewbGenDt);
        }
        if (String.isNotBlank(sr.ewbValidUpto)) inv.put('EWB_Valid_Till__c', parseDate(sr.ewbValidUpto));
        putTransportDistanceFromStatusIfPresent(inv, sr);
        update inv;
    }

    /**
     * Persist Cygnet-computed distance (km) when status returns it; optional field — failures never block IRN/EWB updates.
     */
    private static void putTransportDistanceFromStatusIfPresent(SObject inv, CygnetApiService.StatusResult sr) {
        if (inv == null || sr == null || sr.distanceKm == null) return;
        if (sr.distanceKm <= 0) return;
        Map<String, Schema.SObjectField> fm = Invoice__c.SObjectType.getDescribe().fields.getMap();
        Schema.SObjectField tf = fm.get('Transport_Distance__c');
        if (tf == null) tf = fm.get('transport_distance__c');
        if (tf == null) return;
        Schema.DescribeFieldResult d = tf.getDescribe();
        if (!d.isUpdateable()) return;
        try {
            Object val;
            if (d.getType() == Schema.DisplayType.Integer) {
                val = sr.distanceKm.intValue();
            } else if (
                d.getType() == Schema.DisplayType.Double ||
                d.getType() == Schema.DisplayType.Currency ||
                d.getType() == Schema.DisplayType.Percent
            ) {
                val = sr.distanceKm;
            } else {
                val = String.valueOf(sr.distanceKm.intValue());
            }
            inv.put('Transport_Distance__c', val);
        } catch (Exception e) {
            // leave field unchanged
        }
    }

    private static Date parseDate(String d) {
        if (String.isBlank(d)) return null;
        d = d.trim();

        try {
            // Added by Hari - Handle Cygnet EWB datetime format like "26-03-2026 13:02:00"
            if (Pattern.matches('^\\d{2}-\\d{2}-\\d{4}(\\s+\\d{2}:\\d{2}:\\d{2})?$', d)) {
                String datePart = d.split('\\s+')[0];
                List<String> p = datePart.split('-');
                if (p.size() == 3) {
                    Integer ddDash = Integer.valueOf(p[0]);
                    Integer mmDash = Integer.valueOf(p[1]);
                    Integer yyyyDash = Integer.valueOf(p[2]);
                    return Date.newInstance(yyyyDash, mmDash, ddDash);
                }
            }

            // Added by hari - ISO format "yyyy-MM-dd" only
            if (Pattern.matches('^\\d{4}-\\d{2}-\\d{2}$', d)) {
                return Date.valueOf(d);
            }

            // Added by hari - "dd/MM/yyyy" or "dd/MM/yy" (fallback)
            if (d.contains('/')) {
                List<String> parts = d.split('/');
                if (parts.size() >= 3) {
                    Integer dd = Integer.valueOf(parts[0]);
                    Integer mm = Integer.valueOf(parts[1]);
                    Integer yyyy = Integer.valueOf(parts[2]);
                    return Date.newInstance(yyyy, mm, dd);
                }
            }

            // Added by hari - Example "Sat Sep 16 00:00:00 GMT 30" -> extract month + day (+ optional year)
            // Regex tokens: month short name (Jan..Dec) + day number
            Pattern p = Pattern.compile('\\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\b\\s+(\\d{1,2})\\b');
            Matcher m = p.matcher(d);
            if (m.find()) {
                String mon = m.group(1);
                Integer day = Integer.valueOf(m.group(2));

                // Added by hari - try to extract 4-digit year from the string; if not found, use current year
                Integer yearVal = null;
                Matcher my = Pattern.compile('\\b(\\d{4})\\b').matcher(d);
                if (my.find()) yearVal = Integer.valueOf(my.group(1));
                if (yearVal == null) yearVal = Date.today().year();

                Integer monthNum = monthAbbrevToNumber(mon);
                if (monthNum != null) {
                    return Date.newInstance(yearVal, monthNum, day);
                }
            }
        } catch (Exception e) { }

        return null;
    }

    // Added by hari - Month short name to numeric month
    private static Integer monthAbbrevToNumber(String mon) {
        if (String.isBlank(mon)) return null;
        switch on mon {
            when 'Jan' { return 1; }
            when 'Feb' { return 2; }
            when 'Mar' { return 3; }
            when 'Apr' { return 4; }
            when 'May' { return 5; }
            when 'Jun' { return 6; }
            when 'Jul' { return 7; }
            when 'Aug' { return 8; }
            when 'Sep' { return 9; }
            when 'Oct' { return 10; }
            when 'Nov' { return 11; }
            when 'Dec' { return 12; }
            when else { return null; }
        }
    }

    private static void attachEInvoicePdfToInvoice(Id invoiceId) {
        String criteriasJson = InvoiceToCygnetMapper.buildEInvoicePdfCriterias(invoiceId);
        // Added by hari - Debug PDF export payload
        try {
            System.debug('Cygnet E-Invoice PDF criteriasJson=' + (criteriasJson != null && criteriasJson.length() > 1500 ? criteriasJson.substring(0, 1500) + '...TRUNC' : criteriasJson));
        } catch (Exception e) { }
        // Added by hari (Under SS)
        String base64Pdf = CygnetApiService.exportEInvoicePdf(criteriasJson, invoiceId);
        List<Invoice__c> invs = [SELECT Invoice_Number__c FROM Invoice__c WHERE Id = :invoiceId LIMIT 1];
        String title = invs.isEmpty() ? 'E-Invoice' : ('E-Invoice_' + (invs[0].Invoice_Number__c != null ? invs[0].Invoice_Number__c : invoiceId));
        createContentVersionAndLink(invoiceId, base64Pdf, title, 'E-Invoice.pdf');
    }

    private static void attachEwayBillPdfToInvoice(Id invoiceId) {
        String criteriasJson = InvoiceToCygnetMapper.buildEwayBillPdfCriterias(invoiceId);
        // Added by hari (Under SS)
        String base64Pdf = CygnetApiService.exportEwayBillPdf(criteriasJson, invoiceId);
        List<Invoice__c> invs = [SELECT Invoice_Number__c FROM Invoice__c WHERE Id = :invoiceId LIMIT 1];
        String title = invs.isEmpty() ? 'E-Way Bill' : ('E-Way Bill_' + (invs[0].Invoice_Number__c != null ? invs[0].Invoice_Number__c : invoiceId));
        createContentVersionAndLink(invoiceId, base64Pdf, title, 'E-Way-Bill.pdf');
    }

    private static void createContentVersionAndLink(Id invoiceId, String base64Pdf, String title, String fileName) {
        if (String.isBlank(base64Pdf)) {
            throw new AuraHandledException('PDF content is empty.');
        }
        ContentVersion cv = new ContentVersion();
        cv.Title = title;
        cv.PathOnClient = fileName;
        cv.VersionData = EncodingUtil.base64Decode(base64Pdf);
        cv.Origin = 'H';
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = cv.ContentDocumentId;
        cdl.LinkedEntityId = invoiceId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;
    }
}