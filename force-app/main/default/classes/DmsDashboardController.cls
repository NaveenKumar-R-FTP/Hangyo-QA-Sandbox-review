public without sharing class DmsDashboardController {

    @AuraEnabled(cacheable=false)
    public static DashboardPayload getDashboardData(Id distributorAccountId) {
        Date today     = Date.today();
        Date currStart = today.addDays(-30);
        Date currEnd   = today;
        Date prevStart = today.addDays(-60);
        Date prevEnd   = today.addDays(-31);

        DashboardPayload payload = new DashboardPayload();
        payload.currentWindowLabel = fmtDate(currStart) + ' – ' + fmtDate(currEnd);
        payload.prevWindowLabel    = fmtDate(prevStart) + ' – ' + fmtDate(prevEnd);
        payload.distributorInfo    = getDistributorInfo(distributorAccountId);

        Boolean isSS = payload.distributorInfo.isSuperStockist;

        // For SS: child distributor IDs; for distributor: just itself
        List<Id> distIds = new List<Id>();
        if (isSS) {
            for (Account a : [
                SELECT Id FROM Account
                WHERE Super_Stockist_Name__c = :distributorAccountId
                AND Is_Active__c = true
            ]) { distIds.add(a.Id); }
        } else {
            distIds.add(distributorAccountId);
        }

        payload.kpi           = buildKpi(distributorAccountId, distIds, isSS, currStart, currEnd, prevStart, prevEnd);
        payload.weeklyTrend   = buildWeeklyTrend(distributorAccountId, distIds, isSS, currStart, currEnd);
        payload.categoryData  = buildCategoryData(distributorAccountId, distIds, isSS, currStart, currEnd, prevStart, prevEnd);
        payload.topRetailers  = buildTopRetailers(distributorAccountId, distIds, isSS, currStart, currEnd, prevStart, prevEnd);
        payload.topProducts   = buildTopProducts(distributorAccountId, distIds, isSS, currStart, currEnd, prevStart, prevEnd);
        payload.announcements = getAnnouncements();
        return payload;
    }

    // ─── Distributor info ────────────────────────────────────────────────────

    private static DistributorInfo getDistributorInfo(Id accountId) {
        DistributorInfo info = new DistributorInfo();
        if (accountId == null) return info;
        List<Account> accs = [
            SELECT Id, Name, BillingCity, BillingState, RecordType.DeveloperName
            FROM Account WHERE Id = :accountId LIMIT 1
        ];
        if (!accs.isEmpty()) {
            Account a          = accs[0];
            info.accountId     = a.Id;
            info.name          = a.Name;
            info.location      = buildLocation(a.BillingCity, a.BillingState);
            info.isSuperStockist = (a.RecordType.DeveloperName == 'SuperStockist');
        }
        return info;
    }

    private static String buildLocation(String city, String state) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(city))  parts.add(city);
        if (String.isNotBlank(state)) parts.add(state);
        return String.join(parts, ', ');
    }

    // ─── KPI ─────────────────────────────────────────────────────────────────
    // SS:          Sales   = Secondary_Invoice_Under_SS + Secondary_Invoice (direct retail)
    //              Purchase= Primary_Invoice on SS account
    // Distributor: Sales   = Secondary_Invoice
    //              Purchase= Primary_Invoice OR Secondary_Invoice_Under_SS (if under SS)

    private static KpiBlock buildKpi(
        Id distId, List<Id> distIds, Boolean isSS,
        Date currStart, Date currEnd, Date prevStart, Date prevEnd
    ) {
        KpiBlock k = new KpiBlock();

        if (isSS) {
            // Sales = Under SS invoices + direct retail invoices
            k.salesCurrent    = sumInvoice(distId, 'Secondary_Invoice_Under_SS', currStart, currEnd)
                              + sumInvoice(distId, 'Secondary_Invoice', currStart, currEnd);
            k.salesPrev       = sumInvoice(distId, 'Secondary_Invoice_Under_SS', prevStart, prevEnd)
                              + sumInvoice(distId, 'Secondary_Invoice', prevStart, prevEnd);
            // Purchase = Primary invoices on SS
            k.purchaseCurrent = sumInvoice(distId, 'Primary_Invoice', currStart, currEnd);
            k.purchasePrev    = sumInvoice(distId, 'Primary_Invoice', prevStart, prevEnd);
            // Returns = all returns on SS invoices (both types)
            k.returnsCurrent  = sumReturnsForAccount(distId, currStart, currEnd);
            k.returnsPrev     = sumReturnsForAccount(distId, prevStart, prevEnd);
            // Active count = under SS distributors only
            k.activeRetailersCurrent = countActiveUnderSS(distId);
            k.activeRetailersPrev    = k.activeRetailersCurrent;
        } else {
            Account acc = [SELECT Super_Stockist_Name__c FROM Account WHERE Id = :distId LIMIT 1];
            Boolean isUnderSS = acc.Super_Stockist_Name__c != null;

            k.salesCurrent    = sumInvoiceList(distIds, 'Secondary_Invoice', currStart, currEnd);
            k.salesPrev       = sumInvoiceList(distIds, 'Secondary_Invoice', prevStart, prevEnd);
            // Purchase: if under SS → Secondary_Invoice_Under_SS where Under_SS__c = distId; else Primary_Invoice
            if (isUnderSS) {
                k.purchaseCurrent = sumUnderSSPurchase(distId, currStart, currEnd);
                k.purchasePrev    = sumUnderSSPurchase(distId, prevStart, prevEnd);
            } else {
                k.purchaseCurrent = sumInvoiceList(distIds, 'Primary_Invoice', currStart, currEnd);
                k.purchasePrev    = sumInvoiceList(distIds, 'Primary_Invoice', prevStart, prevEnd);
            }
            k.returnsCurrent         = sumReturnsForAccount(distId, currStart, currEnd);
            k.returnsPrev            = sumReturnsForAccount(distId, prevStart, prevEnd);
            k.activeRetailersCurrent = [SELECT COUNT() FROM Account WHERE Distributor__c = :distId AND Is_Active__c = true];
            k.activeRetailersPrev    = k.activeRetailersCurrent;
        }
        return k;
    }

    // ─── Weekly trend ────────────────────────────────────────────────────────
    // SS:  Secondary = Under_SS + Direct Retail; Primary = Primary_Invoice on SS
    // Dist: Secondary = Secondary_Invoice; Primary = Primary_Invoice or Under_SS purchase

    private static List<WeeklyBucket> buildWeeklyTrend(
        Id distId, List<Id> distIds, Boolean isSS,
        Date startDt, Date endDt
    ) {
        Map<String, WeeklyBucket> bucketMap = new Map<String, WeeklyBucket>();

        if (isSS) {
            // Secondary: Under SS
            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(Invoice_Date__c) yr, WEEK_IN_YEAR(Invoice_Date__c) wk, SUM(Invoice_Amount__c) total
                FROM Invoice__c WHERE Distributor_Account__c = :distId
                AND RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                AND Invoice_Date__c >= :startDt AND Invoice_Date__c <= :endDt
                GROUP BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
                ORDER BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
            ]) {
                String key = ar.get('yr') + '-W' + String.valueOf(ar.get('wk')).leftPad(2,'0');
                getOrCreateBucket(bucketMap, key, (Integer)ar.get('yr'), (Integer)ar.get('wk')).secondarySales
                    += nvlDecimal((Decimal)ar.get('total'));
            }
            // Secondary: Direct retail (SS sells direct to retailer)
            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(Invoice_Date__c) yr, WEEK_IN_YEAR(Invoice_Date__c) wk, SUM(Invoice_Amount__c) total
                FROM Invoice__c WHERE Distributor_Account__c = :distId
                AND RecordType.DeveloperName = 'Secondary_Invoice'
                AND Invoice_Date__c >= :startDt AND Invoice_Date__c <= :endDt
                GROUP BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
                ORDER BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
            ]) {
                String key = ar.get('yr') + '-W' + String.valueOf(ar.get('wk')).leftPad(2,'0');
                getOrCreateBucket(bucketMap, key, (Integer)ar.get('yr'), (Integer)ar.get('wk')).secondarySales
                    += nvlDecimal((Decimal)ar.get('total'));
            }
            // Primary purchase on SS
            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(Invoice_Date__c) yr, WEEK_IN_YEAR(Invoice_Date__c) wk, SUM(Invoice_Amount__c) total
                FROM Invoice__c WHERE Distributor_Account__c = :distId
                AND RecordType.DeveloperName = 'Primary_Invoice'
                AND Invoice_Date__c >= :startDt AND Invoice_Date__c <= :endDt
                GROUP BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
                ORDER BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
            ]) {
                String key = ar.get('yr') + '-W' + String.valueOf(ar.get('wk')).leftPad(2,'0');
                getOrCreateBucket(bucketMap, key, (Integer)ar.get('yr'), (Integer)ar.get('wk')).primaryPurchase
                    += nvlDecimal((Decimal)ar.get('total'));
            }
        } else {
            if (distIds.isEmpty()) return new List<WeeklyBucket>();
            // Secondary sales
            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(Invoice_Date__c) yr, WEEK_IN_YEAR(Invoice_Date__c) wk, SUM(Invoice_Amount__c) total
                FROM Invoice__c WHERE Distributor_Account__c IN :distIds
                AND RecordType.DeveloperName = 'Secondary_Invoice'
                AND Invoice_Date__c >= :startDt AND Invoice_Date__c <= :endDt
                GROUP BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
                ORDER BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
            ]) {
                String key = ar.get('yr') + '-W' + String.valueOf(ar.get('wk')).leftPad(2,'0');
                getOrCreateBucket(bucketMap, key, (Integer)ar.get('yr'), (Integer)ar.get('wk')).secondarySales
                    += nvlDecimal((Decimal)ar.get('total'));
            }
            // Primary purchase
            Account acc = [SELECT Super_Stockist_Name__c FROM Account WHERE Id = :distId LIMIT 1];
            if (acc.Super_Stockist_Name__c != null) {
                // Under SS: primary purchase = Secondary_Invoice_Under_SS where Under_SS__c = distId
                for (AggregateResult ar : [
                    SELECT CALENDAR_YEAR(Invoice_Date__c) yr, WEEK_IN_YEAR(Invoice_Date__c) wk, SUM(Invoice_Amount__c) total
                    FROM Invoice__c WHERE Under_SS__c = :distId
                    AND RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                    AND Invoice_Date__c >= :startDt AND Invoice_Date__c <= :endDt
                    GROUP BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
                    ORDER BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
                ]) {
                    String key = ar.get('yr') + '-W' + String.valueOf(ar.get('wk')).leftPad(2,'0');
                    getOrCreateBucket(bucketMap, key, (Integer)ar.get('yr'), (Integer)ar.get('wk')).primaryPurchase
                        += nvlDecimal((Decimal)ar.get('total'));
                }
            } else {
                // Regular distributor: Primary_Invoice
                for (AggregateResult ar : [
                    SELECT CALENDAR_YEAR(Invoice_Date__c) yr, WEEK_IN_YEAR(Invoice_Date__c) wk, SUM(Invoice_Amount__c) total
                    FROM Invoice__c WHERE Distributor_Account__c IN :distIds
                    AND RecordType.DeveloperName = 'Primary_Invoice'
                    AND Invoice_Date__c >= :startDt AND Invoice_Date__c <= :endDt
                    GROUP BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
                    ORDER BY CALENDAR_YEAR(Invoice_Date__c), WEEK_IN_YEAR(Invoice_Date__c)
                ]) {
                    String key = ar.get('yr') + '-W' + String.valueOf(ar.get('wk')).leftPad(2,'0');
                    getOrCreateBucket(bucketMap, key, (Integer)ar.get('yr'), (Integer)ar.get('wk')).primaryPurchase
                        += nvlDecimal((Decimal)ar.get('total'));
                }
            }
        }

        List<String> keys = new List<String>(bucketMap.keySet());
        keys.sort();
        List<WeeklyBucket> result = new List<WeeklyBucket>();
        for (String k : keys) result.add(bucketMap.get(k));
        return result;
    }

    private static WeeklyBucket getOrCreateBucket(
        Map<String, WeeklyBucket> m, String key, Integer yr, Integer wk
    ) {
        if (!m.containsKey(key)) {
            WeeklyBucket b = new WeeklyBucket();
            Date jan1      = Date.newInstance(yr, 1, 1);
            Integer jan1Day = Math.mod(Date.newInstance(yr, 1, 1).toStartOfWeek().daysBetween(jan1), 7);
            Date weekStart  = jan1.addDays((wk - 1) * 7 - jan1Day);
            b.weekLabel  = 'W' + String.valueOf(wk).leftPad(2,'0') + ' (' + weekStart.format() + ')';
            b.year       = yr;
            b.weekNumber = wk;
            b.secondarySales  = 0;
            b.primaryPurchase = 0;
            m.put(key, b);
        }
        return m.get(key);
    }

    // ─── Category data ───────────────────────────────────────────────────────
    // SS: combine Under_SS + direct retail line items

    private static List<CategoryRow> buildCategoryData(
        Id distId, List<Id> distIds, Boolean isSS,
        Date currStart, Date currEnd, Date prevStart, Date prevEnd
    ) {
        Map<String, CategoryRow> catMap = new Map<String, CategoryRow>();

        if (isSS) {
            // Current: Under SS line items
            for (AggregateResult ar : [
                SELECT Product__r.Product_Brand__c cat, SUM(Total_Amount__c) total
                FROM Invoice_Line_Item__c
                WHERE Invoice__r.Distributor_Account__c = :distId
                AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                AND Invoice__r.Invoice_Date__c >= :currStart AND Invoice__r.Invoice_Date__c <= :currEnd
                GROUP BY Product__r.Product_Brand__c
            ]) {
                String cat = nvlStr((String)ar.get('cat'));
                getOrCreateCategory(catMap, cat).currentAmount += nvlDecimal((Decimal)ar.get('total'));
            }
            // Current: Direct retail line items
            for (AggregateResult ar : [
                SELECT Product__r.Product_Brand__c cat, SUM(Total_Amount__c) total
                FROM Invoice_Line_Item__c
                WHERE Invoice__r.Distributor_Account__c = :distId
                AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice'
                AND Invoice__r.Invoice_Date__c >= :currStart AND Invoice__r.Invoice_Date__c <= :currEnd
                GROUP BY Product__r.Product_Brand__c
            ]) {
                String cat = nvlStr((String)ar.get('cat'));
                getOrCreateCategory(catMap, cat).currentAmount += nvlDecimal((Decimal)ar.get('total'));
            }
            // Previous: Under SS
            for (AggregateResult ar : [
                SELECT Product__r.Product_Brand__c cat, SUM(Total_Amount__c) total
                FROM Invoice_Line_Item__c
                WHERE Invoice__r.Distributor_Account__c = :distId
                AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                AND Invoice__r.Invoice_Date__c >= :prevStart AND Invoice__r.Invoice_Date__c <= :prevEnd
                GROUP BY Product__r.Product_Brand__c
            ]) {
                String cat = nvlStr((String)ar.get('cat'));
                getOrCreateCategory(catMap, cat).prevAmount += nvlDecimal((Decimal)ar.get('total'));
            }
            // Previous: Direct retail
            for (AggregateResult ar : [
                SELECT Product__r.Product_Brand__c cat, SUM(Total_Amount__c) total
                FROM Invoice_Line_Item__c
                WHERE Invoice__r.Distributor_Account__c = :distId
                AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice'
                AND Invoice__r.Invoice_Date__c >= :prevStart AND Invoice__r.Invoice_Date__c <= :prevEnd
                GROUP BY Product__r.Product_Brand__c
            ]) {
                String cat = nvlStr((String)ar.get('cat'));
                getOrCreateCategory(catMap, cat).prevAmount += nvlDecimal((Decimal)ar.get('total'));
            }
        } else {
            if (distIds.isEmpty()) return new List<CategoryRow>();
            for (AggregateResult ar : [
                SELECT Product__r.Product_Brand__c cat, SUM(Total_Amount__c) total
                FROM Invoice_Line_Item__c
                WHERE Invoice__r.Distributor_Account__c IN :distIds
                AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice'
                AND Invoice__r.Invoice_Date__c >= :currStart AND Invoice__r.Invoice_Date__c <= :currEnd
                GROUP BY Product__r.Product_Brand__c
            ]) {
                String cat = nvlStr((String)ar.get('cat'));
                getOrCreateCategory(catMap, cat).currentAmount += nvlDecimal((Decimal)ar.get('total'));
            }
            for (AggregateResult ar : [
                SELECT Product__r.Product_Brand__c cat, SUM(Total_Amount__c) total
                FROM Invoice_Line_Item__c
                WHERE Invoice__r.Distributor_Account__c IN :distIds
                AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice'
                AND Invoice__r.Invoice_Date__c >= :prevStart AND Invoice__r.Invoice_Date__c <= :prevEnd
                GROUP BY Product__r.Product_Brand__c
            ]) {
                String cat = nvlStr((String)ar.get('cat'));
                getOrCreateCategory(catMap, cat).prevAmount += nvlDecimal((Decimal)ar.get('total'));
            }
        }
        return catMap.values();
    }

    private static CategoryRow getOrCreateCategory(Map<String, CategoryRow> m, String cat) {
        if (!m.containsKey(cat)) {
            CategoryRow r = new CategoryRow();
            r.category     = cat;
            r.currentAmount = 0;
            r.prevAmount    = 0;
            m.put(cat, r);
        }
        return m.get(cat);
    }

    // ─── Top retailers ───────────────────────────────────────────────────────
    // SS: top 5 from BOTH Under_SS distributors AND direct retailers combined

    private static List<TopRetailerRow> buildTopRetailers(
        Id distId, List<Id> distIds, Boolean isSS,
        Date currStart, Date currEnd, Date prevStart, Date prevEnd
    ) {
        Map<String, TopRetailerRow> rowMap = new Map<String, TopRetailerRow>();

        if (isSS) {
            // SS: Top 5 Under-SS distributors only
            List<Id> topIds = new List<Id>();
            for (AggregateResult ar : [
                SELECT Under_SS__c rid, MAX(Under_SS__r.Name) rname, SUM(Invoice_Amount__c) total
                FROM Invoice__c
                WHERE Distributor_Account__c = :distId
                AND RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                AND Invoice_Date__c >= :currStart AND Invoice_Date__c <= :currEnd
                AND Under_SS__c != null
                GROUP BY Under_SS__c ORDER BY SUM(Invoice_Amount__c) DESC LIMIT 5
            ]) {
                String key = String.valueOf(ar.get('rid'));
                TopRetailerRow r = new TopRetailerRow();
                r.retailerId    = (Id)ar.get('rid');
                r.retailerName  = nvlStr((String)ar.get('rname'));
                r.currentAmount = nvlDecimal((Decimal)ar.get('total'));
                r.prevAmount    = 0;
                rowMap.put(key, r);
                topIds.add((Id)ar.get('rid'));
            }
            // Get prev period for top 5
            if (!topIds.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Under_SS__c rid, SUM(Invoice_Amount__c) total
                    FROM Invoice__c WHERE Distributor_Account__c = :distId
                    AND RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                    AND Invoice_Date__c >= :prevStart AND Invoice_Date__c <= :prevEnd
                    AND Under_SS__c IN :topIds GROUP BY Under_SS__c
                ]) {
                    String key = String.valueOf(ar.get('rid'));
                    if (rowMap.containsKey(key)) rowMap.get(key).prevAmount = nvlDecimal((Decimal)ar.get('total'));
                }
            }
            List<TopRetailerRow> result = new List<TopRetailerRow>();
            for (Id rid : topIds) result.add(rowMap.get(String.valueOf(rid)));
            return result;

        } else {
            if (distIds.isEmpty()) return new List<TopRetailerRow>();
            List<Id> topIds = new List<Id>();
            for (AggregateResult ar : [
                SELECT Retailer_Account__c rid, MAX(Retailer_Account__r.Name) rname, SUM(Invoice_Amount__c) total
                FROM Invoice__c WHERE Distributor_Account__c IN :distIds
                AND RecordType.DeveloperName = 'Secondary_Invoice'
                AND Invoice_Date__c >= :currStart AND Invoice_Date__c <= :currEnd
                AND Retailer_Account__c != null
                GROUP BY Retailer_Account__c ORDER BY SUM(Invoice_Amount__c) DESC LIMIT 5
            ]) {
                Id rid = (Id)ar.get('rid');
                TopRetailerRow r = new TopRetailerRow();
                r.retailerId    = rid;
                r.retailerName  = nvlStr((String)ar.get('rname'));
                r.currentAmount = nvlDecimal((Decimal)ar.get('total'));
                r.prevAmount    = 0;
                rowMap.put(String.valueOf(rid), r);
                topIds.add(rid);
            }
            if (!topIds.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Retailer_Account__c rid, SUM(Invoice_Amount__c) total
                    FROM Invoice__c WHERE Distributor_Account__c IN :distIds
                    AND RecordType.DeveloperName = 'Secondary_Invoice'
                    AND Invoice_Date__c >= :prevStart AND Invoice_Date__c <= :prevEnd
                    AND Retailer_Account__c IN :topIds GROUP BY Retailer_Account__c
                ]) {
                    String key = String.valueOf(ar.get('rid'));
                    if (rowMap.containsKey(key)) rowMap.get(key).prevAmount = nvlDecimal((Decimal)ar.get('total'));
                }
            }
            List<TopRetailerRow> result = new List<TopRetailerRow>();
            for (Id rid : topIds) result.add(rowMap.get(String.valueOf(rid)));
            return result;
        }
    }

    // ─── Top products ────────────────────────────────────────────────────────
    // SS: combine Under_SS + direct retail line items

    private static List<TopProductRow> buildTopProducts(
        Id distId, List<Id> distIds, Boolean isSS,
        Date currStart, Date currEnd, Date prevStart, Date prevEnd
    ) {
        Map<String, TopProductRow> productMap = new Map<String, TopProductRow>();
        List<String> topNames = new List<String>();

        if (isSS) {
            // Current: Under SS line items
            for (AggregateResult ar : [
                SELECT Product__r.Name pname, SUM(Total_Amount__c) total
                FROM Invoice_Line_Item__c
                WHERE Invoice__r.Distributor_Account__c = :distId
                AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                AND Invoice__r.Invoice_Date__c >= :currStart AND Invoice__r.Invoice_Date__c <= :currEnd
                AND Product__r.Name != null GROUP BY Product__r.Name
            ]) {
                String pname = nvlStr((String)ar.get('pname'));
                getOrCreateProduct(productMap, pname).currentAmount += nvlDecimal((Decimal)ar.get('total'));
            }
            // Current: Direct retail line items
            for (AggregateResult ar : [
                SELECT Product__r.Name pname, SUM(Total_Amount__c) total
                FROM Invoice_Line_Item__c
                WHERE Invoice__r.Distributor_Account__c = :distId
                AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice'
                AND Invoice__r.Invoice_Date__c >= :currStart AND Invoice__r.Invoice_Date__c <= :currEnd
                AND Product__r.Name != null GROUP BY Product__r.Name
            ]) {
                String pname = nvlStr((String)ar.get('pname'));
                getOrCreateProduct(productMap, pname).currentAmount += nvlDecimal((Decimal)ar.get('total'));
            }
            // Sort and take top 5
            List<TopProductRow> allProds = productMap.values();
            allProds.sort();
            List<TopProductRow> top5 = new List<TopProductRow>();
            for (Integer i = 0; i < Math.min(5, allProds.size()); i++) {
                top5.add(allProds[i]);
                topNames.add(allProds[i].productName);
            }
            // Previous: Under SS
            if (!topNames.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Product__r.Name pname, SUM(Total_Amount__c) total
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__r.Distributor_Account__c = :distId
                    AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                    AND Invoice__r.Invoice_Date__c >= :prevStart AND Invoice__r.Invoice_Date__c <= :prevEnd
                    AND Product__r.Name IN :topNames GROUP BY Product__r.Name
                ]) {
                    String pname = nvlStr((String)ar.get('pname'));
                    if (productMap.containsKey(pname)) productMap.get(pname).prevAmount += nvlDecimal((Decimal)ar.get('total'));
                }
                // Previous: Direct retail
                for (AggregateResult ar : [
                    SELECT Product__r.Name pname, SUM(Total_Amount__c) total
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__r.Distributor_Account__c = :distId
                    AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice'
                    AND Invoice__r.Invoice_Date__c >= :prevStart AND Invoice__r.Invoice_Date__c <= :prevEnd
                    AND Product__r.Name IN :topNames GROUP BY Product__r.Name
                ]) {
                    String pname = nvlStr((String)ar.get('pname'));
                    if (productMap.containsKey(pname)) productMap.get(pname).prevAmount += nvlDecimal((Decimal)ar.get('total'));
                }
            }
            return top5;

        } else {
            if (distIds.isEmpty()) return new List<TopProductRow>();
            for (AggregateResult ar : [
                SELECT Product__r.Name pname, SUM(Total_Amount__c) total
                FROM Invoice_Line_Item__c
                WHERE Invoice__r.Distributor_Account__c IN :distIds
                AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice'
                AND Invoice__r.Invoice_Date__c >= :currStart AND Invoice__r.Invoice_Date__c <= :currEnd
                AND Product__r.Name != null GROUP BY Product__r.Name ORDER BY SUM(Total_Amount__c) DESC LIMIT 5
            ]) {
                String pname = nvlStr((String)ar.get('pname'));
                TopProductRow r = new TopProductRow();
                r.productName   = pname;
                r.currentAmount = nvlDecimal((Decimal)ar.get('total'));
                r.prevAmount    = 0;
                productMap.put(pname, r);
                topNames.add(pname);
            }
            if (!topNames.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Product__r.Name pname, SUM(Total_Amount__c) total
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__r.Distributor_Account__c IN :distIds
                    AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice'
                    AND Invoice__r.Invoice_Date__c >= :prevStart AND Invoice__r.Invoice_Date__c <= :prevEnd
                    AND Product__r.Name IN :topNames GROUP BY Product__r.Name
                ]) {
                    String pname = nvlStr((String)ar.get('pname'));
                    if (productMap.containsKey(pname)) productMap.get(pname).prevAmount = nvlDecimal((Decimal)ar.get('total'));
                }
            }
            List<TopProductRow> result = new List<TopProductRow>();
            for (String n : topNames) result.add(productMap.get(n));
            return result;
        }
    }

    private static TopProductRow getOrCreateProduct(Map<String, TopProductRow> m, String pname) {
        if (!m.containsKey(pname)) {
            TopProductRow r = new TopProductRow();
            r.productName   = pname;
            r.currentAmount = 0;
            r.prevAmount    = 0;
            m.put(pname, r);
        }
        return m.get(pname);
    }

    // ─── Announcements ───────────────────────────────────────────────────────

    private static List<AnnouncementItem> getAnnouncements() {
        List<AnnouncementItem> items = new List<AnnouncementItem>();
        for (DMS_Announcement__mdt rec : [
            SELECT MasterLabel, Message__c, Sequence__c
            FROM DMS_Announcement__mdt
            WHERE Is_Active__c = true
            ORDER BY Sequence__c ASC
        ]) {
            AnnouncementItem a = new AnnouncementItem();
            a.label   = rec.MasterLabel;
            a.message = rec.Message__c;
            items.add(a);
        }
        return items;
    }

    // ─── Utility helpers ─────────────────────────────────────────────────────

    private static Decimal sumInvoice(Id distId, String rtDevName, Date startDt, Date endDt) {
        AggregateResult[] rows = [
            SELECT SUM(Invoice_Amount__c) total FROM Invoice__c
            WHERE Distributor_Account__c = :distId AND RecordType.DeveloperName = :rtDevName
            AND Invoice_Date__c >= :startDt AND Invoice_Date__c <= :endDt
        ];
        return rows.isEmpty() ? 0 : nvlDecimal((Decimal)rows[0].get('total'));
    }

    private static Decimal sumInvoiceList(List<Id> distIds, String rtDevName, Date startDt, Date endDt) {
        if (distIds.isEmpty()) return 0;
        AggregateResult[] rows = [
            SELECT SUM(Invoice_Amount__c) total FROM Invoice__c
            WHERE Distributor_Account__c IN :distIds AND RecordType.DeveloperName = :rtDevName
            AND Invoice_Date__c >= :startDt AND Invoice_Date__c <= :endDt
        ];
        return rows.isEmpty() ? 0 : nvlDecimal((Decimal)rows[0].get('total'));
    }

    private static Decimal sumUnderSSPurchase(Id distId, Date startDt, Date endDt) {
        AggregateResult[] rows = [
            SELECT SUM(Invoice_Amount__c) total FROM Invoice__c
            WHERE Under_SS__c = :distId AND RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
            AND Invoice_Date__c >= :startDt AND Invoice_Date__c <= :endDt
        ];
        return rows.isEmpty() ? 0 : nvlDecimal((Decimal)rows[0].get('total'));
    }

    private static Decimal sumReturnsForAccount(Id distId, Date startDt, Date endDt) {
        AggregateResult[] rows = [
            SELECT SUM(Total_return_Incl_tax__c) total FROM Returns__c
            WHERE Invoice__r.Distributor_Account__c = :distId
            AND CreatedDate >= :DateTime.newInstance(startDt, Time.newInstance(0,0,0,0))
            AND CreatedDate <= :DateTime.newInstance(endDt, Time.newInstance(23,59,59,0))
        ];
        return rows.isEmpty() ? 0 : nvlDecimal((Decimal)rows[0].get('total'));
    }

    private static Integer countActiveUnderSS(Id ssId) {
        return [SELECT COUNT() FROM Account WHERE Super_Stockist_Name__c = :ssId AND Is_Active__c = true];
    }

    private static Integer countDirectRetailers(Id ssId) {
        // Count distinct retailers who have Secondary_Invoice from this SS
        Set<Id> retailerIds = new Set<Id>();
        for (Invoice__c inv : [
            SELECT Retailer_Account__c FROM Invoice__c
            WHERE Distributor_Account__c = :ssId
            AND RecordType.DeveloperName = 'Secondary_Invoice'
            AND Retailer_Account__c != null
        ]) { retailerIds.add(inv.Retailer_Account__c); }
        return retailerIds.size();
    }

    private static Decimal nvlDecimal(Decimal d) { return d == null ? 0 : d; }
    private static String  nvlStr(String s)      { return (s == null || s.trim() == '') ? 'Uncategorised' : s; }
    private static String  fmtDate(Date d) {
        return String.valueOf(d.day()).leftPad(2,'0') + ' '
             + DateTime.newInstance(d, Time.newInstance(0,0,0,0)).format('MMM') + ' '
             + String.valueOf(d.year());
    }

    // ─── Inner wrapper classes ────────────────────────────────────────────────

    public class DashboardPayload {
        @AuraEnabled public String                 currentWindowLabel;
        @AuraEnabled public String                 prevWindowLabel;
        @AuraEnabled public DistributorInfo        distributorInfo;
        @AuraEnabled public KpiBlock               kpi;
        @AuraEnabled public List<WeeklyBucket>     weeklyTrend;
        @AuraEnabled public List<CategoryRow>      categoryData;
        @AuraEnabled public List<TopRetailerRow>   topRetailers;
        @AuraEnabled public List<TopProductRow>    topProducts;
        @AuraEnabled public List<AnnouncementItem> announcements;
    }

    public class DistributorInfo {
        @AuraEnabled public Id      accountId;
        @AuraEnabled public String  name;
        @AuraEnabled public String  location;
        @AuraEnabled public Boolean isSuperStockist = false;
    }

    public class KpiBlock {
        @AuraEnabled public Decimal salesCurrent;
        @AuraEnabled public Decimal salesPrev;
        @AuraEnabled public Decimal purchaseCurrent;
        @AuraEnabled public Decimal purchasePrev;
        @AuraEnabled public Decimal returnsCurrent;
        @AuraEnabled public Decimal returnsPrev;
        @AuraEnabled public Integer activeRetailersCurrent;
        @AuraEnabled public Integer activeRetailersPrev;
    }

    public class WeeklyBucket {
        @AuraEnabled public String  weekLabel;
        @AuraEnabled public Integer year;
        @AuraEnabled public Integer weekNumber;
        @AuraEnabled public Decimal secondarySales   = 0;
        @AuraEnabled public Decimal primaryPurchase  = 0;
    }

    public class CategoryRow {
        @AuraEnabled public String  category;
        @AuraEnabled public Decimal currentAmount = 0;
        @AuraEnabled public Decimal prevAmount    = 0;
    }

    public class TopRetailerRow implements Comparable {
        @AuraEnabled public Id      retailerId;
        @AuraEnabled public String  retailerName;
        @AuraEnabled public Decimal currentAmount = 0;
        @AuraEnabled public Decimal prevAmount    = 0;
        public Integer compareTo(Object other) {
            TopRetailerRow o = (TopRetailerRow)other;
            if (this.currentAmount > o.currentAmount) return -1;
            if (this.currentAmount < o.currentAmount) return 1;
            return 0;
        }
    }

    public class TopProductRow implements Comparable {
        @AuraEnabled public String  productName;
        @AuraEnabled public Decimal currentAmount = 0;
        @AuraEnabled public Decimal prevAmount    = 0;
        public Integer compareTo(Object other) {
            TopProductRow o = (TopProductRow)other;
            if (this.currentAmount > o.currentAmount) return -1;
            if (this.currentAmount < o.currentAmount) return 1;
            return 0;
        }
    }

    public class AnnouncementItem {
        @AuraEnabled public String label;
        @AuraEnabled public String message;
    }
}