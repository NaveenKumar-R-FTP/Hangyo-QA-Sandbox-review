/* Hangyo User Tracking Dashboard — Lightning API facade over business-object aggregation. */
public with sharing class UserTrackingController {
    /** Org-default fallbacks when Google_API_User_Tracking__c fields are blank (matches QA org default). */
    private static final String DEFAULT_DASHBOARD_ACCESS_ROLES_CSV = 'ADMIN,ZSM,RSM,ASM,SSO';
    private static final String DEFAULT_DIRECTION_API_ACCESS_ROLES_CSV = 'ZSM';
    private static final String DEFAULT_HAVERSINE_ACCESS_ROLES_CSV = 'ADMIN,RSM,ASM,SSO';

    private static final String SYSTEM_ADMINISTRATOR_PROFILE = 'System Administrator';
    private static final String ROUTING_MODE_DIRECTIONS = 'directions';
    private static final String ROUTING_MODE_HAVERSINE = 'haversine';
    public static final String DASHBOARD_ACCESS_DENIED_MESSAGE =
        'You do not have access to the User Tracking Dashboard.';

    @TestVisible
    private static Boolean testDashboardAccessOverride;

    /** Test hooks: simulate custom-setting field values / missing hierarchy row (tests only). */
    @TestVisible
    private static Boolean testGoogleApiUserTrackingConfigUnavailable;
    @TestVisible
    private static String testDashboardAccessRolesOverride;
    @TestVisible
    private static String testDirectionApiAccessRolesOverride;
    @TestVisible
    private static String testHaversineAccessRolesOverride;

    public class DashboardAccessResult {
        @AuraEnabled public Boolean allowed;
        @AuraEnabled public String userRoleName;
        @AuraEnabled public String profileName;
        /** 'directions' (ZSM) or 'haversine' (ADMIN, RSM, ASM, SSO). */
        @AuraEnabled public String routingMode;

        public DashboardAccessResult(
            Boolean allowed,
            String userRoleName,
            String profileName,
            String routingMode
        ) {
            this.allowed = allowed;
            this.userRoleName = userRoleName;
            this.profileName = profileName;
            this.routingMode = routingMode;
        }
    }

    public class UserOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;

        public UserOption(Id id, String name) {
            this.id = id;
            this.name = name;
        }
    }

    public class DashboardSummary {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Integer totalProductiveOutlets = 0;
        @AuraEnabled public Integer totalNonProductiveOutlets = 0;
        @AuraEnabled public Integer totalVisitedOutlets = 0;
        @AuraEnabled public Decimal totalOrderValue = 0;
        @AuraEnabled public Integer attendanceCount = 0;
        @AuraEnabled public Integer eodCount = 0;
        @AuraEnabled public Integer newOutletAdded = 0;
        @AuraEnabled public Integer rawRowCount = 0;
    }

    @AuraEnabled(cacheable=true)
    
    //Called in UserTrackingDashboard.js
    public static DashboardAccessResult getDashboardAccess() {
        User u = queryCurrentUserForAccess();
        Boolean allowed = isDashboardAccessAllowed(u);
        String roleName = employeeRoleForAccess(u);
        String profileName = u.Profile != null ? u.Profile.Name : null;
        String routingMode = usesGoogleDirectionsRouting(u)
            ? ROUTING_MODE_DIRECTIONS
            : ROUTING_MODE_HAVERSINE;
        return new DashboardAccessResult(allowed, roleName, profileName, routingMode);
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getUsers() {
        assertDashboardAccessAllowed();
        List<UserOption> results = new List<UserOption>();
        for (UserTrackingDashboardService.UserOption o : UserTrackingDashboardService.getUsers()) {
            results.add(new UserOption(o.id, o.name));
        }
        return results;
    }

    /**
     * Single call: summary tiles + chronologically sorted activities for map/route.
     */
    @AuraEnabled
    public static UserTrackingDashboardService.TrackingDashboardResponse getDashboardData(
        Id userId,
        Date selectedDate
    ) {
        assertDashboardAccessAllowed();
        return UserTrackingDashboardService.getDashboardData(userId, selectedDate);
    }

    private static final String MAP_EMBED_ASSET_VERSION = 'iwHangyo26';

    @TestVisible
    private static String testMapAuthorityHostOverride;

    @AuraEnabled(cacheable=true)
    public static String getUserTrackingMapEmbedUrl() {
        assertDashboardAccessAllowed();
        String path = Page.UserTrackingMapEmbed.getUrl();
        if (String.isBlank(path)) {
            path = '/apex/UserTrackingMapEmbed';
        }
        if (!path.startsWith('/')) {
            path = '/' + path;
        }
        String u = mapIframeAuthorityBaseUrl() + path;
        String sep = u.contains('?') ? '&' : '?';
        String q = 'hmv=' + MAP_EMBED_ASSET_VERSION;
        String parentOrigin = deriveLightningPostMessageOriginFromHost(mapOrgDomainHostForPostMessage());
        if (String.isNotBlank(parentOrigin)) {
            q += '&hpo=' + EncodingUtil.urlEncode(parentOrigin, 'UTF-8');
        }
        return u + sep + q;
    }

    /**
     * Trusted Lightning parent origin for VF → LWC postMessage (hosting LEX frame).
     * Pair with getUserTrackingMapIframePostMessageOrigin() which targets the VF iframe for LWC → VF.
     */
    @AuraEnabled(cacheable=true)
    public static String getUserTrackingMapParentPostMessageOrigin() {
        assertDashboardAccessAllowed();
        String lex = deriveLightningPostMessageOriginFromHost(mapOrgDomainHostForPostMessage());
        return lex != null ? lex : '';
    }

    @AuraEnabled(cacheable=true)
    public static String getUserTrackingMapIframePostMessageOrigin() {
        assertDashboardAccessAllowed();
        String vf = deriveVisualforcePostMessageOriginFromHost(extractHost(mapIframeAuthorityBaseUrl()));
        return vf != null ? vf : '';
    }

    @AuraEnabled(cacheable=true)
    public static String getGoogleMapsJavaScriptApiKey() {
        assertDashboardAccessAllowed();
        String k = System.Label.Google_Maps_API_Key;
        return (k == null) ? '' : k.trim();
    }

    /**
     * Central dashboard gate — used by this controller and UserTrackingDashboardService
     * so direct @AuraEnabled service calls cannot bypass access checks.
     */
    public static void assertDashboardAccessAllowed() {
        if (!isDashboardAccessAllowed(queryCurrentUserForAccess())) {
            throw new AuraHandledException(DASHBOARD_ACCESS_DENIED_MESSAGE);
        }
    }

    private static User queryCurrentUserForAccess() {
        /* SYSTEM_MODE: access check must read Employee_Role__c even when FLS hides it from the running user. */
        return [
            SELECT Id, Profile.Name, Employee_Role__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }

    /** Dashboard access is driven by User.Employee_Role__c (not UserRole hierarchy). */
    private static String employeeRoleForAccess(User u) {
        if (u == null || String.isBlank(u.Employee_Role__c)) {
            return null;
        }
        return u.Employee_Role__c.trim();
    }

    @TestVisible
    private static Boolean isDashboardAccessAllowed(User u) {
        if (Test.isRunningTest() && testDashboardAccessOverride != null) {
            return testDashboardAccessOverride;
        }
        if (u == null) {
            return false;
        }
        if (
            u.Profile != null &&
            SYSTEM_ADMINISTRATOR_PROFILE.equalsIgnoreCase(u.Profile.Name.trim())
        ) {
            return true;
        }
        return roleNameMatchesAllowedCode(
            employeeRoleForAccess(u),
            dashboardAllowedRoleCodes()
        );
    }

    @TestVisible
    private static Boolean usesGoogleDirectionsRouting(User u) {
        return roleNameMatchesAllowedCode(
            employeeRoleForAccess(u),
            directionApiAccessRoleCodes()
        );
    }

    @TestVisible
    private static Boolean roleNameMatchesAllowedCode(String roleName) {
        return roleNameMatchesAllowedCode(roleName, dashboardAllowedRoleCodes());
    }

    /**
     * Hierarchy custom setting: User, then Profile, then Organization (Setup - Google API User Tracking).
     */
    @TestVisible
    private static Google_API_User_Tracking__c googleApiUserTrackingConfig() {
        if (Test.isRunningTest() && testGoogleApiUserTrackingConfigUnavailable == true) {
            return null;
        }
        if (!Schema.getGlobalDescribe().containsKey('google_api_user_tracking__c')) {
            return null;
        }
        try {
            return Google_API_User_Tracking__c.getInstance();
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'UserTrackingController: Unable to read Google_API_User_Tracking__c — ' + ex.getMessage()
            );
            return null;
        }
    }

    @TestVisible
    private static Set<String> dashboardAllowedRoleCodes() {
        return resolveConfiguredRoleCodes(
            readCustomSettingRoleCsv(
                googleApiUserTrackingConfig(),
                testDashboardAccessRolesOverride,
                'Dashboard_Access_Roles__c'
            ),
            DEFAULT_DASHBOARD_ACCESS_ROLES_CSV,
            'Dashboard_Access_Roles__c'
        );
    }

    @TestVisible
    private static Set<String> directionApiAccessRoleCodes() {
        return resolveConfiguredRoleCodes(
            readCustomSettingRoleCsv(
                googleApiUserTrackingConfig(),
                testDirectionApiAccessRolesOverride,
                'Direction_API_Access_Roles__c'
            ),
            DEFAULT_DIRECTION_API_ACCESS_ROLES_CSV,
            'Direction_API_Access_Roles__c'
        );
    }

    @TestVisible
    private static Set<String> haversineAccessRoleCodes() {
        return resolveConfiguredRoleCodes(
            readCustomSettingRoleCsv(
                googleApiUserTrackingConfig(),
                testHaversineAccessRolesOverride,
                'Haversine_Access_Roles__c'
            ),
            DEFAULT_HAVERSINE_ACCESS_ROLES_CSV,
            'Haversine_Access_Roles__c'
        );
    }

    /**
     * Reads a role CSV field from hierarchy custom setting; null-safe when cfg or field is missing.
     */
    @TestVisible
    private static String readCustomSettingRoleCsv(
        Google_API_User_Tracking__c cfg,
        String testOverride,
        String fieldApiName
    ) {
        if (Test.isRunningTest() && testOverride != null) {
            return TEST_OVERRIDE_USE_NULL.equals(testOverride) ? null : testOverride;
        }
        if (cfg == null) {
            return null;
        }
        if (fieldApiName == 'Dashboard_Access_Roles__c') {
            return cfg.Dashboard_Access_Roles__c;
        }
        if (fieldApiName == 'Direction_API_Access_Roles__c') {
            return cfg.Direction_API_Access_Roles__c;
        }
        if (fieldApiName == 'Haversine_Access_Roles__c') {
            return cfg.Haversine_Access_Roles__c;
        }
        return null;
    }

    private static final String TEST_OVERRIDE_USE_NULL = '__UT_NULL__';

    /**
     * Central resolver: parse CSV from custom setting (or fallback), normalize to uppercase Set.
     * Blank / missing field values use fallbackCsv; empty result denies non-admin users via exact match.
     */
    @TestVisible
    private static Set<String> resolveConfiguredRoleCodes(
        String rawCsv,
        String fallbackCsv,
        String fieldLabel
    ) {
        Set<String> codes = parseCommaSeparatedRoleCodeSet(rawCsv, fallbackCsv);
        if (codes.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'UserTrackingController: No role codes resolved for ' +
                    fieldLabel +
                    '; non-admin dashboard access will be denied.'
            );
        }
        return codes;
    }

    /**
     * Parses CSV role codes: trim, ignore blanks, uppercase, dedupe (Set), exact Employee_Role__c match only.
     */
    @TestVisible
    private static Set<String> parseCommaSeparatedRoleCodeSet(String csv, String fallbackCsv) {
        String source = String.isNotBlank(csv) ? csv : fallbackCsv;
        Set<String> codes = new Set<String>();
        if (String.isBlank(source)) {
            return codes;
        }
        for (String part : source.split(',')) {
            String token = part != null ? part.trim() : '';
            if (String.isBlank(token)) {
                continue;
            }
            codes.add(token.toUpperCase());
        }
        return codes;
    }

    /** Seeds org-default hierarchy CS in unit tests (see UserTrackingControllerTest @TestSetup). */
    @TestVisible
    private static void ensureGoogleApiUserTrackingOrgDefaultsForTest() {
        if (!Test.isRunningTest() || !Schema.getGlobalDescribe().containsKey('google_api_user_tracking__c')) {
            return;
        }
        Google_API_User_Tracking__c row = Google_API_User_Tracking__c.getOrgDefaults();
        if (row == null || row.Id == null) {
            row = new Google_API_User_Tracking__c();
            row.SetupOwnerId = UserInfo.getOrganizationId();
        }
        row.Dashboard_Access_Roles__c = DEFAULT_DASHBOARD_ACCESS_ROLES_CSV;
        row.Direction_API_Access_Roles__c = DEFAULT_DIRECTION_API_ACCESS_ROLES_CSV;
        row.Haversine_Access_Roles__c = DEFAULT_HAVERSINE_ACCESS_ROLES_CSV;
        upsert row;
    }

    /** Exact match only: Employee_Role__c (trimmed, upper) must be a member of allowedCodes. */
    @TestVisible
    private static Boolean roleNameMatchesAllowedCode(
        String roleName,
        Set<String> allowedCodes
    ) {
        if (String.isBlank(roleName) || allowedCodes == null || allowedCodes.isEmpty()) {
            return false;
        }
        return allowedCodes.contains(roleName.trim().toUpperCase());
    }

    private static String mapIframeAuthorityBaseUrl() {
        String base;
        if (Test.isRunningTest() && String.isNotBlank(testMapAuthorityHostOverride)) {
            base = stripTrailingSlash('https://' + testMapAuthorityHostOverride);
        } else {
            base = stripTrailingSlash(Url.getOrgDomainUrl().toExternalForm());
        }
        String host = extractHost(base);
        if (String.isBlank(host)) {
            return base;
        }
        final String SANDBOX_LEX = '.sandbox.lightning.force.com';
        final String LEX = '.lightning.force.com';
        String hostLower = host.toLowerCase();

        if (hostLower.endsWith(SANDBOX_LEX)) {
            String stub = host.substring(0, host.length() - SANDBOX_LEX.length());
            return stripTrailingSlash('https://' + stub + '.sandbox.my.salesforce.com');
        }
        if (hostLower.endsWith(LEX)) {
            String stub = host.substring(0, host.length() - LEX.length());
            return stripTrailingSlash('https://' + stub + '.my.salesforce.com');
        }
        return base;
    }

    private static String deriveVisualforcePostMessageOriginFromHost(String host) {
        if (String.isBlank(host)) {
            return null;
        }
        final String SANDBOX_MY = '.sandbox.my.salesforce.com';
        final String MY = '.my.salesforce.com';
        String lower = host.toLowerCase();
        if (lower.endsWith(SANDBOX_MY)) {
            String stub = host.substring(0, host.length() - SANDBOX_MY.length());
            return 'https://' + stub + '--c.sandbox.vf.force.com';
        }
        if (lower.endsWith(MY) && !lower.contains('.sandbox.my.salesforce')) {
            String stub = host.substring(0, host.length() - MY.length());
            return 'https://' + stub + '--c.vf.force.com';
        }
        return null;
    }

    /**
     * Strict hostname allow-list for User Tracking postMessage origins (Apex-side parity with LWC/VF).
     * Never use String.contains('.force.com') — spoofed hosts such as fake-force.com must not match.
     */
    @TestVisible
    private static Boolean isTrustedSalesforceHostname(String hostname) {
        if (String.isBlank(hostname)) {
            return false;
        }
        String h = hostname.toLowerCase();
        return h.endsWith('.vf.force.com')
            || h.endsWith('.sandbox.vf.force.com')
            || h.endsWith('.visualforce.com')
            || h.endsWith('.lightning.force.com')
            || h.endsWith('.my.salesforce.com')
            || h.endsWith('.sandbox.my.salesforce.com')
            || h.endsWith('.cloudforce.com');
    }

    @TestVisible
    private static Boolean isTrustedSalesforceOrigin(String originUrl) {
        if (String.isBlank(originUrl)) {
            return false;
        }
        try {
            String host = extractHost(originUrl.trim());
            if (String.isBlank(host)) {
                return false;
            }
            if (!originUrl.trim().toLowerCase().startsWith('https://')) {
                return false;
            }
            return isTrustedSalesforceHostname(host);
        } catch (Exception ex) {
            return false;
        }
    }

    /** Org hostname used to derive trusted postMessage origins (respects test override). */
    private static String mapOrgDomainHostForPostMessage() {
        String base;
        if (Test.isRunningTest() && String.isNotBlank(testMapAuthorityHostOverride)) {
            base = stripTrailingSlash('https://' + testMapAuthorityHostOverride);
        } else {
            base = stripTrailingSlash(Url.getOrgDomainUrl().toExternalForm());
        }
        return extractHost(base);
    }

    /**
     * Lightning LEX origin for VF → parent postMessage. Never use '*' — restricts delivery to the hosting LEX frame.
     */
    @TestVisible
    private static String deriveLightningPostMessageOriginFromHost(String host) {
        if (String.isBlank(host)) {
            return null;
        }
        String lower = host.toLowerCase();
        if (lower.endsWith('.sandbox.lightning.force.com') || lower.endsWith('.lightning.force.com')) {
            return 'https://' + host;
        }
        final String SANDBOX_MY = '.sandbox.my.salesforce.com';
        final String MY = '.my.salesforce.com';
        if (lower.endsWith(SANDBOX_MY)) {
            String stub = normalizeMyDomainStubForLightning(
                host.substring(0, host.length() - SANDBOX_MY.length())
            );
            return String.isNotBlank(stub) ? 'https://' + stub + '.sandbox.lightning.force.com' : null;
        }
        if (lower.endsWith(MY) && !lower.contains('.sandbox.my.salesforce')) {
            String stub = normalizeMyDomainStubForLightning(
                host.substring(0, host.length() - MY.length())
            );
            return String.isNotBlank(stub) ? 'https://' + stub + '.lightning.force.com' : null;
        }
        return null;
    }

    /** My Domain org stubs often include a --c suffix; LEX host uses the prefix without it. */
    @TestVisible
    private static String normalizeMyDomainStubForLightning(String stub) {
        if (String.isBlank(stub)) {
            return stub;
        }
        if (stub.endsWith('--c')) {
            return stub.substring(0, stub.length() - 3);
        }
        return stub;
    }

    private static String stripTrailingSlash(String u) {
        if (String.isBlank(u)) {
            return u;
        }
        String base = u;
        while (base.endsWith('/')) {
            base = base.substring(0, base.length() - 1);
        }
        return base;
    }

    private static String extractHost(String url) {
        if (String.isBlank(url)) {
            return '';
        }
        Integer schemeEnd = url.indexOf('://');
        if (schemeEnd < 0) {
            return url;
        }
        String rest = url.substring(schemeEnd + 3);
        Integer slash = rest.indexOf('/');
        if (slash >= 0) {
            rest = rest.substring(0, slash);
        }
        Integer q = rest.indexOf('?');
        if (q >= 0) {
            rest = rest.substring(0, q);
        }
        Integer hash = rest.indexOf('#');
        if (hash >= 0) {
            rest = rest.substring(0, hash);
        }
        return rest;
    }
}