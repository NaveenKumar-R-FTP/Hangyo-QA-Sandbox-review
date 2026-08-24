public without sharing class ZingHR_AttendanceService {

    public static void createLog(String logName, String requestData, String responseData, String status, String errorMessage) {
        try {
            Integration_Log__c logRec = new Integration_Log__c();
            logRec.Name = logName;
            logRec.Request__c = requestData;
            logRec.Response__c = responseData;
            logRec.Status__c = status;
            logRec.Error_Message__c = errorMessage;

            insert logRec;

        } catch (Exception e) {
            System.debug('Failed to create integration log: ' + e.getMessage());
        }
    }

    // ── Get JWT Token ──────────────────────────────────────────────────────────
    public static String getAccessToken() {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        //req.setEndpoint('callout:ZingHR_Auth/etl/api/v2/Auth/GenerateJWTToken?apiPermission=sswp');
        req.setEndpoint('callout:ZingHR_Auth/etl/api/v2/Auth/GenerateJWTToken?apiPermission=sswp');
        req.setMethod('GET');

        String username = System.Label.ZingHR_Username;
        String password = System.Label.ZingHR_Password;
        String auth = EncodingUtil.base64Encode(Blob.valueOf(username + ':' + password));
        req.setHeader('Authorization', 'Basic ' + auth);

        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String token = (String) result.get('data');
            System.debug('Access Token: ' + token);
            return token;
        } else {
            System.debug('Token Error: ' + res.getBody());
            return null;
        }
    }

    // ── Send Attendance or EOD swipes ──────────────────────────────────────────
    // swipeType: 'ATTENDANCE' → uses Attendance_Applied_on__c  (inOutFlag = '1')
    //            'EOD'        → uses EOD_Date_Time__c           (inOutFlag = '0')
    public static void sendAttendance(List<Attendance__c> attendanceList, String swipeType) {

        String token = getAccessToken();
        System.debug('Token: ' + token);
        if (token == null) return;

        List<Object>       swipes          = new List<Object>();
        List<Attendance__c> successRecords = new List<Attendance__c>();

        for (Attendance__c att : attendanceList) {

            // Pick the correct datetime and flag based on swipe type
            Datetime swipeDT;
            String   inOutFlag;

            if (swipeType == 'ATTENDANCE') {
                swipeDT   = att.Attendance_Applied_on__c;
                inOutFlag = '1';                          // swipe-in
            } else {
                swipeDT   = att.EOD_Date_Time__c;
                inOutFlag = '0';                          // swipe-out
            }

            // Skip if the datetime is somehow null (safety guard)
            if (swipeDT == null) continue;

            String swipeTime = swipeDT.format('yyyy-MM-dd HH:mm:ss');

            Map<String, Object> swipe = new Map<String, Object>();
            swipe.put('empIdentification',att.EMP_CODE__c);
            swipe.put('swipeDateTime',swipeTime);   // actual attendance/EOD time
            swipe.put('inOutFlag',inOutFlag);
            Datetime currentTime = System.now();
            String formattedTime = currentTime.format('yyyy-MM-dd HH:mm:ss');
            swipe.put('swipeReceiveDateTime',formattedTime);   
            swipe.put('terminalId','Terminal1');
            swipe.put('uniqueId','1');
            swipe.put('swipeLocation','');
            swipe.put('source','');

            swipes.add(swipe);
            successRecords.add(att);                       // track for stamping later
        }

        if (swipes.isEmpty()) return;

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('swipes', swipes);
        System.debug('Payload JSON: ' + JSON.serialize(payload));

        HttpRequest req = new HttpRequest();
        //req.setEndpoint('https://mservices-uat.zinghr.com/etl/api/v2/TNA/SynSwipes');
        req.setEndpoint('https://mservices.zinghr.com/etl/api/v2/TNA/SynSwipes');
        req.setMethod('POST');
        req.setHeader('Content-Type',  'application/json');
        req.setHeader('Authorization', 'Bearer ' + token);
        String requestBody = JSON.serialize(payload);
        req.setBody(JSON.serialize(payload));

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                createLog(
                    'ZingHR Swipe API - ' + swipeType,requestBody,res.getBody(),'Success',null
                );

                List<Attendance__c> toUpdate = new List<Attendance__c>();
                for (Attendance__c att : successRecords) {
                    Attendance__c upd = new Attendance__c(Id = att.Id);
                    if (swipeType == 'ATTENDANCE') {
                        upd.Attendance_Sent__c = true;
                    } else {
                        upd.EOD_Sent__c = true;
                    }
                    toUpdate.add(upd);
                }
                if (!toUpdate.isEmpty()) {
                    update toUpdate;
                }

            } else {
                createLog(
                    'ZingHR Swipe API - ' + swipeType,requestBody,res.getBody(),'Fail','HTTP Status: ' + res.getStatusCode()
                );
            }

        } catch (Exception e) {
            createLog(
                'ZingHR Swipe API - ' + swipeType,requestBody,null,'Fail',e.getMessage()
            );
        }
    }
}