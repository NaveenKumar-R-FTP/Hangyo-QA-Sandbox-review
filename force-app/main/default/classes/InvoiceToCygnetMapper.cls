// Added by Hari - Maps Invoice__c and Invoice_Line_Item__c to Cygnet E-Invoice & E-Way Bill payloads per requirement.
// Added by Hari - Secondary_Invoice: Seller details from Distributor_Account__c (Under_SS__c optional legacy); Under_SS_GSTIN__c = optional seller GSTIN override on Invoice; Buyer = Retailer.
// Added by Hari - Secondary_Invoice_Under_SS: Seller = Distributor (Superstockist), Buyer = Under SS (Under_SS__c / Under_SS_GSTIN__c).
// DocDtls from Invoice__c; ItemList from Invoice_Line_Item__c + Product; ValDtls calculated.
public with sharing class InvoiceToCygnetMapper {
    private static final String RECORDTYPE_SECONDARY_INVOICE_DEVNAME = 'Secondary_Invoice';
    private static final String RECORDTYPE_SECONDARY_INVOICE_UNDER_SS_DEVNAME = 'Secondary_Invoice_Under_SS';

    // Added by Hari - Wrappers for Cygnet request bodies; same JSON shape as before, no logic change
    public class CygnetEinvoiceRequestWrapper {
        public String locationGstin;
        public String locationName;
        public Integer returnPeriod;
        public String autoPushOrGenerate;
        public Map<String, Object> data;
    }
    public class CygnetEwayBillRequestWrapper {
        public Map<String, Object> data;
    }
    public class CygnetPdfCriteriasWrapper {
        public List<Map<String, Object>> criterias;
    }

    // Added by hari (Under SS) - Match CygnetApiService: Secondary Invoice uses Cygnet_Integration_Setting__c; Under SS uses Cygnet_Integration_Setting_Under_SS__c
    private static void assertCygnetHierarchySettingConfigured(Invoice__c inv) {
        Boolean underSs = inv.RecordType != null
            && RECORDTYPE_SECONDARY_INVOICE_UNDER_SS_DEVNAME.equalsIgnoreCase(inv.RecordType.DeveloperName);
        if (underSs) {
            Cygnet_Integration_Setting_Under_SS__c u = Cygnet_Integration_Setting_Under_SS__c.getInstance(UserInfo.getUserId());
            if (u == null) u = Cygnet_Integration_Setting_Under_SS__c.getInstance();
            if (u == null) {
                throw new InvoiceToCygnetMapperException('Cygnet Integration Setting (Under SS) is not configured.');
            }
        } else {
            Cygnet_Integration_Setting__c s = Cygnet_Integration_Setting__c.getInstance(UserInfo.getUserId());
            if (s == null) s = Cygnet_Integration_Setting__c.getInstance();
            if (s == null) {
                throw new InvoiceToCygnetMapperException('Cygnet Integration Setting is not configured.');
            }
        }
    }

    // Added by Hari - Build full E-Invoice save request (autoPushOrGenerate = EINV) per FR-1
    public static String buildEInvoiceSaveBody(Id invoiceId) {
        // Secondary_Invoice: Distributor seller + Retailer buyer. Secondary_Invoice_Under_SS: Distributor seller + Under SS buyer.
        List<Invoice__c> invs = [
            SELECT Id, Name, Invoice_Number__c, Invoice_Date__c, RecordType.DeveloperName,
                Retailer_GSTIN__c, Under_SS__c, Under_SS_GSTIN__c, Customer_Name__c, Place_of_Supply__c, Taxable_Amount__c,
                CGST_Amount__c, SGST_Amount__c, IGST_Amount__c, Invoice_Total__c, Total_Discount__c,
                Cygnet_Buyer_PIN__c,
                Retailer_Account__c,
                Retailer_Account__r.Name, Retailer_Account__r.GSTIN__c,
                Retailer_Account__r.BillingStreet, Retailer_Account__r.BillingCity, Retailer_Account__r.BillingPostalCode,
                Retailer_Account__r.BillingState, Retailer_Account__r.Phone,
                Retailer_Account__r.Primary_Address_1__c, Retailer_Account__r.Primary_Address_2__c, Retailer_Account__r.Primary_City__c, Retailer_Account__r.Primary_PINCode__c,
                Retailer_Account__r.Primary_State_Code__c, Retailer_Account__r.Primary_State__c, Retailer_Account__r.Email__c,
                Distributor_Account__c,
                Distributor_Account__r.Name, Distributor_Account__r.GSTIN__c,
                Distributor_Account__r.BillingStreet, Distributor_Account__r.BillingCity, Distributor_Account__r.BillingPostalCode,
                Distributor_Account__r.BillingState, Distributor_Account__r.Phone,
                Distributor_Account__r.Primary_Address_1__c, Distributor_Account__r.Primary_Address_2__c, Distributor_Account__r.Primary_City__c, Distributor_Account__r.Primary_PINCode__c,
                Distributor_Account__r.Primary_State_Code__c, Distributor_Account__r.Primary_State__c, Distributor_Account__r.Email__c,
                Under_SS__r.Name, Under_SS__r.GSTIN__c,
                Under_SS__r.BillingStreet, Under_SS__r.BillingCity, Under_SS__r.BillingPostalCode,
                Under_SS__r.BillingState, Under_SS__r.Phone,
                Under_SS__r.Primary_Address_1__c, Under_SS__r.Primary_Address_2__c, Under_SS__r.Primary_City__c, Under_SS__r.Primary_PINCode__c,
                Under_SS__r.Primary_State_Code__c, Under_SS__r.Primary_State__c, Under_SS__r.Email__c
            FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
        ];

        System.debug('invs: ' + invs);

        if (invs.isEmpty()) throw new InvoiceToCygnetMapperException('Invoice not found.');
        Invoice__c inv = invs[0];
        // Added by hari (Under SS) - Require Cygnet_Integration_Setting_Under_SS__c for Secondary_Invoice_Under_SS; else Cygnet_Integration_Setting__c
        assertCygnetHierarchySettingConfigured(inv);
        List<Invoice_Line_Item__c> lines = [
            SELECT Id, Product__c, Quantity__c, Price__c, CGST_Amount__c, SGST_Amount__c, IGST_Amount__c
            FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId ORDER BY Name
        ];
        if (lines.isEmpty()) throw new InvoiceToCygnetMapperException('At least one Invoice Line Item is required.');

        // Added by Hari - HSN column name varies on Product__c by org; load products with first matching HSN field
        String hsnFieldApi = resolveProductHsnFieldName();
        Map<Id, SObject> productById = loadProductsForLines(lines, hsnFieldApi);

        String docNo = String.isNotBlank(inv.Invoice_Number__c) ? inv.Invoice_Number__c : inv.Name;
        String docDt = formatDate(inv.Invoice_Date__c);
        if (String.isBlank(docDt)) docDt = formatDate(Date.today());

        Decimal totInvVal = inv.Invoice_Total__c != null ? inv.Invoice_Total__c : 0;
        if (totInvVal == 0 && inv.Taxable_Amount__c != null) totInvVal = inv.Taxable_Amount__c + (inv.CGST_Amount__c != null ? inv.CGST_Amount__c : 0) + (inv.SGST_Amount__c != null ? inv.SGST_Amount__c : 0) + (inv.IGST_Amount__c != null ? inv.IGST_Amount__c : 0);
        Decimal assVal = inv.Taxable_Amount__c != null ? inv.Taxable_Amount__c : 0;
        Decimal cgstVal = inv.CGST_Amount__c != null ? inv.CGST_Amount__c : 0;
        Decimal sgstVal = inv.SGST_Amount__c != null ? inv.SGST_Amount__c : 0;
        Decimal igstVal = inv.IGST_Amount__c != null ? inv.IGST_Amount__c : 0;
        Decimal discountVal = inv.Total_Discount__c != null ? inv.Total_Discount__c : 0;

        // Added by hari - Build seller/buyer before ItemList so interstate tax + IGST/CGST/SGST rules apply per Cygnet VAL0050
        Boolean isUnderSsScenario = inv.RecordType != null &&
            RECORDTYPE_SECONDARY_INVOICE_UNDER_SS_DEVNAME.equalsIgnoreCase(inv.RecordType.DeveloperName);

        Map<String, Object> sellerDtlsMap = isUnderSsScenario
            ? buildSellerDtlsFromDistributor(inv)
            : buildSellerDtlsFromUnderSS(inv);
        String sellerState = normalizeStateCodeTwoDigit((String) sellerDtlsMap.get('Stcd'));
        if (String.isBlank(sellerState)) sellerState = '29';
        Map<String, Object> buyerDtlsMap = isUnderSsScenario
            ? buildBuyerDtlsFromUnderSS(inv)
            : buildBuyerDtlsFromRetailer(inv);
        String buyerState = normalizeStateCodeTwoDigit((String) buyerDtlsMap.get('Stcd'));
        if (String.isBlank(buyerState)) buyerState = '29';
        Boolean interstate = sellerState != buyerState;

        // FIX: For IGST case, POS must match Seller State (VAL0374)
        if (interstate) {
            // buyerState = sellerState;
             buyerDtlsMap.put('Pos', sellerState);
        }

        // Added by hari (Integration tax issue) - Line ItemList + ValDtls tax totals are derived in the loop from TotAmt × snapped Rate (VAL0052); header cgst/sgst/igst below are overwritten after the loop.

        List<Map<String, Object>> itemList = new List<Map<String, Object>>();
        Decimal sumLineAss = 0;
        Decimal sumLineCgst = 0;
        Decimal sumLineSgst = 0;
        Decimal sumLineIgst = 0;
        Decimal sumLineTotItem = 0;
        Integer slNo = 1;
        for (Invoice_Line_Item__c line : lines) {
            Decimal qty = line.Quantity__c != null ? line.Quantity__c : 0;
            Decimal unitPrice = line.Price__c != null ? line.Price__c : 0;
            Decimal totAmt = (qty * unitPrice);
            // Added by hari (Fetch GST values from the invoice line item and IGST = CGST + SGST)
            // Use stored line tax amounts, but normalize for interstate/intrastate to satisfy NIC/Cygnet rules (e.g., VAL0050).
            Decimal igst = line.IGST_Amount__c != null ? line.IGST_Amount__c : 0;
            Decimal cgst = line.CGST_Amount__c != null ? line.CGST_Amount__c : 0;
            Decimal sgst = line.SGST_Amount__c != null ? line.SGST_Amount__c : 0;
            if (interstate) {
                igst = igst + cgst + sgst;
                cgst = 0;
                sgst = 0;
            } else {
                igst = 0;
            }

            // Derive GST rate from stored line tax and taxable amount; snap to NIC slab for payload rate fields.
            Decimal gstRtRaw = totAmt != 0 ? ((igst + cgst + sgst) / totAmt * 100) : 0;
            Decimal gstRt = snapGstRtToNicRateMaster(gstRtRaw);
            SObject prod = (line.Product__c != null) ? productById.get(line.Product__c) : null;
            String hsn = '0';
            if (prod != null && String.isNotBlank(hsnFieldApi)) {
                Object hv = prod.get(hsnFieldApi);
                if (hv != null) hsn = String.valueOf(hv).replaceAll('\\.0$', '');
            }
            String prdDesc = 'Item';
            if (prod != null) {
                Object nm = prod.get('Name');
                if (nm != null && String.isNotBlank(String.valueOf(nm))) prdDesc = String.valueOf(nm);
            }
            itemList.add(new Map<String, Object>{
                'SlNo' => String.valueOf(slNo++),
                'PrdDesc' => prdDesc,
                'IsServc' => 'N',
                'HsnCd' => hsn,
                'Qty' => qty,
                'Unit' => 'NOS',
                'UnitPrice' => unitPrice,
                'TotAmt' => totAmt,
                'AssAmt' => totAmt,
                'GstRt' => gstRt,
                // Added by hari - Cygnet validates Items[].Rate against Rate Master (same slab as GstRt)
                'Rate' => gstRt,
                'IgstAmt' => igst,
                'CgstAmt' => cgst,
                'SgstAmt' => sgst,
                'TotItemVal' => totAmt + igst + cgst + sgst
            });
            // added by hari (Integration tax issue) - Roll up for ValDtls to match ItemList (NIC/Cygnet header vs line checks)
            sumLineAss += totAmt;
            sumLineCgst += cgst;
            sumLineSgst += sgst;
            sumLineIgst += igst;
            sumLineTotItem += (totAmt + igst + cgst + sgst);
        }

        assVal = sumLineAss;
        cgstVal = sumLineCgst;
        sgstVal = sumLineSgst;
        igstVal = sumLineIgst;
        // added by hari (Integration tax issue) - VAL0363: TotInvVal = sum(TotItemVal) - Discount + OthChrg + RndOff (must match Cygnet Document Value formula)
        Decimal othChrgVal = 0;
        Decimal rndOffVal = 0;
        totInvVal = sumLineTotItem - (discountVal != null ? discountVal : 0) + othChrgVal + rndOffVal;
        totInvVal = totInvVal.setScale(2, System.RoundingMode.HALF_UP);

        Map<String, Object> data = new Map<String, Object>{
            'Version' => '1.1',
            'TranDtls' => new Map<String, Object>{
                'TaxSch' => 'GST',
                'SupTyp' => 'B2B',
                'RegRev' => 'N',
                'EcmGstin' => null,
                // Added by hari - Keep prior Cygnet/NIC mapping; tax split fixed separately for interstate (VAL0050)
                'IgstOnIntra' => sellerState == buyerState ? 'N' : 'Y'
            },

            'DocDtls' => new Map<String, Object>{ 'Typ' => 'INV', 'No' => docNo, 'Dt' => docDt },
            'SellerDtls' => sellerDtlsMap,
            'BuyerDtls' => buyerDtlsMap,
            'ItemList' => itemList,
            'ValDtls' => new Map<String, Object>{
                'AssVal' => assVal,
                'CgstVal' => cgstVal,
                'SgstVal' => sgstVal,
                'IgstVal' => igstVal,
                'Discount' => discountVal,
                'OthChrg' => othChrgVal,
                'RndOffAmt' => rndOffVal,
                'TotInvVal' => totInvVal,
                'TotInvValFc' => totInvVal
            }
        };
        // Added by Hari - Return period always from Invoice date (no Custom Setting); format MMMYYYY as number e.g. 22026 = Feb 2026
        Integer returnPeriod = 112020;
        if (inv.Invoice_Date__c != null) {
            returnPeriod = inv.Invoice_Date__c.month() * 10000 + inv.Invoice_Date__c.year();
        } else {
            Date today = Date.today();
            returnPeriod = today.month() * 10000 + today.year();
        }
        // Added by Hari - Scenario 2: Location = Seller (Under SS): use seller GSTIN and name for locationGstin/locationName
        CygnetEinvoiceRequestWrapper w = new CygnetEinvoiceRequestWrapper();
        w.locationGstin = (String) sellerDtlsMap.get('Gstin');
        if (w.locationGstin == null) w.locationGstin = '';
        w.locationName = (String) sellerDtlsMap.get('LglNm');
        if (w.locationName == null) w.locationName = '';
        w.returnPeriod = returnPeriod;
        w.autoPushOrGenerate = 'EINV';
        w.data = data;
        return JSON.serialize(w);
    }

    // Added by Hari - Build E-Way Bill by IRN (PartBDtls: Irn + transport details) per FR-2
    public static String buildEwayBillByIrnBody(Id invoiceId) {
        List<Invoice__c> invs = [
            SELECT Id, IRN_Number__c, Transporter_Name__c, Transporter_Doc_Number__c, Transporter_Doc_Date__c,
                Vehicle_Number__c, Transport_Mode__c, Transport_Distance__c,
                Invoice_Number__c, Invoice_Date__c,
                Distributor_Account__r.GSTIN__c
            FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
        ];
        if (invs.isEmpty()) throw new InvoiceToCygnetMapperException('Invoice not found.');
        Invoice__c inv = invs[0];
        String irn = inv.IRN_Number__c != null ? String.valueOf(inv.IRN_Number__c).trim() : '';
        if (String.isBlank(irn)) throw new InvoiceToCygnetMapperException('IRN is blank. Generate E-Invoice first.');
        String transName = String.isNotBlank(inv.Transporter_Name__c) ? inv.Transporter_Name__c : '';
        String vehNo = String.isNotBlank(inv.Vehicle_Number__c) ? inv.Vehicle_Number__c : '';
        String transMode = '1';
        if (String.isNotBlank(inv.Transport_Mode__c)) {
            String m = inv.Transport_Mode__c.toUpperCase();
            if (m.contains('RAIL') || m == '2') transMode = '2';
            else if (m.contains('AIR') || m == '3') transMode = '3';
            else if (m.contains('SHIP') || m == '4') transMode = '4';
        }
        Integer distance = (inv.Transport_Distance__c != null && inv.Transport_Distance__c > 0) ? Integer.valueOf(inv.Transport_Distance__c) : 0;

        // Added by hari - E-Way Bill 'Transport Document Number/Date' validation (Cygnet: doc no length 1..15)
        String transDocNo = String.isNotBlank(inv.Transporter_Doc_Number__c) ? inv.Transporter_Doc_Number__c.trim() : '';
        if (String.isBlank(transDocNo)) {
            transDocNo = String.isNotBlank(inv.Invoice_Number__c) ? inv.Invoice_Number__c.trim() : '';
        }
        if (!String.isBlank(transDocNo) && transDocNo.length() > 15) {
            transDocNo = transDocNo.substring(0, 15);
        }

        Date transDocDt = (inv.Transporter_Doc_Date__c != null) ? inv.Transporter_Doc_Date__c : inv.Invoice_Date__c;
        // keep transDocDt null if not available; Cygnet will validate
        String transDocDtStr = transDocDt != null ? formatDate(transDocDt) : '';

        List<Map<String, Object>> partB = new List<Map<String, Object>>();
        Map<String, Object> partBRow = new Map<String, Object>{
            'Irn' => irn,
            'TransName' => transName,
            'TransMode' => transMode,
            'Distance' => distance,
            'TransDocNo' => transDocNo,
            'TransDocDt' => String.isNotBlank(transDocDtStr) ? transDocDtStr : formatDate(Date.today()),
            'VehNo' => vehNo
        };
        if ('1'.equals(transMode)) {
            partBRow.put('VehType', 'R');
        }
        partB.add(partBRow);
        CygnetEwayBillRequestWrapper w = new CygnetEwayBillRequestWrapper();
        w.data = new Map<String, Object>{ 'PartBDtls' => partB };
        return JSON.serialize(w);
    }

    // Added by Hari - Criterias for E-Invoice PDF export; location/billFrom = Seller (Under SS) GSTIN and name (Scenario 2)
    public static String buildEInvoicePdfCriterias(Id invoiceId) {
        List<Invoice__c> invs = [
            SELECT Id, Name, Invoice_Number__c, Invoice_Date__c, RecordType.DeveloperName, Retailer_GSTIN__c,
                Retailer_Account__r.Name, Retailer_Account__r.GSTIN__c,
                Distributor_Account__r.Name, Distributor_Account__r.GSTIN__c,
                Under_SS_GSTIN__c, Under_SS__r.Name, Under_SS__r.GSTIN__c
            FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
        ];
        if (invs.isEmpty()) throw new InvoiceToCygnetMapperException('Invoice not found.');
        Invoice__c inv = invs[0];

        Boolean isUnderSsScenario = inv.RecordType != null &&
            RECORDTYPE_SECONDARY_INVOICE_UNDER_SS_DEVNAME.equalsIgnoreCase(inv.RecordType.DeveloperName);

        // Secondary_Invoice: location = Distributor seller; Secondary_Invoice_Under_SS: seller=Distributor(Superstockist)
        String locationGstin;
        String locationName;
        if (isUnderSsScenario) {
            locationGstin = (inv.Distributor_Account__r != null && String.isNotBlank(inv.Distributor_Account__r.GSTIN__c))
                ? inv.Distributor_Account__r.GSTIN__c
                : '';
            locationName = (inv.Distributor_Account__r != null && String.isNotBlank(inv.Distributor_Account__r.Name))
                ? inv.Distributor_Account__r.Name
                : '';
        } else {
            locationGstin = String.isNotBlank(inv.Under_SS_GSTIN__c)
                ? inv.Under_SS_GSTIN__c
                : (inv.Distributor_Account__r != null && String.isNotBlank(inv.Distributor_Account__r.GSTIN__c)
                    ? inv.Distributor_Account__r.GSTIN__c
                    : (inv.Under_SS__r != null && String.isNotBlank(inv.Under_SS__r.GSTIN__c) ? inv.Under_SS__r.GSTIN__c : ''));
            locationName = (inv.Distributor_Account__r != null && String.isNotBlank(inv.Distributor_Account__r.Name))
                ? inv.Distributor_Account__r.Name
                : (inv.Under_SS__r != null && String.isNotBlank(inv.Under_SS__r.Name) ? inv.Under_SS__r.Name : '');
        }
        String docNo = String.isNotBlank(inv.Invoice_Number__c) ? inv.Invoice_Number__c : inv.Name;
        String docDt = formatDateForPdf(inv.Invoice_Date__c);
        if (String.isBlank(docDt)) docDt = formatDateForPdf(Date.today());
        List<Map<String, Object>> criterias = new List<Map<String, Object>>();
        criterias.add(new Map<String, Object>{
            'locationGstin' => locationGstin,
            'locationName' => locationName,
            'documentNumber' => docNo,
            'documentDate' => docDt,
            'supplyType' => 'S',
            'documentType' => 'INV',
            'billFromGstin' => locationGstin,
            'portCode' => null
        });
        CygnetPdfCriteriasWrapper w = new CygnetPdfCriteriasWrapper();
        w.criterias = criterias;
        return JSON.serialize(w);
    }

    public static String buildEwayBillPdfCriterias(Id invoiceId) {
        return buildEInvoicePdfCriterias(invoiceId);
    }

    // Added by Hari - Secondary_Invoice seller: Distributor_Account__c (Under_SS__c optional fallback for legacy records)
    private static Map<String, Object> buildSellerDtlsFromUnderSS(Invoice__c inv) {
        if (inv == null) {
            throw new InvoiceToCygnetMapperException('Distributor Account is required on the Invoice for E-Invoice.');
        }
        Account acc = inv.Distributor_Account__r;
        if (acc == null && inv.Under_SS__r != null) {
            acc = inv.Under_SS__r;
        }
        if (acc == null) {
            throw new InvoiceToCygnetMapperException('Distributor Account is required on the Invoice for E-Invoice.');
        }
        String gstin = String.isNotBlank(inv.Under_SS_GSTIN__c) ? inv.Under_SS_GSTIN__c : (String.isNotBlank(acc.GSTIN__c) ? acc.GSTIN__c : '');
        // Added by hari - Stcd from GSTIN first (matches Cygnet POS / state master VAL0315)
        String stcd = stateCodeFromGstin(gstin);
        if (String.isBlank(stcd)) stcd = deriveStateCodeFromAccount(acc);
        stcd = normalizeStateCodeTwoDigit(stcd);
        if (String.isBlank(stcd)) stcd = '29';
        String addr1 = String.isNotBlank(acc.Primary_Address_1__c) ? acc.Primary_Address_1__c : (String.isNotBlank(acc.BillingStreet) ? acc.BillingStreet : '');
        // Added by hari - Cygnet minimum length BillFromAddress1
        if (String.isBlank(addr1) || addr1.length() < 3) addr1 = 'N/A';
        String addr2 = String.isNotBlank(acc.Primary_Address_2__c) ? acc.Primary_Address_2__c : '';
        // Added by hari - Cygnet minimum length on BillFromAddress2
        addr2 = ensureMinLenAddressLine(addr2, addr1);
        String loc = String.isNotBlank(acc.Primary_City__c) ? acc.Primary_City__c : (String.isNotBlank(acc.BillingCity) ? acc.BillingCity : '');
        // Added by hari - Cygnet minimum length on seller city/location
        if (String.isBlank(loc) || loc.length() < 3) loc = 'N/A';
        Integer pin = 0;
        if (acc.Primary_PINCode__c != null) {
            try {
                String pinStr = String.valueOf(acc.Primary_PINCode__c).replaceAll('[^0-9]', '');
                if (pinStr.length() > 6) pinStr = pinStr.substring(0, 6);
                if (String.isNotBlank(pinStr)) pin = Integer.valueOf(pinStr);
            } catch (Exception e) { }
        }
        if (pin == 0 && acc.BillingPostalCode != null) {
            try {
                String pinStr = String.valueOf(acc.BillingPostalCode).replaceAll('[^0-9]', '');
                if (pinStr.length() > 6) pinStr = pinStr.substring(0, 6);
                if (String.isNotBlank(pinStr)) pin = Integer.valueOf(pinStr);
            } catch (Exception ex) { }
        }
        String ph = String.isNotBlank(acc.Phone) ? acc.Phone : '';
        String em = (acc.Email__c != null && String.isNotBlank(String.valueOf(acc.Email__c))) ? String.valueOf(acc.Email__c) : '';
        // Added by hari - Cygnet minimum length BillFromPhone / BillFromEmail
        if (String.isBlank(ph) || ph.replaceAll('[^0-9]', '').length() < 6) ph = '9999999999';
        if (String.isBlank(em) || em.length() < 6) em = 'na@a.co';
        return new Map<String, Object>{
            'Gstin' => gstin,
            'LglNm' => String.isNotBlank(acc.Name) ? acc.Name : '',
            'TrdNm' => String.isNotBlank(acc.Name) ? acc.Name : '',
            'Addr1' => addr1,
            'Addr2' => addr2,
            'Loc' => loc,
            'Pin' => pin,
            'Stcd' => stcd,
            'Ph' => ph,
            'Em' => em
        };
    }

    // Secondary_Invoice_Under_SS: Seller = Distributor account (Superstockist)
    private static Map<String, Object> buildSellerDtlsFromDistributor(Invoice__c inv) {
        if (inv == null || inv.Distributor_Account__r == null) {
            throw new InvoiceToCygnetMapperException('Distributor (Superstockist Seller) Account is required on the Invoice for E-Invoice.');
        }
        Account acc = inv.Distributor_Account__r;
        String gstin = String.isNotBlank(acc.GSTIN__c) ? acc.GSTIN__c : '';
        String stcd = stateCodeFromGstin(gstin);
        if (String.isBlank(stcd)) stcd = deriveStateCodeFromAccount(acc);
        stcd = normalizeStateCodeTwoDigit(stcd);
        if (String.isBlank(stcd)) stcd = '29';
        String addr1 = String.isNotBlank(acc.Primary_Address_1__c) ? acc.Primary_Address_1__c : (String.isNotBlank(acc.BillingStreet) ? acc.BillingStreet : '');
        if (String.isBlank(addr1) || addr1.length() < 3) addr1 = 'N/A';
        String addr2 = String.isNotBlank(acc.Primary_Address_2__c) ? acc.Primary_Address_2__c : '';
        addr2 = ensureMinLenAddressLine(addr2, addr1);
        String loc = String.isNotBlank(acc.Primary_City__c) ? acc.Primary_City__c : (String.isNotBlank(acc.BillingCity) ? acc.BillingCity : '');
        if (String.isBlank(loc) || loc.length() < 3) loc = 'N/A';
        Integer pin = 0;
        if (acc.Primary_PINCode__c != null) {
            try {
                String pinStr = String.valueOf(acc.Primary_PINCode__c).replaceAll('[^0-9]', '');
                if (pinStr.length() > 6) pinStr = pinStr.substring(0, 6);
                if (String.isNotBlank(pinStr)) pin = Integer.valueOf(pinStr);
            } catch (Exception e) { }
        }
        if (pin == 0 && acc.BillingPostalCode != null) {
            try {
                String pinStr = String.valueOf(acc.BillingPostalCode).replaceAll('[^0-9]', '');
                if (pinStr.length() > 6) pinStr = pinStr.substring(0, 6);
                if (String.isNotBlank(pinStr)) pin = Integer.valueOf(pinStr);
            } catch (Exception ex) { }
        }
        String ph = String.isNotBlank(acc.Phone) ? acc.Phone : '';
        String em = (acc.Email__c != null && String.isNotBlank(String.valueOf(acc.Email__c))) ? String.valueOf(acc.Email__c) : '';
        if (String.isBlank(ph) || ph.replaceAll('[^0-9]', '').length() < 6) ph = '9999999999';
        if (String.isBlank(em) || em.length() < 6) em = 'na@a.co';
        return new Map<String, Object>{
            'Gstin' => gstin,
            'LglNm' => String.isNotBlank(acc.Name) ? acc.Name : '',
            'TrdNm' => String.isNotBlank(acc.Name) ? acc.Name : '',
            'Addr1' => addr1,
            'Addr2' => addr2,
            'Loc' => loc,
            'Pin' => pin,
            'Stcd' => stcd,
            'Ph' => ph,
            'Em' => em
        };
    }

    // Secondary_Invoice_Under_SS only: Buyer = Under_SS__c; GSTIN = Under_SS_GSTIN__c then Under_SS__r.GSTIN__c (same pattern as buildSellerDtlsFromUnderSS for Secondary_Invoice seller).
    private static Map<String, Object> buildBuyerDtlsFromUnderSS(Invoice__c inv) {
        if (inv == null || inv.Under_SS__r == null) {
            throw new InvoiceToCygnetMapperException('Under SS (Buyer) Account is required on the Invoice for E-Invoice.');
        }
        Account acc = inv.Under_SS__r;
        String gstin = String.isNotBlank(inv.Under_SS_GSTIN__c) ? inv.Under_SS_GSTIN__c : (String.isNotBlank(acc.GSTIN__c) ? acc.GSTIN__c : '');
        String buyerState = stateCodeFromGstin(gstin);
        if (String.isBlank(buyerState)) buyerState = deriveStateCode(inv.Place_of_Supply__c, acc);
        buyerState = normalizeStateCodeTwoDigit(buyerState);
        if (String.isBlank(buyerState)) buyerState = '29';
        String addr1 = String.isNotBlank(acc.Primary_Address_1__c) ? acc.Primary_Address_1__c : (String.isNotBlank(acc.BillingStreet) ? acc.BillingStreet : '');
        if (String.isBlank(addr1) || addr1.length() < 3) addr1 = 'N/A';
        String city = String.isNotBlank(acc.Primary_City__c) ? acc.Primary_City__c : (String.isNotBlank(acc.BillingCity) ? acc.BillingCity : (String.isNotBlank(inv.Place_of_Supply__c) ? inv.Place_of_Supply__c : ''));
        if (String.isBlank(city) || city.replaceAll('[^0-9A-Za-z]', '').length() < 3) {
            city = String.isNotBlank(acc.BillingCity) && acc.BillingCity.length() >= 3 ? acc.BillingCity : 'N/A';
        }
        String addr2 = String.isNotBlank(acc.Primary_Address_2__c) ? acc.Primary_Address_2__c : '';
        addr2 = ensureMinLenAddressLine(addr2, addr1);
        // Added by hari (Under SS) - Robust PIN parsing: always strip non-digits (handles values like 5,77,004) and keep as 6-digit string
        String pin = '';
        String pinBranch = '';
        if (String.isNotBlank(inv.Cygnet_Buyer_PIN__c)) {
            try {
                String pinStr = String.valueOf(inv.Cygnet_Buyer_PIN__c).replaceAll('[^0-9]', '');
                if (pinStr.length() > 6) pinStr = pinStr.substring(0, 6);
                if (pinStr.length() == 6) {
                    pin = pinStr;
                    pinBranch = 'INVOICE_CYGNET_BUYER_PIN';
                }
            } catch (Exception e) { }
        }
        if (String.isBlank(pin) && acc.Primary_PINCode__c != null) {
            try {
                String pinStr = String.valueOf(acc.Primary_PINCode__c).replaceAll('[^0-9]', '');
                if (pinStr.length() > 6) pinStr = pinStr.substring(0, 6);
                if (pinStr.length() == 6) {
                    pin = pinStr;
                    pinBranch = 'PRIMARY_PINCODE';
                }
            } catch (Exception e) { }
        }
        if (String.isBlank(pin) && acc.BillingPostalCode != null) {
            try {
                String pinStr = String.valueOf(acc.BillingPostalCode).replaceAll('[^0-9]', '');
                if (pinStr.length() > 6) pinStr = pinStr.substring(0, 6);
                if (pinStr.length() == 6) {
                    pin = pinStr;
                    pinBranch = 'BILLING_POSTALCODE';
                }
            } catch (Exception ex) { }
        }
        // Added by hari (Under SS) - Fallback: if still blank, default BillToPincode to 575004 as per requirement
        if (String.isBlank(pin)) {
            pin = '575004';
            pinBranch = 'FALLBACK_575004';
        }
        System.debug(LoggingLevel.DEBUG,
            'buildBuyerDtlsFromUnderSS Cygnet_Buyer_PIN__c=' + inv.Cygnet_Buyer_PIN__c
            + ', Primary_PINCode__c=' + acc.Primary_PINCode__c
            + ', BillingPostalCode=' + acc.BillingPostalCode
            + ', branch=' + pinBranch
            + ', pin=' + pin
        );

        String ph = String.isNotBlank(acc.Phone) ? acc.Phone : '';
        String em = (acc.Email__c != null && String.isNotBlank(String.valueOf(acc.Email__c))) ? String.valueOf(acc.Email__c) : '';
        if (String.isBlank(ph) || ph.replaceAll('[^0-9]', '').length() < 6) ph = '9999999999';
        if (String.isBlank(em) || em.length() < 6) em = 'na@a.co';
        String lglNm = String.isNotBlank(acc.Name) ? acc.Name : '';
        String trdNm = lglNm;
        if (String.isBlank(trdNm) || trdNm.length() < 3) trdNm = 'N/A';
        return new Map<String, Object>{
            'Gstin' => gstin,
            'LglNm' => lglNm,
            'TrdNm' => trdNm,
            'Pos' => buyerState,
            'Addr1' => addr1,
            'Addr2' => addr2,
            'Loc' => city,
            'Pin' => pin,
            'Stcd' => buyerState,
            'Ph' => ph,
            'Em' => em
        };
    }

    // Added by Hari - Scenario 2: Build BuyerDtls from Retailer (Retailer_Account__c on Invoice) — Secondary_Invoice only (via isUnderSsScenario branch).
    private static Map<String, Object> buildBuyerDtlsFromRetailer(Invoice__c inv) {
        if (inv == null || inv.Retailer_Account__r == null) {
            throw new InvoiceToCygnetMapperException('Retailer (Buyer) Account is required on the Invoice for E-Invoice.');
        }
        Account acc = inv.Retailer_Account__r;
        String gstin = String.isNotBlank(inv.Retailer_GSTIN__c) ? inv.Retailer_GSTIN__c : (String.isNotBlank(acc.GSTIN__c) ? acc.GSTIN__c : '');
        // Added by hari - POS / BillToStateCode from GSTIN prefix first (VAL0315)
        String buyerState = stateCodeFromGstin(gstin);
        if (String.isBlank(buyerState)) buyerState = deriveStateCode(inv.Place_of_Supply__c, acc);
        buyerState = normalizeStateCodeTwoDigit(buyerState);
        if (String.isBlank(buyerState)) buyerState = '29';
        String addr1 = String.isNotBlank(acc.Primary_Address_1__c) ? acc.Primary_Address_1__c : (String.isNotBlank(acc.BillingStreet) ? acc.BillingStreet : '');
        // Added by hari - Cygnet minimum length BillToAddress1
        if (String.isBlank(addr1) || addr1.length() < 3) addr1 = 'N/A';
        String city = String.isNotBlank(acc.Primary_City__c) ? acc.Primary_City__c : (String.isNotBlank(acc.BillingCity) ? acc.BillingCity : (String.isNotBlank(inv.Place_of_Supply__c) ? inv.Place_of_Supply__c : ''));
        // Added by hari - Cygnet minimum length BillToCity
        if (String.isBlank(city) || city.replaceAll('[^0-9A-Za-z]', '').length() < 3) {
            city = String.isNotBlank(acc.BillingCity) && acc.BillingCity.length() >= 3 ? acc.BillingCity : 'N/A';
        }
        String addr2 = String.isNotBlank(acc.Primary_Address_2__c) ? acc.Primary_Address_2__c : '';
        // Added by hari - Cygnet minimum length BillToAddress2
        addr2 = ensureMinLenAddressLine(addr2, addr1);
        Integer pin = 0;
        if (acc.Primary_PINCode__c != null) {
            try {
                String pinStr = String.valueOf(acc.Primary_PINCode__c).replaceAll('[^0-9]', '');
                if (pinStr.length() > 6) pinStr = pinStr.substring(0, 6);
                if (String.isNotBlank(pinStr)) pin = Integer.valueOf(pinStr);
            } catch (Exception e) { }
        }
        if (pin == 0 && acc.BillingPostalCode != null) {
            try {
                String pinStr = String.valueOf(acc.BillingPostalCode).replaceAll('[^0-9]', '');
                if (pinStr.length() > 6) pinStr = pinStr.substring(0, 6);
                if (String.isNotBlank(pinStr)) pin = Integer.valueOf(pinStr);
            } catch (Exception ex) { }
        }
        String ph = String.isNotBlank(acc.Phone) ? acc.Phone : '';
        String em = (acc.Email__c != null && String.isNotBlank(String.valueOf(acc.Email__c))) ? String.valueOf(acc.Email__c) : '';
        // Added by hari - Cygnet minimum length BillToPhone / BillToEmail
        if (String.isBlank(ph) || ph.replaceAll('[^0-9]', '').length() < 6) ph = '9999999999';
        if (String.isBlank(em) || em.length() < 6) em = 'na@a.co';
        String lglNm = String.isNotBlank(acc.Name) ? acc.Name : '';
        // Added by hari - BillToTradeName must match legal/trade name (was blank)
        String trdNm = lglNm;
        if (String.isBlank(trdNm) || trdNm.length() < 3) trdNm = 'N/A';
        return new Map<String, Object>{
            'Gstin' => gstin,
            'LglNm' => lglNm,
            'TrdNm' => trdNm,
            'Pos' => buyerState,
            'Addr1' => addr1,
            'Addr2' => addr2,
            'Loc' => city,
            'Pin' => pin,
            'Stcd' => buyerState,
            'Ph' => ph,
            'Em' => em
        };
    }

    // Added by hari - First 2 digits of GSTIN = state code for Cygnet master validation
    private static String stateCodeFromGstin(String gstin) {
        if (String.isBlank(gstin) || gstin.length() < 2) return null;
        String prefix = gstin.substring(0, 2);
        if (Pattern.compile('^[0-9]{2}$').matcher(prefix).matches()) {
            return prefix;
        }
        return null;
    }

    // Added by hari - Normalize to 2-digit numeric state code string
    private static String normalizeStateCodeTwoDigit(String st) {
        if (String.isBlank(st)) return null;
        String d = st.replaceAll('[^0-9]', '');
        if (d.length() >= 2) return d.substring(0, 2);
        if (d.length() == 1) return '0' + d;
        return null;
    }

    // Added by hari - Cygnet requires min 3 chars on secondary address lines
    private static String ensureMinLenAddressLine(String preferredLine2, String line1Fallback) {
        if (String.isNotBlank(preferredLine2) && preferredLine2.length() >= 3) return preferredLine2;
        if (String.isNotBlank(line1Fallback) && line1Fallback.length() >= 3) {
            return line1Fallback.length() > 120 ? line1Fallback.substring(0, 120) : line1Fallback;
        }
        return 'N/A';
    }

    // Added by hari - NIC / Cygnet Rate Master (GST slabs); computed % from invoice lines must snap here or VAL0315 fails
    private static final List<Decimal> NIC_GST_RATE_MASTER = new List<Decimal>{
        0,
        Decimal.valueOf('0.10'),
        Decimal.valueOf('0.25'),
        1,
        Decimal.valueOf('1.5'),
        3,
        5,
        6,
        Decimal.valueOf('7.5'),
        12,
        18,
        28
    };

    private static Decimal snapGstRtToNicRateMaster(Decimal effectiveRatePercent) {
        if (effectiveRatePercent == null || effectiveRatePercent <= 0) {
            return 0;
        }
        Decimal r = effectiveRatePercent.setScale(6, System.RoundingMode.HALF_UP);
        Decimal best = 0;
        Decimal bestDiff = Decimal.valueOf('9999');
        for (Decimal slab : NIC_GST_RATE_MASTER) {
            Decimal d = (r - slab).abs();
            if (d < bestDiff) {
                bestDiff = d;
                best = slab;
            }
        }
        // Added by hari - NIC allows up to 3 decimals on rate field
        return best.setScale(3, System.RoundingMode.HALF_UP);
    }

    private static String deriveStateCodeFromAccount(Account acc) {
        if (acc == null) return '29';
        if (String.isNotBlank(acc.Primary_State_Code__c)) {
            String dig = acc.Primary_State_Code__c.replaceAll('[^0-9]', '');
            if (dig.length() >= 2) return dig.length() > 2 ? dig.substring(0, 2) : dig;
        }
        if (String.isNotBlank(acc.Primary_State__c)) {
            String dig = acc.Primary_State__c.replaceAll('[^0-9]', '');
            if (dig.length() >= 2) return dig.substring(0, 2);
        }
        if (String.isNotBlank(acc.BillingState)) {
            String dig = acc.BillingState.replaceAll('[^0-9]', '');
            if (dig.length() >= 2) return dig.substring(0, 2);
        }
        return '29';
    }

    private static String deriveStateCode(String placeOfSupply, Account acc) {
        if (String.isNotBlank(placeOfSupply) && placeOfSupply.length() >= 2) {
            String dig = placeOfSupply.replaceAll('[^0-9]', '');
            if (dig.length() >= 2) return dig.substring(0, 2);
        }
        if (acc != null) {
            if (String.isNotBlank(acc.Primary_State_Code__c)) {
                String dig = acc.Primary_State_Code__c.replaceAll('[^0-9]', '');
                if (dig.length() >= 2) return dig.length() > 2 ? dig.substring(0, 2) : dig;
            }
            if (String.isNotBlank(acc.BillingState)) {
                String s = acc.BillingState.replaceAll('[^0-9]', '');
                if (s.length() >= 2) return s.substring(0, 2);
            }
        }
        return '29';
    }

    // Added by Hari - Product__c HSN API name differs by org
    private static String resolveProductHsnFieldName() {
        if (!Schema.getGlobalDescribe().containsKey('Product__c')) return null;
        Map<String, Schema.SObjectField> fm = Schema.getGlobalDescribe().get('Product__c').getDescribe().fields.getMap();
        List<String> candidates = new List<String>{
            'HSN_Code__c', 'HSN__c', 'HSN_SAC__c', 'HSN_SAC_Code__c', 'SAC_HSN_Code__c', 'HSNCode__c',
            'HSNAC__c', 'Product_HSN__c', 'GST_HSN_Code__c'
        };
        for (String cand : candidates) {
            Schema.SObjectField f = fm.get(cand.toLowerCase());
            if (f != null) return f.getDescribe().getName();
        }
        return null;
    }

    // Added by Hari - Dynamic SELECT for Product HSN column
    private static Map<Id, SObject> loadProductsForLines(List<Invoice_Line_Item__c> lines, String hsnFieldApi) {
        Set<Id> pIds = new Set<Id>();
        for (Invoice_Line_Item__c li : lines) {
            if (li.Product__c != null) pIds.add(li.Product__c);
        }
        Map<Id, SObject> out = new Map<Id, SObject>();
        if (pIds.isEmpty() || !Schema.getGlobalDescribe().containsKey('Product__c')) return out;
        List<String> flds = new List<String>{ 'Id', 'Name' };
        if (String.isNotBlank(hsnFieldApi)) flds.add(hsnFieldApi);
        String soql = 'SELECT ' + String.join(flds, ', ') + ' FROM Product__c WHERE Id IN :pIds';
        for (SObject row : Database.query(soql)) {
            out.put(row.Id, row);
        }
        return out;
    }

    private static String formatDate(Date d) {
        if (d == null) return '';
        String dd = d.day() < 10 ? '0' + d.day() : String.valueOf(d.day());
        String mm = d.month() < 10 ? '0' + d.month() : String.valueOf(d.month());
        return dd + '/' + mm + '/' + d.year();
    }

    private static String formatDateForPdf(Date d) {
        if (d == null) return '';
        String dd = d.day() < 10 ? '0' + d.day() : String.valueOf(d.day());
        String mm = d.month() < 10 ? '0' + d.month() : String.valueOf(d.month());
        return dd + '-' + mm + '-' + d.year();
    }

    public class InvoiceToCygnetMapperException extends Exception {}
}