public without sharing class UserHierarchyController {

   @AuraEnabled(cacheable=true)
public static List<Attendance__c> getAllAttendanceRecords(List<Id> userIds, Date forDate) {
    System.debug('START: getAllAttendanceRecords');
    System.debug('Input userIds: ' + userIds);
    System.debug('Input forDate: ' + forDate);
    
    if (userIds == null || userIds.isEmpty() || forDate == null) {
        System.debug('Empty parameters. Returning empty list.');
        return new List<Attendance__c>();
    }
    
    List<Attendance__c> result = [
        SELECT Id, User__c, User__r.FirstName, User__r.LastName, 
               Status__c, Work__c, Date__c, Leave_Period__c
        FROM Attendance__c
        WHERE User__c IN :userIds 
        AND Date__c = :forDate
        AND Status__c IN ('Absent', 'Present', 'Leave', 'Present Half Day')
        ORDER BY User__r.LastName, User__r.FirstName
    ];
    
    System.debug('All Attendance records found: ' + result.size());
    System.debug('Attendance records: ' + JSON.serialize(result));
    
    return result;
}
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getAttendanceSummary(List<Id> userIds, Date forDate) {
        System.debug('START: getAttendanceSummary');
        System.debug('Input userIds: ' + userIds);
        System.debug('Input forDate: ' + forDate);
        
        Map<String, Integer> result = new Map<String, Integer>();
        result.put('Absent', 0);
        result.put('Leave', 0);
        result.put('Present', 0);
        result.put('Official Work', 0);
        result.put('Retailing', 0);
        
        if (userIds == null || userIds.isEmpty()) {
            System.debug('userIds is NULL or EMPTY. Returning zeroed map.');
            return result;
        }
        
        List<Attendance__c> atts = [
            SELECT Id, User__c, Status__c, Work__c, Date__c
            FROM Attendance__c
            WHERE User__c IN :userIds AND Date__c = :forDate
        ];
        
        System.debug('Attendance records found: ' + atts.size());
        
        Set<Id> countedRetailingUsers = new Set<Id>();
        
        for (Attendance__c a : atts) {
            String status = a.Status__c == null ? '' : a.Status__c.trim();
            String work   = a.Work__c == null ? '' : a.Work__c.trim();
            
            if (status == 'Leave') {
                result.put('Leave', result.get('Leave') + 1);
                continue; // once absent, skip other checks
            }
             if (status == 'Absent') {
                result.put('Absent', result.get('Absent') + 1);
                continue; // once absent, skip other checks
            }
            
            if (status == 'Present') {
                result.put('Present', result.get('Present') + 1);
                
                if (work == 'Official Meeting') {
                    result.put('Official Work', result.get('Official Work') + 1);
                }
                
                if (work == 'Audit' || work == 'Beat') {
                    if (a.User__c != null && !countedRetailingUsers.contains(a.User__c)) {
                        countedRetailingUsers.add(a.User__c);
                        result.put('Retailing', result.get('Retailing') + 1);
                    }
                }
            }
        }
        
        System.debug('FINAL RESULT Attendance Summary (counts only): ' + result);
        return result;
    }
    
    @AuraEnabled//(cacheable=true)
    public static List<Attendance__c> getLeaveUsersfirst(List<Id> userIds) {
        System.debug('START: getLeaveUsers');
        System.debug('Input userIds: ' + userIds);
        
        List<Attendance__c> result = [SELECT Id, User__c, User__r.FirstName, User__r.LastName, Leave_Period__c, Status__c, Date__c FROM Attendance__c 
                                      WHERE User__c IN :userIds AND (Status__c = 'Leave' OR  Status__c = 'Present Half Day') AND Date__c = :Date.today()];
        
        System.debug('Leave Users found: ' + result.size());
        System.debug('Leave User records: ' + JSON.serialize(result));
        
        return result;
    }
    
    @AuraEnabled
    public static List<Map<String, String>> getLeaveUsers(List<Id> userIds) {
        system.debug('userIds = ' + userIds);
        List<Map<String,String>> resultMap = new List<Map<String,String>>();
        
        for (Attendance__c att : [
            SELECT Id, User__c, User__r.FirstName, User__r.LastName, Leave_Period__c, Status__c, Date__c 
            FROM Attendance__c 
            WHERE User__c IN :userIds AND (Status__c = 'Leave' OR  Status__c = 'Present Half Day' ) AND Date__c = :Date.today()
        ]) {
            Map<String,String> m = new Map<String,String>();
            m.put('Id', att.Id);
            m.put('UserId', att.User__c);
            m.put('UserName', att.User__r.FirstName + ' ' + att.User__r.LastName);
            m.put('LeavePeriod', String.valueOf(att.Leave_Period__c));
            m.put('Status', att.Status__c);
            m.put('Date', String.valueOf(att.Date__c));
            resultMap.add(m);
        }
        
        return resultMap;
    }
    
    
    @AuraEnabled(cacheable=true)
    public static List<Visit__c> getRetailingDetails(List<Id> userIds) {
        System.debug('⚡ START: getRetailingDetails');
        System.debug('➡ Input userIds: ' + userIds);
        
        List<Visit__c> visits = [
            SELECT Id, Visitor_Name__c, Visitor_Name__r.FirstName, Visitor_Name__r.LastName, Beat__c, Beat__r.Name, 
            (SELECT Id, Retailer_Address_New__c 
             FROM Visit_Tasks__r 
             WHERE Status__c = 'In-Progress'
             LIMIT 1)
            FROM Visit__c
            WHERE Visitor_Name__c IN :userIds AND Visit_planned_date__c = :Date.today()
        ];
        
        System.debug('✅ Retailing records found: ' + visits.size());
        System.debug('🟢 Retailing Details: ' + JSON.serialize(visits));
        
        return visits;
    }
}