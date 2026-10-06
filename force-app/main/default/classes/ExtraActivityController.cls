/**
* Class Name  : ExtraActivityController
* Test Class  : ExtraActivityControllerTest
* author      : IT Support
* CreatedDate : 06-10-26
* Description : Controller for the Extra Activity capture screen. BRD v6.0, items D2 and D4.
*               The record is inserted at Start Activity, not at Save, so an activity
*               survives the app being closed and can be resumed.
* */
public with sharing class ExtraActivityController {

    // What every method hands back to the screen.
    public class ActivityResponse {
        @AuraEnabled public Boolean isAllowed;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Extra_Activity__c activity;

        public ActivityResponse() {
            this.isAllowed = true;
            this.errorMessage = null;
            this.activity = null;
        }
    }

    private static final Set<String> VALID_TYPES = new Set<String>{
        'New Outlet Approach', 'Event', 'Meeting', 'Others'
    };

    private static final String STATUS_OPEN = 'In Progress';
    private static final String STATUS_DONE = 'Completed';

    /**
     * The user's own open activity for today, or null.
     * Drives the Resume bar on the Activity page and on My Visits.
     */
    @AuraEnabled(cacheable=true)
    public static Extra_Activity__c getInProgressActivity() {
        return findOpenActivity();
    }

    private static Extra_Activity__c findOpenActivity() {
        Id userId = UserInfo.getUserId();
        Date todayDate = Date.today();

        List<Extra_Activity__c> openRows = [
            SELECT Id, Name, Activity_Type__c, Activity_Date__c, Status__c,
                   Start_Time__c, End_Time__c, Duration_Minutes__c,
                   Start_Latitude__c, Start_Longitude__c, Location_Address__c,
                   Outlet_Name__c, Event_Name__c, City_Area__c,
                   Meeting_Location__c, Meeting_Type__c,
                   Expected_Sale__c, Remarks__c, Comment__c
            FROM Extra_Activity__c
            WHERE User__c = :userId
              AND Activity_Date__c = :todayDate
              AND Status__c = :STATUS_OPEN
            ORDER BY Start_Time__c DESC
            LIMIT 1
        ];

        return openRows.isEmpty() ? null : openRows[0];
    }

    /**
     * True when the user is checked in to a visit right now.
     * Mirrors VisitTaskController.checkAnyVisitTaskInprogress.
     */
    private static Boolean hasOpenVisit() {
        Date todayDate = Date.today();

        List<Visit_Task__c> openVisits = [
            SELECT Id
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :UserInfo.getUserId()
              AND Task_Planned_Date__c = :todayDate
              AND Status__c = 'In-Progress'
            LIMIT 1
        ];

        return !openVisits.isEmpty();
    }

    /**
     * Step 1 of the flow. Creates the record immediately so it survives the app closing.
     * The user is always the logged-in user. It is never accepted from the screen.
     */
    @AuraEnabled
    public static ActivityResponse startActivity(String activityType,
                                                 Decimal startLatitude,
                                                 Decimal startLongitude,
                                                 String locationAddress) {
        ActivityResponse response = new ActivityResponse();

        if (String.isBlank(activityType) || !VALID_TYPES.contains(activityType)) {
            response.isAllowed = false;
            response.errorMessage = 'Select a valid activity type.';
            return response;
        }

        if (hasOpenVisit()) {
            response.isAllowed = false;
            response.errorMessage = 'You are checked in to an outlet. Check out before adding an extra activity.';
            return response;
        }

        if (findOpenActivity() != null) {
            response.isAllowed = false;
            response.errorMessage = 'You already have an activity in progress. End it before starting another.';
            return response;
        }

        Extra_Activity__c activity = new Extra_Activity__c(
            Activity_Type__c    = activityType,
            Activity_Date__c    = Date.today(),
            Start_Time__c       = System.now(),
            Status__c           = STATUS_OPEN,
            User__c             = UserInfo.getUserId(),
            Start_Latitude__c   = startLatitude,
            Start_Longitude__c  = startLongitude,
            Location_Address__c = locationAddress
        );

        try {
            insert activity;
        } catch (DmlException e) {
            response.isAllowed = false;
            response.errorMessage = e.getDmlMessage(0);
            return response;
        }

        response.activity = activity;
        return response;
    }

    /**
     * Step 2. Stamps the end time and calculates the duration.
     * Neither value is ever accepted from the screen.
     */
    @AuraEnabled
    public static ActivityResponse endActivity(Id activityId) {
        ActivityResponse response = new ActivityResponse();

        Extra_Activity__c activity = loadOwnOpenActivity(activityId, response);
        if (activity == null) {
            return response;
        }

        DateTime endTime = System.now();
        Decimal elapsedMinutes =
            Decimal.valueOf(endTime.getTime() - activity.Start_Time__c.getTime()) / 60000;

        activity.End_Time__c = endTime;
        activity.Duration_Minutes__c = elapsedMinutes.setScale(0, System.RoundingMode.HALF_UP);

        try {
            update activity;
        } catch (DmlException e) {
            response.isAllowed = false;
            response.errorMessage = e.getDmlMessage(0);
            return response;
        }

        response.activity = activity;
        return response;
    }

    /**
     * Step 3. Writes the fields for this activity type and marks it Completed.
     * Only the fields that belong to the type are written; the rest stay blank.
     */
    @AuraEnabled
    public static ActivityResponse saveActivity(Id activityId,
                                                String outletName,
                                                String eventName,
                                                String cityArea,
                                                String meetingLocation,
                                                String meetingType,
                                                Decimal expectedSale,
                                                String remarks,
                                                String comment) {
        ActivityResponse response = new ActivityResponse();

        Extra_Activity__c activity = loadOwnOpenActivity(activityId, response);
        if (activity == null) {
            return response;
        }

        if (activity.End_Time__c == null) {
            response.isAllowed = false;
            response.errorMessage = 'End the activity before saving it.';
            return response;
        }

        if (activity.Activity_Type__c == 'New Outlet Approach') {
            activity.Outlet_Name__c   = outletName;
            activity.Expected_Sale__c = expectedSale;
            activity.Remarks__c       = remarks;

        } else if (activity.Activity_Type__c == 'Event') {
            activity.Event_Name__c    = eventName;
            activity.City_Area__c     = cityArea;
            activity.Expected_Sale__c = expectedSale;
            activity.Remarks__c       = remarks;

        } else if (activity.Activity_Type__c == 'Meeting') {
            activity.Meeting_Location__c = meetingLocation;
            activity.Meeting_Type__c     = meetingType;
            activity.Remarks__c          = remarks;

        } else if (activity.Activity_Type__c == 'Others') {
            activity.Comment__c = comment;
        }

        activity.Status__c = STATUS_DONE;

        try {
            update activity;
        } catch (DmlException e) {
            response.isAllowed = false;
            response.errorMessage = e.getDmlMessage(0);
            return response;
        }

        response.activity = activity;
        return response;
    }

    /**
     * Loads an activity and checks it belongs to the caller and is still open.
     * Fills the response with the reason and returns null when it does not.
     */
    private static Extra_Activity__c loadOwnOpenActivity(Id activityId, ActivityResponse response) {
        if (activityId == null) {
            response.isAllowed = false;
            response.errorMessage = 'No activity was supplied.';
            return null;
        }

        List<Extra_Activity__c> rows = [
            SELECT Id, User__c, Status__c, Activity_Type__c,
                   Start_Time__c, End_Time__c, Duration_Minutes__c,
                   Outlet_Name__c, Event_Name__c, City_Area__c,
                   Meeting_Location__c, Meeting_Type__c,
                   Expected_Sale__c, Remarks__c, Comment__c
            FROM Extra_Activity__c
            WHERE Id = :activityId
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            response.isAllowed = false;
            response.errorMessage = 'Activity not found.';
            return null;
        }

        Extra_Activity__c activity = rows[0];

        if (activity.User__c != UserInfo.getUserId()) {
            response.isAllowed = false;
            response.errorMessage = 'You can only change your own activity.';
            return null;
        }

        if (activity.Status__c != STATUS_OPEN) {
            response.isAllowed = false;
            response.errorMessage = 'This activity is already saved and cannot be changed.';
            return null;
        }

        return activity;
    }
}