public without sharing class InvoiceUtility {

    public static Map<String,Id> fetchInvoice(Set<String> names){
        Map<String,Id> m = new Map<String,Id>();
        for(Invoice__c inv:[SELECT Id,Name FROM Invoice__c WHERE Name IN :names])
            m.put(inv.Name,inv.Id);
        return m;
    }

    public static Map<String,Id> fetchDistributors(Set<String> codes){
        Map<String,Id> m = new Map<String,Id>();
        for(Account a:[SELECT Id,Code__c FROM Account WHERE Code__c IN :codes])
            m.put(a.Code__c,a.Id);
        return m;
    }

    public static Map<String,Order__c> fetchOrders(Set<String> refs){
        Map<String,Order__c> m = new Map<String,Order__c>();
        for(Order__c o:[SELECT Id,Name,OwnerId FROM Order__c WHERE Name IN :refs])
            m.put(o.Name,o);
        return m;
    }

    public static Map<String,Id> fetchProducts(Set<String> codes){
        Map<String,Id> m = new Map<String,Id>();
        for(Product__c p:[SELECT Id,Product_Code__c FROM Product__c WHERE Product_Code__c IN :codes])
            m.put(p.Product_Code__c,p.Id);
        return m;
    }

    public static Map<String,String> fetchProductCodess(Set<String> codes){
        Map<String,String> m = new Map<String,String>();
        for(Product__c p:[SELECT Id,Product_Code__c FROM Product__c WHERE Product_Code__c IN :codes])
            m.put(p.Id,p.Product_Code__c);
        return m;
    }

    public static Map<String,List<Database.SaveResult>> processInvoiceLineItems(List<Invoice_Line_Item__c> items){
        Map<String,List<Database.SaveResult>> resultMap = new Map<String,List<Database.SaveResult>>();
        if(items.isEmpty()) return resultMap;
        Set<Id> invoiceIds = new Set<Id>();
        for(Invoice_Line_Item__c i:items){
            invoiceIds.add(i.Invoice__c);
        }

        Map<String,Invoice_Line_Item__c> existing = new Map<String,Invoice_Line_Item__c>();

        for(Invoice_Line_Item__c li:[SELECT Id,Invoice__c,Invoice_Line_Key__c FROM Invoice_Line_Item__c WHERE Invoice__c IN :invoiceIds]){
            String key = li.Invoice__c+'-'+li.Invoice_Line_Key__c;
            existing.put(key,li);
        }

        List<Invoice_Line_Item__c> toInsert = new List<Invoice_Line_Item__c>();

        for(Invoice_Line_Item__c li:items){
            String key = li.Invoice__c+'-'+li.Invoice_Line_Key__c;
            if(!existing.containsKey(key)){
                existing.put(key,li);
                toInsert.add(li);
            }
        }

        if(!toInsert.isEmpty()){
            List<Database.SaveResult> results = Database.insert(toInsert,false);
            for(Integer i=0;i<results.size();i++){
                String invId = toInsert[i].Invoice__c;
                if(!resultMap.containsKey(invId)){
                    resultMap.put(invId,new List<Database.SaveResult>());
                }                    
                resultMap.get(invId).add(results[i]);
            }
        }
        return resultMap;
    }

    public static Map<Id,Invoice_Line_Item__c> buildInvoiceLineItemMap(List<Invoice_Line_Item__c> items){
        Map<Id,Invoice_Line_Item__c> m = new Map<Id,Invoice_Line_Item__c>();
        for(Invoice_Line_Item__c i:items){
            if(i.Id!=null){
                m.put(i.Id,i);
            }
        }
        return m;
    }

    /*public static InvoiceAPI.InvoiceResponseData generateResponse(InvoiceAPI.InvoiceResponseData response,InvoiceAPI.FinalResponse fRes){
        for(Integer i=0;i<fRes.invoiceList.size();i++){
            Invoice__c inv = fRes.invoiceList[i];
            Database.UpsertResult res = fRes.invResults[i];
            InvoiceAPI.ResponseData rd = new InvoiceAPI.ResponseData();
            rd.ref = inv.Name;
            rd.id = res.isSuccess()?res.getId():'';
            rd.status = res.isSuccess()?'Success':'Failure';
            rd.apiResponse = res.isSuccess() ?
                (res.isCreated()?'Invoice Created in Salesforce.':'Invoice Updated in Salesforce.')
                : res.getErrors()[0].getMessage();

            rd.items = new List<InvoiceAPI.invItemResponse>();

            if(res.isSuccess() && fRes.invItemMap.containsKey(rd.id)){
                for(Database.SaveResult itRes : fRes.invItemMap.get(rd.id)){
                    InvoiceAPI.invItemResponse ir = new InvoiceAPI.invItemResponse();
                    ir.id = itRes.isSuccess()?itRes.getId():'';
                    ir.status = itRes.isSuccess()?'Success':'Failure';
                    ir.apiResponse = itRes.isSuccess()?'Invoice Item Created.': itRes.getErrors()[0].getMessage();

                    if(itRes.isSuccess() && fRes.invoiceLineItemMap.containsKey(itRes.getId())){
                        ir.prdCode = fRes.prdCodeMap.get(
                            fRes.invoiceLineItemMap.get(itRes.getId()).Product__c
                        );
                    }
                    rd.items.add(ir);
                }
            }
            response.data.add(rd);
        }
        return response;
    }*/
    
    public static InvoiceAPI.InvoiceResponseData generateResponse(InvoiceAPI.InvoiceResponseData response,InvoiceAPI.FinalResponse fRes){
        //Guard clauses
        if(response == null){
            response = new InvoiceAPI.InvoiceResponseData();
        }
        if(response.data == null){
            response.data = new List<InvoiceAPI.ResponseData>();
        }
        if(fRes == null || fRes.invoiceList == null){
            return response;
        }
    
        Integer invSize = fRes.invoiceList.size();
    
        for(Integer i = 0; i < invSize; i++){    
            Invoice__c inv = fRes.invoiceList[i];
    
            // Safe result fetch
            Database.UpsertResult res = (fRes.invResults != null && fRes.invResults.size() > i) ? fRes.invResults[i] : null;
    
            InvoiceAPI.ResponseData rd = new InvoiceAPI.ResponseData();
            rd.ref = (inv != null) ? inv.Name : null;
            rd.items = new List<InvoiceAPI.invItemResponse>();
    
            if(res != null && res.isSuccess()){
                rd.id = res.getId();
                rd.status = 'Success';
                rd.apiResponse = res.isCreated() ? 'Invoice Created in Salesforce.' : 'Invoice Updated in Salesforce.';
            } 
            else {
                rd.id = '';
                rd.status = 'Failure';   
                if(res != null && res.getErrors() != null && res.getErrors().size() > 0){
                    rd.apiResponse = res.getErrors()[0].getMessage();
                } else {
                    rd.apiResponse = 'Unknown error';
                }
            }
    
            // Process Invoice Items
            if(res != null && res.isSuccess() 
                && fRes.invItemMap != null 
                && fRes.invItemMap.containsKey(rd.id)){
    
                List<Database.SaveResult> itemResults = fRes.invItemMap.get(rd.id);
    
                if(itemResults != null){
                    for(Database.SaveResult itRes : itemResults){
    
                        InvoiceAPI.invItemResponse ir = new InvoiceAPI.invItemResponse();
    
                        if(itRes != null && itRes.isSuccess()){
                            ir.id = itRes.getId();
                            ir.status = 'Success';
                            ir.apiResponse = 'Invoice Item Created.';
                        } 
                        else {
                            ir.id = '';
                            ir.status = 'Failure';
    
                            if(itRes != null && itRes.getErrors() != null && itRes.getErrors().size() > 0){
                                ir.apiResponse = itRes.getErrors()[0].getMessage();
                            } else {
                                ir.apiResponse = 'Unknown error';
                            }
                        }
    
                        //Safe product code mapping
                        if(itRes != null && itRes.isSuccess() && fRes.invoiceLineItemMap != null && fRes.invoiceLineItemMap.containsKey(itRes.getId())){
                            Invoice_Line_Item__c lineItem = fRes.invoiceLineItemMap.get(itRes.getId());
                            if(lineItem != null && lineItem.Product__c != null && fRes.prdCodeMap != null){
                                ir.prdCode = fRes.prdCodeMap.get(lineItem.Product__c);
                            }
                        }
    
                        rd.items.add(ir);
                    }
                }
            }
            response.data.add(rd);
        }
        return response;
    }
}