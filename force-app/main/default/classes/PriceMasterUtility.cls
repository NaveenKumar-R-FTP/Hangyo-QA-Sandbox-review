public without sharing class PriceMasterUtility {
    

    public static map<string,Pricing_Group__c> fetchCustomerGroups(set<String> custGrps){
        map<string,Pricing_Group__c> temp = new map<string,Pricing_Group__c>();
        for(Pricing_Group__c pg:[SELECT Id,Code__c,Name FROM Pricing_Group__c WHERE Code__c IN:custGrps AND Type__c=:'Customer']){
            temp.put(pg.Code__c,pg);
        }
        return temp;
    }

    public static map<string,Pricing_Group__c> fetchPriceGroups(set<String> priceGrps){
        map<string,Pricing_Group__c> temp = new map<string,Pricing_Group__c>();
        for(Pricing_Group__c pg:[SELECT Id,Code__c,Name FROM Pricing_Group__c WHERE Code__c IN:priceGrps AND Type__c=:'Product']){
            temp.put(pg.Code__c,pg);
        }
        return temp;
    }

    

    public static map<string,Product__c> fetchProducts(set<String> materialNums){
        map<string,Product__c> temp = new map<string,Product__c>();
        for(Product__c pd:[SELECT Id,Product_Code__c,MRP__c,Name FROM Product__c WHERE Product_Code__c IN: materialNums]){
            temp.put(pd.Product_Code__c,pd);
        }
        return temp;
    }

    public static map<string,List<Product__c>> fetchProductsforPrice(set<String> materialPricings){
        map<string,List<Product__c>> temp = new map<string,List<Product__c>>();
        for(Product__c pd:[SELECT Id,Product_Code__c,Pricing_Group__r.code__c,MRP__c,Name FROM Product__c WHERE Pricing_Group__r.code__c IN: materialPricings]){
            if(temp.get(pd.Pricing_Group__r.code__c)!=null){
                temp.get(pd.Pricing_Group__r.code__c).add(pd);
            } else{
                temp.put(pd.Pricing_Group__r.code__c,new List<Product__c>{pd});
            }
            
            
        }
        return temp;
    }

    

    public static map<string,Region__c> fetchRegions(set<String> regions){
        map<string,Region__c> temp = new map<string,Region__c>();
        for(Region__C rg:[SELECT Id,Region__c,Name FROM Region__c WHERE Region__c IN:regions]){
            temp.put(rg.Region__c,rg);
        }
        return temp;
    }

    public static map<string,Price_Book__c> fetchPriceBooks(set<String> regions){
        map<string,Price_Book__c> temp = new map<string,Price_Book__c>();
        for(Price_Book__c pb:[SELECT Id,Region__r.Region__c,Region__r.Name FROM Price_Book__c WHERE Region__r.Region__c IN:regions]){
            temp.put(pb.Region__r.Region__c,pb);
        }
        return temp;

    }
    
    public static Price_Book_Entry__c getExistingProd(Price_Book_Entry__c pb, List<Price_Book_Entry__c> oldList){        
        for(Price_Book_Entry__c prb:oldList){
            if(pb.Condition_Type__c == prb.Condition_Type__c && pb.Product__c == prb.Product__c && pb.Type__c == prb.Type__c && 
            pb.Validity_Start_Date__c == prb.Validity_Start_Date__c && pb.Validity_End_Date__c == prb.Validity_End_Date__c){
                
                if(pb.Customer_Group__c == prb.Customer_Group__c && pb.Region__C == prb.Region__C){
                    pb.id = prb.Id;
                }
            }
            
        }
        return pb;
    }

    public static void updateProductsMRP(List<PriceMasterAPI.PriceInfo> mrpPrice,PriceMasterAPI.PriceResponseData responseData){
        set<string> materialNums = new set<string>();
        for(PriceMasterAPI.PriceInfo price:mrpPrice){
            if(String.isNotBlank(price.material)){
                materialNums.add(price.material);
            }
        }
        if(!materialNums.isEmpty()){
            map<string,Product__c> productMap = new map<string,Product__c>();
            productMap = fetchProducts(materialNums);    
            List<Product__c> prodList = new List<Product__c>();
            for(PriceMasterAPI.PriceInfo price:mrpPrice){
                if(productMap.get(price.material) != null){
                    Product__c pd =productMap.get(price.material);
                    pd.MRP__c = Decimal.valueOf(price.conditionamount);
                    prodList.add(pd);
                } else {
                    PriceMasterAPI.ResponseData res = new PriceMasterAPI.ResponseData();
                        res.ref = price.material;
                        res.id =  '';
                        res.apiResponse = 'Product: '+price.material+' is unavailable.';
                        res.status = 'Failure';
                    responseData.data.add(res);
                }
            }
            if(!prodList.isEmpty()){
                Database.UpsertResult[] priceResults = Database.upsert(prodList, product__c.Id);
                for (Integer i = 0; i < priceResults.size(); i++) {
                    PriceMasterAPI.ResponseData res = new PriceMasterAPI.ResponseData();
                        res.ref = prodList[i].Name;
                        res.id = priceResults[i].isSuccess() ? priceResults[i].getId() : '';
                        res.apiResponse = priceResults[i].isSuccess() ? (priceResults[i].isCreated()?'Product MRP Created in Salesforce.':'Product MRP Updated in Salesforce.') : priceResults[i].getErrors()[0].getMessage();
                        res.status = priceResults[i].isSuccess() ? 'Success': 'Failure';
                    responseData.data.add(res);    
                }
            } 
        }
        

        
        
    }
}