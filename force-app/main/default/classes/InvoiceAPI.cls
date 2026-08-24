@RestResource(urlMapping='/InvoiceMaster/')
global without sharing class InvoiceAPI {
    
    @HttpPost
    global static InvoiceResponseData loadPriceDataFromSAP(List<InvoiceInfo> data) {
        InvoiceResponseData response = new InvoiceResponseData();
        response.data = new List<ResponseData>();
        Integration_Log__c log = new Integration_Log__c(Name='InvoiceAPI',Status__c='Success');
        log.Request__c  = (Json.serialize(data,false).length()>131072)?Json.serialize(data,false).Substring(0,131070):Json.serialize(data,false);
        try {
            if (data == null || data.isEmpty()) {
                return createEmptyResponse(response);
            }
        
            // Fetching required mappings
            Map<string, Id> invoiceMap = InvoiceUtility.fetchInvoice(getInvoiceNames(data));
            Map<string, Id> distributorMap = InvoiceUtility.fetchDistributors(getCustomerCodes(data));
            Map<string, Order__c> orderMap = InvoiceUtility.fetchOrders(getOrderRefs(data));
            Map<string, Id> prodMap = InvoiceUtility.fetchProducts(getProductCodes(data));

            FinalResponse fRes = new FinalResponse();
            
            fRes.invMap = prepareInvoiceRecords(data, invoiceMap, distributorMap, orderMap);
            fRes.invoiceList = new List<Invoice__c>(fRes.invMap.values());
            
            if (!fRes.invMap.isEmpty()) {
                fRes.invResults = Database.upsert(new List<Invoice__c>(fRes.invMap.values()), Invoice__c.Id);
                List<Invoice_Line_Item__c> invItemList = prepareInvoiceLineItems(data, fRes.invMap, prodMap);
        
                fRes.invItemMap = InvoiceUtility.processInvoiceLineItems(invItemList);
                fRes.invoiceLineItemMap = InvoiceUtility.buildInvoiceLineItemMap(invItemList);
                fRes.prdCodeMap = InvoiceUtility.fetchProductCodess(getProductCodes(data));
        
                response = InvoiceUtility.generateResponse(response, fRes);
            }
        } catch(Exception excp){            
            log.Error_Message__c    =   excp.getMessage() + ' at line ' + excp.getLineNumber();
            log.Status__c           =   'Fail';  
            ResponseData res = new ResponseData();                
                res.status = 'Failure';
                res.apiResponse = excp.getMessage();
            response.data.add(res);               
        }

        log.Response__c  = (Json.serialize(data,false).length()>131072)?Json.serialize(data,false).Substring(0,131070):Json.serialize(data,false);
        
        System.debug('*****log request*******'+log.Request__c.length());
        System.debug('*****log Response*******'+log.Response__c.length());
        Insert log;

        return response;
    }
    
    // Helper method to return empty response
    private static InvoiceResponseData createEmptyResponse(InvoiceResponseData response) {
        ResponseData resData = new ResponseData();
        resData.status = 'Failure';
        resData.apiResponse = 'Requested data is blank.';
        response.data.add(resData);
        return response;
    }
    
    // Extracted methods for readability
    private static Set<string> getCustomerCodes(List<InvoiceInfo> data) {
        Set<string> custCodes = new Set<string>();
        for (InvoiceInfo inv : data) {
            if (String.isNotBlank(inv.customer_code)) {
                custCodes.add(inv.customer_code);
            }
        }
        return custCodes;
    }
    
    private static Set<string> getOrderRefs(List<InvoiceInfo> data) {
        Set<string> orderRefs = new Set<string>();
        for (InvoiceInfo inv : data) {
            if (String.isNotBlank(inv.order_ref)) {
                orderRefs.add(inv.order_ref);
            }
        }
        return orderRefs;
    }
    
    /*private static Set<String> getProductCodes(List<InvoiceInfo> data){
        Set<String> codes = new Set<String>();
        for(InvoiceInfo inv : data){
            if(inv.items != null){
                for(InvoiceItem item : inv.items){
                    if(String.isNotBlank(item.prd_code))
                        codes.add(item.prd_code);
                }
            }
        }
        return codes;
    }*/
    
    private static Set<string> getProductCodes(List<InvoiceInfo> data) {
        Set<string> prodCodes = new Set<string>();
        for (InvoiceInfo inv : data) {
            for (InvoiceItem item : inv.items) {
                if (String.isNotBlank(item.prd_code)) {
                    prodCodes.add(item.prd_code);
                }
            }
        }
        return prodCodes;
    }
    
    private static Set<string> getInvoiceNames(List<InvoiceInfo> data) {
        Set<string> invNames = new Set<string>();
        for (InvoiceInfo inv : data) {
            if (String.isNotBlank(inv.invoice_no)) {
                invNames.add(inv.invoice_no);
            }
        }
        return invNames;
    }
    
    // Method to prepare Invoice__c records
    private static Map<string, Invoice__c> prepareInvoiceRecords(
        List<InvoiceInfo> data,
        Map<string, Id> invoiceMap,
        Map<string, Id> distributorMap,
        Map<string, Order__c> orderMap
    ) {
        Map<string, Invoice__c> invMap = new Map<string, Invoice__c>();
        String invRecTypeId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Primary_Invoice').getRecordTypeId();
    
        for (InvoiceInfo invEach : data) {
            Invoice__c inv = new Invoice__c();
            inv.Id = invoiceMap.get(invEach.invoice_no);
            inv.RecordTypeId = invRecTypeId;
            inv.Name = invEach.invoice_no;
            inv.Status__c = invEach.status != null ? invEach.status : null;
            inv.Type__c = invEach.type;
            inv.Supplier_Code__c = invEach.supplier_code;
            inv.Sub_Total__c = toDecimal(invEach.subtotal);
            inv.Taxable_Amount__c = toDecimal(invEach.tax_amt);
            inv.Origin__c = invEach.origin != null ? invEach.origin : null;
            //inv.Invoice_Total__c = toDecimal(invEach.total);
            inv.Invoice_Amount__c = toDecimal(invEach.total);
            //inv.Billing_Date__c = toDate(invEach.BillingDate);
            inv.Invoice_Date__c = toDate(invEach.BillingDate);
            inv.Distributor_Account__c = distributorMap.get(invEach.customer_code);
            if (orderMap.containsKey(invEach.order_ref)) {
                inv.Order__c = orderMap.get(invEach.order_ref).id;
                inv.OwnerId = orderMap.get(invEach.order_ref).OwnerId;
            }
            invMap.put(inv.Name, inv);           
            inv.Seller_Name__c  = System.Label.Seller_Name;
            inv.Seller_GSTIN__c = System.Label.Seller_GSTIN;
        }
        return invMap;
    }
    
    // Helper methods for type conversion
    private static Decimal toDecimal(String value) {
        return String.isNotBlank(value) ? Decimal.valueOf(value) : null;
    }
    
    private static Date toDate(String value) {
        return String.isNotBlank(value) ? Date.valueOf(value) : null;
    }
    
    // Prepare Invoice Line Items
    private static List<Invoice_Line_Item__c> prepareInvoiceLineItems(
        List<InvoiceInfo> data,
        Map<string, Invoice__c> invMap,
        Map<string, Id> prodMap
    ) {
        List<Invoice_Line_Item__c> invItemList = new List<Invoice_Line_Item__c>();
        for (InvoiceInfo invEach : data) {
            for (InvoiceItem item : invEach.items) {
                Invoice_Line_Item__c invItem = new Invoice_Line_Item__c();
                invItem.Product__c = prodMap.get(item.prd_code) != null ? prodMap.get(item.prd_code) : null;
                invItem.Invoice__c = invMap.get(invEach.invoice_no) != null ? invMap.get(invEach.invoice_no).Id : null;
                invItem.Quantity__c = toDecimal(item.qty);
                invItem.Unit_Of_Measure__c = item.uom;
                //invItem.Price__c = toDecimal(item.unit_price);
                //invItem.MRP__c = toDecimal(item.mrp);
                if(toDecimal(item.subtotal) > 0 && toDecimal(item.qty) > 0){
                    invItem.Price__c = toDecimal(item.subtotal) / toDecimal(item.qty);
                }
                invItem.Invoice_Line_Key__c = item.lineItem_number;
                invItem.MRP__c = toDecimal(item.unit_price);
                invItem.Total_MRP__c = toDecimal(item.mrp);
                invItem.Margin__c = toDecimal(item.margin);
                invItem.Discount__c = toDecimal(item.discount);
                invItem.Sub_Total__c = toDecimal(item.subtotal);
                invItem.Tax_Code__c = item.tax_code;
                invItem.Tax__c = toDecimal(item.tax);
                invItem.Total_Amount__c = toDecimal(item.total) != null ? toDecimal(item.total) : null;
                invItem = processTaxDetails(item.tax_lines, invItem);
                invItemList.add(invItem);
            }
        }
        return invItemList;
    }
    
    // Process tax details separately
    private static Invoice_Line_Item__c processTaxDetails(List<TaxLine> taxLines, Invoice_Line_Item__c invItem) {
        for (TaxLine tx : taxLines) {
            if (tx.Name == 'SGST') {
                invItem.SGST_Amount__c = Decimal.valueOf(tx.amt);
                invItem.SGST_Percentage__c = Decimal.valueOf(tx.pct);
            } else if (tx.Name == 'CGST') {
                invItem.CGST_Amount__c = Decimal.valueOf(tx.amt);
                invItem.CGST_Percentage__c = Decimal.valueOf(tx.pct);
            } else if (tx.Name == 'IGST') {
                invItem.IGST_Amount__c = Decimal.valueOf(tx.amt);
                invItem.IGST_Percentage__c = Decimal.valueOf(tx.pct);
            }
        }
        return invItem;
    }
    

    

    global class InvoiceResponseData {
        global List<ResponseData> data;
    }

    global class ResponseData {
        global string ref;
        global string status;
        global string id;
        global List<invItemResponse> items;        
        global string apiResponse;
    }

    global class invItemResponse{
        global string prdCode;
        global string status;
        global string id;
        global string apiResponse;
    }

    global class InvoiceInfo {
        global list<InvoiceItem> items;

        global string invoice_no;
        global string status;
        global string type;
        global string customer_code;
        global string supplier_code;
        global string order_ref;
        global string BillingDate;
        global string subtotal;
        global string tax_amt;
        global string origin;
        global string total;
    }

    global class InvoiceItem{
        global string lineItem_number;
        global string prd_code;
        global string qty;
        global string uom;
        global string unit_price;
        global string mrp;
        global string margin;
        global string discount;
        global string subtotal;
        global string tax_code;
        global string tax;
        global string total;
        global List<TaxLine> tax_lines;
    }

    global class TaxLine {
        global string Name;
        global string pct;
        global string amt;
    }

    global class finalResponse{
        global List<Invoice__c> invoiceList;
        global List<Database.UpsertResult> invResults;
        global Map<string, Invoice__c> invMap;
        global Map<string, List<Database.SaveResult>> invItemMap;
        //global Map<string, Invoice_Line_Item__c> invoiceLineItemMap;
        global Map<Id,Invoice_Line_Item__c> invoiceLineItemMap;
        global map<string,string> prdCodeMap;
    }
}