global class UpdateInvoiceScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        UpdateInvoiceScheduler.updateInvoiceAndLines();
    }

    public static void updateInvoiceAndLines() {
        // Cutoff time -> yesterday 5 PM
        Datetime nowTime = System.now();
        Date yesterday = nowTime.date().addDays(-4);
        Datetime cutoff = Datetime.newInstance(yesterday, Time.newInstance(17,0,0,0));

        // Fetch Tax settings
        Order_Tax_Value__c taxSetting = [
            SELECT CGST__c, SGST__c, IGST__c
            FROM Order_Tax_Value__c
            WHERE Name = 'General GST Settings'
            LIMIT 1
        ];

        // Fetch invoices + account’s primary state
        List<Invoice__c> invoices = [
            SELECT Id, Name, Order__c, CreatedDate,
                   Order__r.Account__r.Primary_State__c,
                   (SELECT Id, Product__c, Price__c, MRP__c, Quantity__c, Total_Amount__c,
                           Discount_1__c, Discount_2__c, Total_Discount__c,
                           CGST_Amount__c, SGST_Amount__c, IGST_Amount__c
                    FROM Invoice_Line_Items__r)
            FROM Invoice__c
            WHERE Order__r.CreatedDate < :cutoff
              AND CreatedDate > :cutoff AND RecordType.Name = 'Secondary Invoice' AND Retailer_Account__c != NULL LIMIT 1
        ];
        System.debug('Invoice Details:- ' + invoices);

        // Collect all product + state combinations to query PBE in one SOQL
        Set<Id> productIds = new Set<Id>();
        Set<String> stateNames = new Set<String>();

        for (Invoice__c inv : invoices) {
            if (String.isNotBlank(inv.Order__r.Account__r.Primary_State__c)) {
                stateNames.add(inv.Order__r.Account__r.Primary_State__c);
            }
            for (Invoice_Line_Item__c line : inv.Invoice_Line_Items__r) {
                if (line.Product__c != null) {
                    productIds.add(line.Product__c);
                }
            }
        }
        System.debug('productIds:- ' + productIds);
        System.debug('stateNames:- ' + stateNames);

        // Query PricebookEntries for all required states + products
        Map<String, Map<Id, Price_Book_Entry__c>> stateProductPBEMap = new Map<String, Map<Id, Price_Book_Entry__c>>();
        if (!stateNames.isEmpty() && !productIds.isEmpty()) {
            for (Price_Book_Entry__c pbe : [
                SELECT Id, Product__c, Price_Book__r.Name, PTR__c
                FROM Price_Book_Entry__c
                WHERE Product__c IN :productIds
                  AND Price_Book__r.Name IN :stateNames
                  AND IsActive__c = true
            ]) {
                if (!stateProductPBEMap.containsKey(pbe.Price_Book__r.Name)) {
                    stateProductPBEMap.put(pbe.Price_Book__r.Name, new Map<Id, Price_Book_Entry__c>());
                }
                stateProductPBEMap.get(pbe.Price_Book__r.Name).put(pbe.Product__c, pbe);
            }
        }
        System.debug('stateProductPBEMap:- ' + stateProductPBEMap);

        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        List<Invoice_Line_Item__c> lineItemsToUpdate = new List<Invoice_Line_Item__c>();

        for (Invoice__c inv : invoices) {
            String state = inv.Order__r.Account__r.Primary_State__c;
            Decimal invoiceTaxable = 0;
            Decimal invoiceDiscount = 0;
            Decimal totalCGST = 0;
            Decimal totalSGST = 0;
            Decimal totalIGST = 0;

            for (Invoice_Line_Item__c line : inv.Invoice_Line_Items__r) {
                Decimal qty = (line.Quantity__c == null) ? 0 : line.Quantity__c.setScale(2, RoundingMode.HALF_UP);

                // Fetch PTR from PBE
                System.debug('State:- ' + state);
                //System.debug('PTR:- ' + stateProductPBEMap.get(state).get(line.Product__c).PTR__c);
                if (state != null && stateProductPBEMap.containsKey(state) && stateProductPBEMap.get(state).containsKey(line.Product__c) && stateProductPBEMap.get(state).get(line.Product__c).PTR__c != NULL) {
                    line.Price__c = stateProductPBEMap.get(state).get(line.Product__c).PTR__c.setScale(2, RoundingMode.HALF_UP);
                }

                Decimal baseTotal = (line.Price__c != null) ? (line.Price__c * qty) : 0;

                // Apply discounts
                Decimal discountAmt1 = (line.Discount_1__c != null && line.Discount_1__c > 0)
                                        ? baseTotal * (line.Discount_1__c / 100) : 0;
                Decimal afterDisc1 = baseTotal - discountAmt1;

                Decimal discountAmt2 = (line.Discount_2__c != null && line.Discount_2__c > 0)
                                        ? afterDisc1 * (line.Discount_2__c / 100) : 0;
                Decimal finalAmount = afterDisc1 - discountAmt2;

                //line.Total_Discount__c = (discountAmt1 + discountAmt2).setScale(2, RoundingMode.HALF_UP);
                line.Total_Amount__c = finalAmount.setScale(2, RoundingMode.HALF_UP);

                // Taxes
                line.CGST_Amount__c = (finalAmount * (taxSetting.CGST__c / 100)).setScale(2, RoundingMode.HALF_UP);
                line.SGST_Amount__c = (finalAmount * (taxSetting.SGST__c / 100)).setScale(2, RoundingMode.HALF_UP);
                line.IGST_Amount__c = (finalAmount * (taxSetting.IGST__c / 100)).setScale(2, RoundingMode.HALF_UP);

                // Rollups
                invoiceTaxable += finalAmount;
                invoiceDiscount += line.Total_Discount__c;
                totalCGST += line.CGST_Amount__c;
                totalSGST += line.SGST_Amount__c;
                totalIGST += line.IGST_Amount__c;

                lineItemsToUpdate.add(line);
            }

            // Invoice rollups
            inv.Taxable_Amount__c = invoiceTaxable.setScale(2, RoundingMode.HALF_UP);
            //inv.Discount__c = invoiceDiscount.setScale(2, RoundingMode.HALF_UP);
            inv.CGST_Amount__c = totalCGST.setScale(2, RoundingMode.HALF_UP);
            inv.SGST_Amount__c = totalSGST.setScale(2, RoundingMode.HALF_UP);
            inv.IGST_Amount__c = totalIGST.setScale(2, RoundingMode.HALF_UP);

            // Invoice total (rounded to whole number)
            Decimal totalAmt = invoiceTaxable + totalCGST + totalSGST + totalIGST;
            inv.Invoice_Amount__c = totalAmt.setScale(0, RoundingMode.HALF_UP);
            //inv.Total_Payable_Balance__c = inv.Invoice_Amount__c;

            // Amount in words
            inv.Invoice_Amount_In_Words__c = numberToWords(inv.Invoice_Amount__c);

            invoicesToUpdate.add(inv);
        }

        if (!lineItemsToUpdate.isEmpty()) update lineItemsToUpdate;
        if (!invoicesToUpdate.isEmpty()) update invoicesToUpdate;
    }

    private static String numberToWords(Decimal amount) {
        if (amount == null) return '';
    
        Long amt = amount.setScale(0, RoundingMode.HALF_UP).longValue();
        if (amt == 0) {
            return 'Zero Only';
        }
        return NumberToWords.convert(amt) + ' Only';
    }
}