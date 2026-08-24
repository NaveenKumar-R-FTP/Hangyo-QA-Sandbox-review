public without sharing class CustomerStatementController {

    @AuraEnabled(cacheable=false)
    public static Map<String,Object> getContextAndCustomers() {
        User currentUser = [
            SELECT AccountId, Account.Name, Account.RecordType.DeveloperName
            FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        Map<String,Object> ctx = new Map<String,Object>();
        if (currentUser.AccountId == null) {
            ctx.put('error', 'No account linked to this portal user.');
            return ctx;
        }
        String recType = currentUser.Account.RecordType.DeveloperName;
        ctx.put('accountId',   currentUser.AccountId);
        ctx.put('accountName', currentUser.Account.Name);
        ctx.put('accountType', recType);

        List<Map<String,String>> customers = new List<Map<String,String>>();

        if (recType == 'SuperStockist') {
            // ── 1. Distributors under this SS via Super_Stockist_Name__c ──
            for (Account acc : [
                SELECT Id, Name, Code__c
                FROM Account
                WHERE Super_Stockist_Name__c = :currentUser.AccountId
                  AND Is_Active__c           = true
                ORDER BY Name ASC
            ]) {
                Map<String,String> m = new Map<String,String>();
                m.put('value', String.valueOf(acc.Id));
                String code = (acc.Code__c != null && String.valueOf(acc.Code__c) != 'null')
                              ? '[' + acc.Code__c + '] ' : '';
                m.put('label', code + acc.Name + ' (Distributor)');
                m.put('customerType', 'Distributor');
                customers.add(m);
            }
            // ── 2. Direct retailers under this SS via Account.Distributor__c ──
            for (Account acc : [
                SELECT Id, Name, Retailer_Code__c
                FROM Account
                WHERE Distributor__c           = :currentUser.AccountId
                  AND RecordType.DeveloperName  = 'Retailer'
                  AND Is_Active__c              = true
                ORDER BY Name ASC
            ]) {
                Map<String,String> m = new Map<String,String>();
                m.put('value', String.valueOf(acc.Id));
                String code = (acc.Retailer_Code__c != null
                               && String.valueOf(acc.Retailer_Code__c) != 'null')
                              ? '[' + acc.Retailer_Code__c + '] ' : '';
                m.put('label', code + acc.Name + ' (Retailer)');
                m.put('customerType', 'Retailer');
                customers.add(m);
            }
            ctx.put('customerLabel', 'Distributor / Retailer');
        } else {
            // Distributor sees all active retailers via Account.Distributor__c
            for (Account acc : [
                SELECT Id, Name, Retailer_Code__c
                FROM Account
                WHERE Distributor__c             = :currentUser.AccountId
                  AND RecordType.DeveloperName   = 'Retailer'
                  AND Is_Active__c               = true
                ORDER BY Name ASC
            ]) {
                Map<String,String> m = new Map<String,String>();
                m.put('value', String.valueOf(acc.Id));
                String code = (acc.Retailer_Code__c != null
                               && String.valueOf(acc.Retailer_Code__c) != 'null')
                              ? '[' + acc.Retailer_Code__c + '] ' : '';
                m.put('label', code + acc.Name);
                m.put('customerType', 'Retailer');
                customers.add(m);
            }
            ctx.put('customerLabel', 'Retailer');
        }
        ctx.put('customers', customers);
        return ctx;
    }

    public class StatementLine {
        @AuraEnabled public String  txnDate;
        @AuraEnabled public String  txnType;
        @AuraEnabled public String  invoiceNumber;
        @AuraEnabled public Decimal debit;
        @AuraEnabled public Decimal credit;
        @AuraEnabled public Decimal balance;
        @AuraEnabled public String  comment;
    }

    public class StatementResult {
        @AuraEnabled public String  accountName;
        @AuraEnabled public String  customerName;
        @AuraEnabled public String  accountType;
        @AuraEnabled public String  customerType;
        @AuraEnabled public Decimal openingBalance;
        @AuraEnabled public Decimal closingBalance;
        @AuraEnabled public Decimal totalSales;
        @AuraEnabled public Decimal totalReturns;
        @AuraEnabled public Decimal totalCollections;
        @AuraEnabled public List<StatementLine> lines;
        @AuraEnabled public String  errorMessage;
    }

    @AuraEnabled(cacheable=false)
    public static StatementResult getStatement(String customerId, String fromDate, String toDate) {
        StatementResult result    = new StatementResult();
        result.lines              = new List<StatementLine>();
        result.totalSales         = 0;
        result.totalReturns       = 0;
        result.totalCollections   = 0;

        try {
            User currentUser = [
                SELECT AccountId, Account.Name, Account.RecordType.DeveloperName
                FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
            ];
            if (currentUser.AccountId == null) {
                result.errorMessage = 'No account linked to this portal user.';
                return result;
            }

            // Enforce 90-day maximum range
            Date startDateCheck = Date.valueOf(fromDate);
            Date endDateCheck   = Date.valueOf(toDate);
            if (startDateCheck.daysBetween(endDateCheck) > 90) {
                result.errorMessage = 'Date range cannot exceed 90 days.';
                return result;
            }

            Id ownerId = currentUser.AccountId;
            Id custId;
            try {
                custId = Id.valueOf(customerId);
            } catch (Exception idEx) {
                List<Account> accts = [SELECT Id FROM Account WHERE Name = :customerId LIMIT 1];
                if (accts.isEmpty()) {
                    result.errorMessage = 'Could not find customer: ' + customerId;
                    return result;
                }
                custId = accts[0].Id;
            }

            String rType = currentUser.Account.RecordType.DeveloperName;
            result.accountName = currentUser.Account.Name;
            result.accountType = rType;

            // ── Detect customer type for SS ──────────────────────────────────
            // For SS: check if custId is a Distributor (Under SS) or direct Retailer
            String custType = 'Retailer'; // default
            if (rType == 'SuperStockist') {
                List<Account> custAcc = [SELECT Id, RecordType.DeveloperName FROM Account WHERE Id = :custId LIMIT 1];
                if (!custAcc.isEmpty() && custAcc[0].RecordType.DeveloperName == 'Distributor') {
                    custType = 'Distributor';
                }
            }
            result.customerType = custType;

            // ── Get customer name ────────────────────────────────────────────
            String custName = '';
            if (rType == 'SuperStockist' && custType == 'Distributor') {
                List<Invoice__c> nameInv = [SELECT Under_SS__r.Name FROM Invoice__c
                    WHERE Distributor_Account__c = :ownerId AND Under_SS__c = :custId
                    AND RecordType.DeveloperName = 'Secondary_Invoice_Under_SS' LIMIT 1];
                custName = nameInv.isEmpty() ? String.valueOf(custId) : nameInv[0].Under_SS__r.Name;
            } else {
                List<Invoice__c> nameInv = [SELECT Retailer_Account__r.Name FROM Invoice__c
                    WHERE Distributor_Account__c = :ownerId AND Retailer_Account__c = :custId LIMIT 1];
                custName = nameInv.isEmpty() ? String.valueOf(custId) : nameInv[0].Retailer_Account__r.Name;
            }
            result.customerName = custName;

            Date startDate   = Date.valueOf(fromDate);
            Date endDate     = Date.valueOf(toDate);
            Date oneYearBack = startDate.addYears(-1);

            Decimal salesBefore = 0, cancelsBefore = 0, returnsBefore = 0, collectionsBefore = 0;

            // ── Opening Balance ──────────────────────────────────────────────
            if (rType == 'SuperStockist' && custType == 'Distributor') {
                // SS → Distributor (Under SS)
                for (AggregateResult ar : [SELECT SUM(Invoice_Amount__c) total FROM Invoice__c
                    WHERE Distributor_Account__c = :ownerId AND Under_SS__c = :custId
                    AND Invoice_Date__c < :startDate AND Invoice_Date__c >= :oneYearBack
                    AND Status__c != 'Cancelled' AND RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                ]) { salesBefore = ar.get('total') != null ? (Decimal)ar.get('total') : 0; }

                for (AggregateResult ar : [SELECT SUM(Invoice_Amount__c) total FROM Invoice__c
                    WHERE Distributor_Account__c = :ownerId AND Under_SS__c = :custId
                    AND Invoice_Date__c < :startDate AND Invoice_Date__c >= :oneYearBack
                    AND Status__c = 'Cancelled' AND RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                ]) { cancelsBefore = ar.get('total') != null ? (Decimal)ar.get('total') : 0; }

                for (AggregateResult ar : [SELECT SUM(Total_return_Incl_tax__c) total FROM Returns__c
                    WHERE Invoice__r.Distributor_Account__c = :ownerId AND Invoice__r.Under_SS__c = :custId
                    AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                    AND DAY_ONLY(CreatedDate) < :startDate AND DAY_ONLY(CreatedDate) >= :oneYearBack
                    AND IsDeleted = false
                ]) { returnsBefore = ar.get('total') != null ? (Decimal)ar.get('total') : 0; }

                for (AggregateResult ar : [SELECT SUM(Amount_Collected__c) total FROM Collection__c
                    WHERE Invoice__r.Distributor_Account__c = :ownerId AND Invoice__r.Under_SS__c = :custId
                    AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                    AND Payment_Date__c < :startDate AND Payment_Date__c >= :oneYearBack
                    AND IsDeleted = false
                ]) { collectionsBefore = ar.get('total') != null ? (Decimal)ar.get('total') : 0; }

            } else {
                // Distributor → Retailer OR SS → Direct Retailer
                String rtFilter = (rType == 'SuperStockist') ? 'Secondary_Invoice' : null;

                for (AggregateResult ar : [SELECT SUM(Invoice_Amount__c) total FROM Invoice__c
                    WHERE Distributor_Account__c = :ownerId AND Retailer_Account__c = :custId
                    AND Invoice_Date__c < :startDate AND Invoice_Date__c >= :oneYearBack
                    AND Status__c != 'Cancelled'
                ]) { salesBefore = ar.get('total') != null ? (Decimal)ar.get('total') : 0; }

                for (AggregateResult ar : [SELECT SUM(Invoice_Amount__c) total FROM Invoice__c
                    WHERE Distributor_Account__c = :ownerId AND Retailer_Account__c = :custId
                    AND Invoice_Date__c < :startDate AND Invoice_Date__c >= :oneYearBack
                    AND Status__c = 'Cancelled'
                ]) { cancelsBefore = ar.get('total') != null ? (Decimal)ar.get('total') : 0; }

                for (AggregateResult ar : [SELECT SUM(Total_return_Incl_tax__c) total FROM Returns__c
                    WHERE Invoice__r.Distributor_Account__c = :ownerId AND Invoice__r.Retailer_Account__c = :custId
                    AND DAY_ONLY(CreatedDate) < :startDate AND DAY_ONLY(CreatedDate) >= :oneYearBack
                    AND IsDeleted = false
                ]) { returnsBefore = ar.get('total') != null ? (Decimal)ar.get('total') : 0; }

                for (AggregateResult ar : [SELECT SUM(Amount_Collected__c) total FROM Collection__c
                    WHERE Invoice__r.Distributor_Account__c = :ownerId AND Invoice__r.Retailer_Account__c = :custId
                    AND Payment_Date__c < :startDate AND Payment_Date__c >= :oneYearBack
                    AND IsDeleted = false
                ]) { collectionsBefore = ar.get('total') != null ? (Decimal)ar.get('total') : 0; }
            }

            result.openingBalance = salesBefore - cancelsBefore - returnsBefore - collectionsBefore;

            // ── Transactions in period ───────────────────────────────────────
            Map<String, StatementLine> eventMap = new Map<String, StatementLine>();

            if (rType == 'SuperStockist' && custType == 'Distributor') {
                // SS → Distributor (Under SS)
                for (Invoice__c inv : [
                    SELECT Id, Name, Invoice_Number__c, Invoice_Date__c, Invoice_Amount__c, Status__c
                    FROM Invoice__c
                    WHERE Distributor_Account__c = :ownerId AND Under_SS__c = :custId
                    AND Invoice_Date__c >= :startDate AND Invoice_Date__c <= :endDate
                    AND RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                    ORDER BY Invoice_Date__c ASC, CreatedDate ASC
                ]) {
                    StatementLine line = new StatementLine();
                    line.txnDate = String.valueOf(inv.Invoice_Date__c);
                    line.txnType = inv.Status__c == 'Cancelled' ? 'Sale Cancel' : 'Sale';
                    line.invoiceNumber = String.isNotBlank(inv.Invoice_Number__c) ? inv.Invoice_Number__c : inv.Name;
                    Decimal amt = inv.Invoice_Amount__c != null ? inv.Invoice_Amount__c : 0;
                    line.debit = inv.Status__c == 'Cancelled' ? 0 : amt;
                    line.credit = inv.Status__c == 'Cancelled' ? amt : 0;
                    line.comment = inv.Status__c;
                    eventMap.put(line.txnDate + '_1_' + inv.Id, line);
                }
                for (Returns__c ret : [
                    SELECT Id, Name, Total_return_Incl_tax__c, CreatedDate,
                           Invoice__r.Name, Invoice__r.Invoice_Number__c
                    FROM Returns__c
                    WHERE Invoice__r.Distributor_Account__c = :ownerId AND Invoice__r.Under_SS__c = :custId
                    AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                    AND DAY_ONLY(CreatedDate) >= :startDate AND DAY_ONLY(CreatedDate) <= :endDate
                    AND IsDeleted = false ORDER BY CreatedDate ASC
                ]) {
                    StatementLine line = new StatementLine();
                    line.txnDate = String.valueOf(ret.CreatedDate.date());
                    line.txnType = 'Return';
                    line.invoiceNumber = ret.Invoice__r != null
                        ? (String.isNotBlank(ret.Invoice__r.Invoice_Number__c) ? ret.Invoice__r.Invoice_Number__c : ret.Invoice__r.Name) : ret.Name;
                    line.debit = 0;
                    line.credit = ret.Total_return_Incl_tax__c != null ? ret.Total_return_Incl_tax__c : 0;
                    line.comment = ret.Name;
                    eventMap.put(line.txnDate + '_2_' + ret.Id, line);
                }
                for (Collection__c col : [
                    SELECT Id, Payment_Date__c, Amount_Collected__c, Payment_Method__c, Narration__c,
                           Invoice__r.Name, Invoice__r.Invoice_Number__c
                    FROM Collection__c
                    WHERE Invoice__r.Distributor_Account__c = :ownerId AND Invoice__r.Under_SS__c = :custId
                    AND Invoice__r.RecordType.DeveloperName = 'Secondary_Invoice_Under_SS'
                    AND Payment_Date__c >= :startDate AND Payment_Date__c <= :endDate
                    AND IsDeleted = false ORDER BY Payment_Date__c ASC, CreatedDate ASC
                ]) {
                    StatementLine line = new StatementLine();
                    line.txnDate = String.valueOf(col.Payment_Date__c);
                    line.txnType = 'Collection';
                    line.invoiceNumber = col.Invoice__r != null
                        ? (String.isNotBlank(col.Invoice__r.Invoice_Number__c) ? col.Invoice__r.Invoice_Number__c : col.Invoice__r.Name) : '';
                    line.debit = 0;
                    line.credit = col.Amount_Collected__c != null ? col.Amount_Collected__c : 0;
                    line.comment = String.isNotBlank(col.Narration__c) ? col.Narration__c
                                 : String.isNotBlank(col.Payment_Method__c) ? col.Payment_Method__c : '';
                    eventMap.put(line.txnDate + '_3_' + col.Id, line);
                }

            } else {
                // Distributor → Retailer OR SS → Direct Retailer (Secondary_Invoice)
                for (Invoice__c inv : [
                    SELECT Id, Name, Invoice_Number__c, Invoice_Date__c, Invoice_Amount__c, Status__c
                    FROM Invoice__c
                    WHERE Distributor_Account__c = :ownerId AND Retailer_Account__c = :custId
                    AND Invoice_Date__c >= :startDate AND Invoice_Date__c <= :endDate
                    ORDER BY Invoice_Date__c ASC, CreatedDate ASC
                ]) {
                    StatementLine line = new StatementLine();
                    line.txnDate = String.valueOf(inv.Invoice_Date__c);
                    line.txnType = inv.Status__c == 'Cancelled' ? 'Sale Cancel' : 'Sale';
                    line.invoiceNumber = String.isNotBlank(inv.Invoice_Number__c) ? inv.Invoice_Number__c : inv.Name;
                    Decimal amt = inv.Invoice_Amount__c != null ? inv.Invoice_Amount__c : 0;
                    line.debit = inv.Status__c == 'Cancelled' ? 0 : amt;
                    line.credit = inv.Status__c == 'Cancelled' ? amt : 0;
                    line.comment = inv.Status__c;
                    eventMap.put(line.txnDate + '_1_' + inv.Id, line);
                }
                for (Returns__c ret : [
                    SELECT Id, Name, Total_return_Incl_tax__c, CreatedDate,
                           Invoice__r.Name, Invoice__r.Invoice_Number__c
                    FROM Returns__c
                    WHERE Invoice__r.Distributor_Account__c = :ownerId AND Invoice__r.Retailer_Account__c = :custId
                    AND DAY_ONLY(CreatedDate) >= :startDate AND DAY_ONLY(CreatedDate) <= :endDate
                    AND IsDeleted = false ORDER BY CreatedDate ASC
                ]) {
                    StatementLine line = new StatementLine();
                    line.txnDate = String.valueOf(ret.CreatedDate.date());
                    line.txnType = 'Return';
                    line.invoiceNumber = ret.Invoice__r != null
                        ? (String.isNotBlank(ret.Invoice__r.Invoice_Number__c) ? ret.Invoice__r.Invoice_Number__c : ret.Invoice__r.Name) : ret.Name;
                    line.debit = 0;
                    line.credit = ret.Total_return_Incl_tax__c != null ? ret.Total_return_Incl_tax__c : 0;
                    line.comment = ret.Name;
                    eventMap.put(line.txnDate + '_2_' + ret.Id, line);
                }
                for (Collection__c col : [
                    SELECT Id, Payment_Date__c, Amount_Collected__c, Payment_Method__c, Narration__c,
                           Invoice__r.Name, Invoice__r.Invoice_Number__c
                    FROM Collection__c
                    WHERE Invoice__r.Distributor_Account__c = :ownerId AND Invoice__r.Retailer_Account__c = :custId
                    AND Payment_Date__c >= :startDate AND Payment_Date__c <= :endDate
                    AND IsDeleted = false ORDER BY Payment_Date__c ASC, CreatedDate ASC
                ]) {
                    StatementLine line = new StatementLine();
                    line.txnDate = String.valueOf(col.Payment_Date__c);
                    line.txnType = 'Collection';
                    line.invoiceNumber = col.Invoice__r != null
                        ? (String.isNotBlank(col.Invoice__r.Invoice_Number__c) ? col.Invoice__r.Invoice_Number__c : col.Invoice__r.Name) : '';
                    line.debit = 0;
                    line.credit = col.Amount_Collected__c != null ? col.Amount_Collected__c : 0;
                    line.comment = String.isNotBlank(col.Narration__c) ? col.Narration__c
                                 : String.isNotBlank(col.Payment_Method__c) ? col.Payment_Method__c : '';
                    eventMap.put(line.txnDate + '_3_' + col.Id, line);
                }
            }

            // Sort and compute running balance
            List<String> sortedKeys = new List<String>(eventMap.keySet());
            sortedKeys.sort();
            Decimal runningBal = result.openingBalance;
            for (String k : sortedKeys) {
                StatementLine line = eventMap.get(k);
                if (line.txnType == 'Sale') { runningBal += line.debit; result.totalSales += line.debit; }
                else if (line.txnType == 'Sale Cancel' || line.txnType == 'Return') { runningBal -= line.credit; result.totalReturns += line.credit; }
                else if (line.txnType == 'Collection') { runningBal -= line.credit; result.totalCollections += line.credit; }
                line.balance = runningBal;
                result.lines.add(line);
            }
            result.closingBalance = runningBal;

        } catch (Exception ex) {
            result.errorMessage = ex.getMessage() + ' | ' + ex.getStackTraceString();
        }
        return result;
    }
}