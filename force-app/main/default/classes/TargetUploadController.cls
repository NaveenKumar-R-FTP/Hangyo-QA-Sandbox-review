/**
 * TargetUploadController
 * ---------------------------------------------------------------------------
 * Backs the "Target Upload" LWC so the MIS team can upload/update secondary
 * targets from a simple CSV (Employee Code, Month, Year, Secondary Target) —
 * no Salesforce Ids, no key formats, no Data Import Wizard.
 *
 * For each row it resolves the User by EmployeeNumber, builds the same
 * Target_Key__c the rollup uses (<15-char Id>-YYYY-MM), and upserts the monthly
 * Sales_Target__c row (record type "Sales Performance - Month"). Existing rows
 * are updated; new ones created. Only the TARGET is written — actuals are left
 * to SecondaryActualRollup. Reads User; never touches Invoice__c.
 */
public with sharing class TargetUploadController {

    private static final String MONTH_RT = 'Sales_Target_Month';

    public class RowResult {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String employeeCode;
        @AuraEnabled public String status;   // 'Success' | 'Error'
        @AuraEnabled public String message;
    }
    public class UploadResult {
        @AuraEnabled public Integer total   = 0;
        @AuraEnabled public Integer success = 0;
        @AuraEnabled public Integer failed  = 0;
        @AuraEnabled public List<RowResult> rows = new List<RowResult>();
    }

    /** CSV template the Download button hands the MIS team. */
    @AuraEnabled(cacheable=true)
    public static String getTemplate() {
        return 'Employee Code,Month,Year,Secondary Target\n'
             + '11795,8,2026,160000\n';
    }

    /** Parse the uploaded CSV, resolve users, and upsert monthly targets. */
    @AuraEnabled
    public static UploadResult uploadTargets(String csvData) {
        UploadResult result = new UploadResult();
        if (String.isBlank(csvData)) return result;

        List<String> lines = csvData.replace('\r\n', '\n').replace('\r', '\n').split('\n');

        // Parse rows (skip header) and collect employee codes.
        List<Map<String, String>> parsed = new List<Map<String, String>>();
        Set<String> codes = new Set<String>();
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;
            List<String> c = line.split(',');
            Map<String, String> row = new Map<String, String>{
                'rowNum' => String.valueOf(i + 1),
                'code'   => c.size() > 0 ? c[0].trim() : '',
                'month'  => c.size() > 1 ? c[1].trim() : '',
                'year'   => c.size() > 2 ? c[2].trim() : '',
                'target' => c.size() > 3 ? c[3].trim() : ''
            };
            parsed.add(row);
            if (String.isNotBlank(row.get('code'))) codes.add(row.get('code'));
        }

        Map<String, Id> codeToUser = new Map<String, Id>();
        for (User u : [SELECT Id, EmployeeNumber FROM User WHERE EmployeeNumber IN :codes AND IsActive = true]) {
            if (u.EmployeeNumber != null) codeToUser.put(u.EmployeeNumber, u.Id);
        }

        Id monthRt = Schema.SObjectType.Sales_Target__c
            .getRecordTypeInfosByDeveloperName().get(MONTH_RT).getRecordTypeId();

        List<Sales_Target__c> toUpsert = new List<Sales_Target__c>();
        List<RowResult>       pending  = new List<RowResult>(); // aligned with toUpsert

        for (Map<String, String> row : parsed) {
            RowResult rr = new RowResult();
            rr.rowNumber    = Integer.valueOf(row.get('rowNum'));
            rr.employeeCode = row.get('code');
            result.total++;

            String code = row.get('code');
            if (String.isBlank(code)) { fail(result, rr, 'Missing Employee Code'); continue; }
            if (!codeToUser.containsKey(code)) { fail(result, rr, 'Employee Code not found / inactive'); continue; }

            Integer monthNo = parseMonth(row.get('month'));
            if (monthNo == null) { fail(result, rr, 'Invalid Month (use 1-12)'); continue; }

            Integer yr;
            try { yr = Integer.valueOf(row.get('year')); } catch (Exception e) { fail(result, rr, 'Invalid Year'); continue; }
            if (yr < 2000 || yr > 2100) { fail(result, rr, 'Invalid Year'); continue; }

            Decimal target;
            try { target = Decimal.valueOf(row.get('target').replace(',', '')); }
            catch (Exception e) { fail(result, rr, 'Invalid Target amount'); continue; }

            Id  uid = codeToUser.get(code);
            String mm = monthNo < 10 ? '0' + monthNo : String.valueOf(monthNo);
            toUpsert.add(new Sales_Target__c(
                Target_Key__c             = String.valueOf(uid) + '-' + yr + '-' + mm,
                Assigned_To__c            = uid,
                Number_of_Month__c        = monthNo,
                From_Date__c              = Date.newInstance(yr, monthNo, 1),
                To_Date__c                = Date.newInstance(yr, monthNo, Date.daysInMonth(yr, monthNo)),
                Secondary_Sales_Target__c = target,
                RecordTypeId              = monthRt
            ));
            rr.status  = 'Success';
            rr.message = 'Target set: ' + target;
            pending.add(rr);
        }

        if (!toUpsert.isEmpty()) {
            Database.UpsertResult[] urs = Database.upsert(toUpsert, Sales_Target__c.Target_Key__c, false);
            for (Integer i = 0; i < urs.size(); i++) {
                RowResult rr = pending[i];
                if (urs[i].isSuccess()) {
                    result.success++;
                } else {
                    rr.status  = 'Error';
                    rr.message = urs[i].getErrors().isEmpty() ? 'Save failed' : urs[i].getErrors()[0].getMessage();
                    result.failed++;
                }
                result.rows.add(rr);
            }
        }
        return result;
    }

    private static void fail(UploadResult res, RowResult rr, String msg) {
        rr.status = 'Error';
        rr.message = msg;
        res.failed++;
        res.rows.add(rr);
    }

    @TestVisible
    private static Integer parseMonth(String m) {
        if (String.isBlank(m)) return null;
        m = m.trim();
        try { Integer n = Integer.valueOf(m); return (n >= 1 && n <= 12) ? n : null; } catch (Exception e) {}
        Map<String, Integer> names = new Map<String, Integer>{
            'january'=>1,'february'=>2,'march'=>3,'april'=>4,'may'=>5,'june'=>6,
            'july'=>7,'august'=>8,'september'=>9,'october'=>10,'november'=>11,'december'=>12
        };
        return names.get(m.toLowerCase());
    }
}