/**
 * @description Resolves allowed Salesforce User Ids for the Tally pull API
 *              from Tally_Allowed_User__mdt.
 *              Uses getAll() instead of SOQL because Client Credentials /
 *              Integration User contexts reject SOQL against this CMDT type.
 */
public with sharing class TallyAllowedUserService {
    /** Picklist API value for active records on Is_Active__c. */
    private static final String ACTIVE_VALUE = 'True';

    /**
     * @description Returns User Ids from active Tally_Allowed_User__mdt records.
     *              Blank and invalid User_Id__c values are ignored.
     * @return Set of active allowed User Ids (never null)
     */
    public static Set<Id> getAllowedUserIds() {
        Set<Id> allowedUserIds = new Set<Id>();

        Map<String, Tally_Allowed_User__mdt> allRecords = Tally_Allowed_User__mdt.getAll();
        if (allRecords == null || allRecords.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'TallyAllowedUserService: no CMDT records found.');
            return allowedUserIds;
        }

        for (Tally_Allowed_User__mdt allowedUser : allRecords.values()) {
            if (allowedUser == null) {
                continue;
            }

            // Null-safe picklist check (handles null / casing differences like "true").
            if (!ACTIVE_VALUE.equalsIgnoreCase(allowedUser.Is_Active__c)) {
                continue;
            }

            String userId = allowedUser.User_Id__c == null
                ? null
                : allowedUser.User_Id__c.trim();

            if (String.isBlank(userId)) {
                continue;
            }

            Id parsedUserId = tryParseUserId(userId);
            if (parsedUserId != null) {
                allowedUserIds.add(parsedUserId);
            }
        }

        System.debug(
            LoggingLevel.INFO,
            'TallyAllowedUserService: allowed user count = ' + allowedUserIds.size()
        );
        return allowedUserIds;
    }

    /**
     * @description Safely converts text to a Salesforce Id.
     * @param userIdValue Candidate User Id from CMDT
     * @return Parsed Id, or null when invalid
     */
    private static Id tryParseUserId(String userIdValue) {
        try {
            return Id.valueOf(userIdValue.trim());
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'TallyAllowedUserService: skipping invalid User_Id__c value: ' + userIdValue
            );
            return null;
        }
    }
}