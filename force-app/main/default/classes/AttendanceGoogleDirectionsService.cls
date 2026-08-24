/**
 * @description Calculates daily travelled distance via Google Directions API for attendance persistence.
 *              Route waypoint resolution mirrors User Tracking Dashboard data sources without
 *              invoking dashboard access-controlled APIs.
 */
public without sharing class AttendanceGoogleDirectionsService {

    private static final String DIRECTIONS_API_URL = 'https://maps.googleapis.com/maps/api/directions/json';
    private static final String RETAILER_RECORD_TYPE_NAME = 'Retailer';
    /** Mirrors dashboard LWC/VF routing constants (userTrackingDashboard + UserTrackingMapEmbed). */
    private static final Double CLUSTER_RADIUS_DEG_SQ = 0.000000285;
    private static final Double BASE_DEG_OFFSET = 0.000365;
    private static final Integer DIRECTIONS_MAX_INTERMEDIATE = 23;
    private static final Integer GOOGLE_DIRECTIONS_MAX_POSITIONS_SINGLE = 25;

    @TestVisible
    private static String testApiKeyOverride;

    /** When true in tests, {@link #testApiKeyOverride} is used even when blank. */
    @TestVisible
    private static Boolean testApiKeyOverrideConfigured = false;

    /**
     * @description Returns total driving distance in kilometres for the user's attendance day.
     * @param attendanceId Attendance__c Id (for logging; route is built for user + date).
     * @param userId Attendance__c.User__c
     * @param attendanceDate Attendance__c.Date_of_attendance__c
     * @return Distance in km rounded to 2 decimals, or null when the route or API call cannot produce a value.
     */
    public static Decimal calculateTotalDistanceKm(
        Id attendanceId,
        Id userId,
        Date attendanceDate
    ) {
        if (userId == null || attendanceDate == null) {
            return null;
        }

        try {
            List<LatLngPoint> waypoints = buildRouteWaypoints(userId, attendanceDate);
            if (waypoints == null || waypoints.size() < 2) {
                System.debug(
                    LoggingLevel.WARN,
                    'AttendanceGoogleDirectionsService.calculateTotalDistanceKm | attendanceId='
                        + attendanceId
                        + ' | insufficient waypoints: '
                        + (waypoints == null ? 0 : waypoints.size())
                );
                return null;
            }

            List<LatLngPoint> routingPath = preparePathForDirectionsRouting(waypoints);
            if (routingPath == null || routingPath.size() < 2) {
                return null;
            }

            Integer googleMeters = requestGoogleDirectionsDistanceMeters(routingPath);
            if (googleMeters != null && googleMeters > 0) {
                return Decimal.valueOf(googleMeters).divide(1000, 2, RoundingMode.HALF_UP);
            }
            if (googleMeters != null && googleMeters == 0) {
                return calculateHaversineRouteDistanceKm(waypoints);
            }

            return null;
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'AttendanceGoogleDirectionsService.calculateTotalDistanceKm | attendanceId='
                    + attendanceId
                    + ' | error='
                    + ex.getMessage()
                    + ' | stack='
                    + ex.getStackTraceString()
            );
            return null;
        }
    }

    @TestVisible
    private static List<LatLngPoint> buildRouteWaypoints(Id userId, Date attendanceDate) {
        List<RouteActivity> activities = new List<RouteActivity>();
        activities.addAll(loadAttendanceActivities(userId, attendanceDate));
        activities.addAll(loadVisitActivities(userId, attendanceDate));
        activities.addAll(loadNewOutletActivities(userId, attendanceDate));

        if (activities.isEmpty()) {
            return new List<LatLngPoint>();
        }

        activities.sort(new RouteActivitySortComparator());
        Datetime lifecycleStart = null;
        for (RouteActivity activity : activities) {
            if (activity != null && activity.isAttendanceCheckIn && activity.sortTime != null) {
                lifecycleStart = activity.sortTime;
                break;
            }
        }
        if (lifecycleStart == null) {
            return new List<LatLngPoint>();
        }

        List<LatLngPoint> waypoints = new List<LatLngPoint>();
        for (RouteActivity activity : activities) {
            if (activity == null || activity.sortTime == null || activity.sortTime < lifecycleStart) {
                continue;
            }
            if (activity.latitude == null || activity.longitude == null) {
                continue;
            }
            waypoints.add(new LatLngPoint(activity.latitude, activity.longitude));
        }
        return waypoints;
    }

    private static List<RouteActivity> loadAttendanceActivities(Id userId, Date attendanceDate) {
        List<RouteActivity> activities = new List<RouteActivity>();
        for (Attendance__c row : [
            SELECT
                Id,
                Location__Latitude__s,
                Location__Longitude__s,
                Attendance_Applied_on__c,
                Date_of_attendance__c,
                CreatedDate,
                EOD_Date_Time__c,
                EOD_Location__Latitude__s,
                EOD_Location__Longitude__s
            FROM Attendance__c
            WHERE User__c = :userId
                AND Date_of_attendance__c = :attendanceDate
            ORDER BY CreatedDate ASC
        ]) {
            RouteActivity checkIn = new RouteActivity();
            checkIn.isAttendanceCheckIn = true;
            checkIn.sortTime = resolveSortTime(
                row.Attendance_Applied_on__c != null
                    ? row.Attendance_Applied_on__c
                    : row.Date_of_attendance__c,
                row.CreatedDate
            );
            checkIn.latitude = row.Location__Latitude__s;
            checkIn.longitude = row.Location__Longitude__s;
            activities.add(checkIn);

            if (
                row.EOD_Date_Time__c != null
                && row.EOD_Location__Latitude__s != null
                && row.EOD_Location__Longitude__s != null
            ) {
                RouteActivity eod = new RouteActivity();
                eod.isAttendanceCheckIn = false;
                eod.sortTime = row.EOD_Date_Time__c;
                eod.latitude = row.EOD_Location__Latitude__s;
                eod.longitude = row.EOD_Location__Longitude__s;
                activities.add(eod);
            }
        }
        return activities;
    }

    private static List<RouteActivity> loadVisitActivities(Id userId, Date attendanceDate) {
        List<RouteActivity> activities = new List<RouteActivity>();
        for (Visit_Task__c row : [
            SELECT
                Checked_In_Time__c,
                Checked_In_Location__Latitude__s,
                Checked_In_Location__Longitude__s
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
                AND Task_Planned_Date__c = :attendanceDate
                AND Checked_In_Time__c != NULL
            ORDER BY Checked_In_Time__c ASC
        ]) {
            RouteActivity visit = new RouteActivity();
            visit.isAttendanceCheckIn = false;
            visit.sortTime = row.Checked_In_Time__c;
            visit.latitude = row.Checked_In_Location__Latitude__s;
            visit.longitude = row.Checked_In_Location__Longitude__s;
            activities.add(visit);
        }
        return activities;
    }

    private static List<RouteActivity> loadNewOutletActivities(Id userId, Date attendanceDate) {
        List<RouteActivity> activities = new List<RouteActivity>();
        DateTime dayStart = DateTime.newInstance(attendanceDate, Time.newInstance(0, 0, 0, 0));
        DateTime dayEndExclusive = dayStart.addDays(1);

        for (Account row : [
            SELECT
                CreatedDate,
                BillingLatitude,
                BillingLongitude,
                Latitude__c,
                Longitude__c
            FROM Account
            WHERE CreatedById = :userId
                AND CreatedDate >= :dayStart
                AND CreatedDate < :dayEndExclusive
                AND RecordType.Name = :RETAILER_RECORD_TYPE_NAME
            ORDER BY CreatedDate ASC
        ]) {
            LatLngPoint coordinates = resolveNewOutletMapCoordinates(row);
            if (coordinates == null) {
                continue;
            }
            RouteActivity outlet = new RouteActivity();
            outlet.isAttendanceCheckIn = false;
            outlet.sortTime = row.CreatedDate;
            outlet.latitude = coordinates.latitude;
            outlet.longitude = coordinates.longitude;
            activities.add(outlet);
        }
        return activities;
    }

    /**
     * @description Mirrors UserTrackingDashboardService.resolveNewOutletMapCoordinates:
     *              prefer Account Latitude__c / Longitude__c text fields; fallback to billing geocode.
     */
    @TestVisible
    private static LatLngPoint resolveNewOutletMapCoordinates(Account acc) {
        if (acc == null) {
            return null;
        }
        if (!String.isBlank(acc.Latitude__c) && !String.isBlank(acc.Longitude__c)) {
            try {
                return new LatLngPoint(
                    Decimal.valueOf(acc.Latitude__c.trim()),
                    Decimal.valueOf(acc.Longitude__c.trim())
                );
            } catch (Exception ex) {
                // fall through to billing geocode
            }
        }
        if (acc.BillingLatitude != null && acc.BillingLongitude != null) {
            return new LatLngPoint(acc.BillingLatitude, acc.BillingLongitude);
        }
        return null;
    }

    /**
     * @description Applies the same path pipeline as the User Tracking Dashboard map before Directions:
     *              LWC expandPathForRouting, then VF hangyoPathForRouting (coincident spiral offsets).
     */
    @TestVisible
    private static List<LatLngPoint> preparePathForDirectionsRouting(List<LatLngPoint> waypoints) {
        if (waypoints == null || waypoints.isEmpty()) {
            return waypoints;
        }
        return hangyoPathForRouting(expandPathForRouting(waypoints));
    }

    /** LWC expandPathForRouting — nudge consecutive near-duplicate GPS so every visit affects routing. */
    @TestVisible
    private static List<LatLngPoint> expandPathForRouting(List<LatLngPoint> path) {
        if (path == null || path.size() < 2) {
            return path == null ? new List<LatLngPoint>() : path;
        }

        List<LatLngPoint> out = new List<LatLngPoint>();
        out.add(path[0]);
        Integer slot = 0;

        for (Integer i = 1; i < path.size(); i++) {
            LatLngPoint last = out[out.size() - 1];
            LatLngPoint cur = path[i];
            if (
                CLUSTER_RADIUS_DEG_SQ >
                planarSqDeg(last.latitude, last.longitude, cur.latitude, cur.longitude)
            ) {
                slot++;
                out.add(offsetCoincidentSlot(last.latitude, last.longitude, slot));
            } else {
                slot = 0;
                out.add(cur);
            }
        }
        return out;
    }

    /** VF hangyoPathForRouting — spatial cluster spiral offsets on the expanded path. */
    @TestVisible
    private static List<LatLngPoint> hangyoPathForRouting(List<LatLngPoint> literals) {
        if (literals == null || literals.size() < 2) {
            return literals;
        }

        List<RoutingPathRow> prep = new List<RoutingPathRow>();
        for (LatLngPoint point : literals) {
            prep.add(new RoutingPathRow(point.latitude, point.longitude));
        }
        applyCoincidentMarkerDisplayPositions(prep);

        List<LatLngPoint> out = new List<LatLngPoint>();
        for (RoutingPathRow row : prep) {
            out.add(
                new LatLngPoint(
                    row.displayLatitude != null ? row.displayLatitude : row.latitude,
                    row.displayLongitude != null ? row.displayLongitude : row.longitude
                )
            );
        }
        return out;
    }

    private static void applyCoincidentMarkerDisplayPositions(List<RoutingPathRow> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }

        Integer rowCount = rows.size();
        List<Boolean> seen = new List<Boolean>();
        for (Integer i = 0; i < rowCount; i++) {
            seen.add(false);
        }

        for (Integer qi = 0; qi < rowCount; qi++) {
            if (seen[qi]) {
                continue;
            }

            List<Integer> stack = new List<Integer>{ qi };
            seen[qi] = true;
            List<Integer> groupIdx = new List<Integer>();

            while (!stack.isEmpty()) {
                Integer popIdx = stack.remove(stack.size() - 1);
                groupIdx.add(popIdx);
                RoutingPathRow anchorRow = rows[popIdx];

                for (Integer vi = 0; vi < rowCount; vi++) {
                    if (seen[vi]) {
                        continue;
                    }
                    RoutingPathRow candidate = rows[vi];
                    if (
                        withinClusterDistance(
                            anchorRow.latitude,
                            anchorRow.longitude,
                            candidate.latitude,
                            candidate.longitude
                        )
                    ) {
                        seen[vi] = true;
                        stack.add(vi);
                    }
                }
            }

            groupIdx.sort();
            Integer groupSize = groupIdx.size();
            Decimal anchorLat = rows[groupIdx[0]].latitude;
            Decimal anchorLng = rows[groupIdx[0]].longitude;

            for (Integer gx = 0; gx < groupIdx.size(); gx++) {
                LatLngPoint display = offsetCoincidentSlot(anchorLat, anchorLng, gx, groupSize);
                RoutingPathRow row = rows[groupIdx[gx]];
                row.displayLatitude = display.latitude;
                row.displayLongitude = display.longitude;
            }
        }
    }

    private static Boolean withinClusterDistance(
        Decimal lat1,
        Decimal lng1,
        Decimal lat2,
        Decimal lng2
    ) {
        return CLUSTER_RADIUS_DEG_SQ > planarSqDeg(lat1, lng1, lat2, lng2);
    }

    private static Double planarSqDeg(Decimal lat1, Decimal lng1, Decimal lat2, Decimal lng2) {
        Double dLat1 = lat1.doubleValue();
        Double dLng1 = lng1.doubleValue();
        Double dLat2 = lat2.doubleValue();
        Double dLng2 = lng2.doubleValue();
        Double avgLatRad = ((dLat1 + dLat2) / 2) * Math.PI / 180;
        Double dy = dLat1 - dLat2;
        Double scaledLngDelta = (dLng1 - dLng2) * Math.cos(avgLatRad);
        return dy * dy + scaledLngDelta * scaledLngDelta;
    }

    private static LatLngPoint offsetCoincidentSlot(Decimal lat, Decimal lng, Integer slot) {
        return offsetCoincidentSlot(lat, lng, slot, 2);
    }

    private static LatLngPoint offsetCoincidentSlot(
        Decimal lat,
        Decimal lng,
        Integer slotWithinGroup,
        Integer groupTotal
    ) {
        if (slotWithinGroup == null || slotWithinGroup == 0 || groupTotal == null || groupTotal <= 1) {
            return new LatLngPoint(lat, lng);
        }

        Double twoPi = Math.PI * 2;
        Integer ring = (slotWithinGroup - 1) / 8;
        Integer posInRing = Math.mod(slotWithinGroup - 1, 8);
        Double angle = twoPi * (posInRing + 1) / 8 + ring * 0.28;
        Double step = BASE_DEG_OFFSET * (ring + 1);
        Double latRad = lat.doubleValue() * Math.PI / 180;
        Double cosLat = Math.cos(latRad == 0 ? 0.000001 : latRad);

        return new LatLngPoint(
            Decimal.valueOf(lat.doubleValue() + step * Math.cos(angle)),
            Decimal.valueOf(lng.doubleValue() + (step * Math.sin(angle)) / cosLat)
        );
    }

    @TestVisible
    private static Integer requestGoogleDirectionsDistanceMeters(List<LatLngPoint> waypoints) {
        if (waypoints == null || waypoints.size() < 2) {
            return null;
        }

        if (waypoints.size() <= GOOGLE_DIRECTIONS_MAX_POSITIONS_SINGLE) {
            return requestSingleDirectionsLegMeters(waypoints);
        }

        Integer totalMeters = 0;
        Integer startIdx = 0;
        while (startIdx < waypoints.size() - 1) {
            Integer endIdx = startIdx + DIRECTIONS_MAX_INTERMEDIATE + 1;
            if (endIdx > waypoints.size() - 1) {
                endIdx = waypoints.size() - 1;
            }

            List<LatLngPoint> segment = new List<LatLngPoint>();
            for (Integer i = startIdx; i <= endIdx; i++) {
                segment.add(waypoints[i]);
            }

            Integer legMeters = requestSingleDirectionsLegMeters(segment);
            if (legMeters == null) {
                return null;
            }
            totalMeters += legMeters;

            if (endIdx >= waypoints.size() - 1) {
                break;
            }
            startIdx = endIdx;
        }
        return totalMeters;
    }

    private static Integer requestSingleDirectionsLegMeters(List<LatLngPoint> waypoints) {
        String apiKey = resolveGoogleMapsApiKey();
        if (String.isBlank(apiKey)) {
            System.debug(
                LoggingLevel.WARN,
                'AttendanceGoogleDirectionsService.requestSingleDirectionsLegMeters | Google_Maps_API_Key is blank.'
            );
            return null;
        }

        LatLngPoint origin = waypoints[0];
        LatLngPoint destination = waypoints[waypoints.size() - 1];

        String endpoint = DIRECTIONS_API_URL
            + '?origin='
            + formatCoordinate(origin.latitude, origin.longitude)
            + '&destination='
            + formatCoordinate(destination.latitude, destination.longitude)
            + '&mode=driving'
            + '&key='
            + EncodingUtil.urlEncode(apiKey.trim(), 'UTF-8');

        if (waypoints.size() > 2) {
            List<String> viaPoints = new List<String>();
            for (Integer i = 1; i < waypoints.size() - 1; i++) {
                LatLngPoint point = waypoints[i];
                viaPoints.add(formatCoordinate(point.latitude, point.longitude));
            }
            endpoint += '&waypoints=' + EncodingUtil.urlEncode(String.join(viaPoints, '|'), 'UTF-8');
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setTimeout(120000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            System.debug(
                LoggingLevel.WARN,
                'AttendanceGoogleDirectionsService.requestSingleDirectionsLegMeters | HTTP '
                    + response.getStatusCode()
                    + ' | '
                    + response.getStatus()
            );
            return null;
        }

        return parseDirectionsDistanceMeters(response.getBody());
    }

    @TestVisible
    private static Integer parseDirectionsDistanceMeters(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        if (payload == null || payload.get('status') != 'OK') {
            return null;
        }

        List<Object> routes = (List<Object>) payload.get('routes');
        if (routes == null || routes.isEmpty()) {
            return null;
        }

        Map<String, Object> route = (Map<String, Object>) routes[0];
        List<Object> legs = (List<Object>) route.get('legs');
        if (legs == null || legs.isEmpty()) {
            return null;
        }

        Integer totalMeters = 0;
        for (Object legObject : legs) {
            Map<String, Object> leg = (Map<String, Object>) legObject;
            Map<String, Object> distance = (Map<String, Object>) leg.get('distance');
            if (distance == null || !distance.containsKey('value')) {
                continue;
            }
            Object value = distance.get('value');
            if (value instanceof Integer) {
                totalMeters += (Integer) value;
            } else if (value instanceof Long) {
                totalMeters += Integer.valueOf((Long) value);
            } else if (value instanceof Decimal) {
                totalMeters += ((Decimal) value).intValue();
            }
        }

        return totalMeters;
    }

    /**
     * @description Sums straight-line Haversine distance across ordered waypoints (km, 2 dp).
     */
    @TestVisible
    private static Decimal calculateHaversineRouteDistanceKm(List<LatLngPoint> waypoints) {
        if (waypoints == null || waypoints.size() < 2) {
            return null;
        }

        Double totalMeters = 0;
        for (Integer i = 1; i < waypoints.size(); i++) {
            totalMeters += haversineMeters(waypoints[i - 1], waypoints[i]);
        }

        return Decimal.valueOf(totalMeters).divide(1000, 2, RoundingMode.HALF_UP);
    }

    private static Double haversineMeters(LatLngPoint fromPoint, LatLngPoint toPoint) {
        Double earthRadiusMeters = 6371000.0;
        Double lat1Rad = fromPoint.latitude.doubleValue() * Math.PI / 180;
        Double lat2Rad = toPoint.latitude.doubleValue() * Math.PI / 180;
        Double deltaLatRad =
            (toPoint.latitude.doubleValue() - fromPoint.latitude.doubleValue()) * Math.PI / 180;
        Double deltaLngRad =
            (toPoint.longitude.doubleValue() - fromPoint.longitude.doubleValue()) * Math.PI / 180;

        Double a =
            Math.sin(deltaLatRad / 2) * Math.sin(deltaLatRad / 2)
            + Math.cos(lat1Rad)
                * Math.cos(lat2Rad)
                * Math.sin(deltaLngRad / 2)
                * Math.sin(deltaLngRad / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return earthRadiusMeters * c;
    }

    private static Datetime resolveSortTime(Object appliedOn, Datetime createdDate) {
        if (appliedOn instanceof Datetime) {
            return (Datetime) appliedOn;
        }
        if (appliedOn instanceof Date) {
            return DateTime.newInstance((Date) appliedOn, Time.newInstance(0, 0, 0, 0));
        }
        return createdDate;
    }

    private static String formatCoordinate(Decimal latitude, Decimal longitude) {
        return String.valueOf(latitude) + ',' + String.valueOf(longitude);
    }

    @TestVisible
    private static String resolveGoogleMapsApiKey() {
        if (Test.isRunningTest() && testApiKeyOverrideConfigured == true) {
            return testApiKeyOverride == null ? '' : testApiKeyOverride.trim();
        }
        String apiKey = System.Label.Google_Maps_API_Key;
        return apiKey == null ? null : apiKey.trim();
    }

    private class RoutingPathRow {
        public Decimal latitude;
        public Decimal longitude;
        public Decimal displayLatitude;
        public Decimal displayLongitude;

        public RoutingPathRow(Decimal latitude, Decimal longitude) {
            this.latitude = latitude;
            this.longitude = longitude;
        }
    }

    @TestVisible
    private class LatLngPoint {
        public Decimal latitude;
        public Decimal longitude;

        public LatLngPoint(Decimal latitude, Decimal longitude) {
            this.latitude = latitude;
            this.longitude = longitude;
        }
    }

    private class RouteActivity {
        public Boolean isAttendanceCheckIn = false;
        public Datetime sortTime;
        public Decimal latitude;
        public Decimal longitude;
    }

    private class RouteActivitySortComparator implements System.Comparator<RouteActivity> {
        public Integer compare(RouteActivity left, RouteActivity right) {
            if (left == null && right == null) {
                return 0;
            }
            if (left == null) {
                return -1;
            }
            if (right == null) {
                return 1;
            }
            if (left.sortTime == null && right.sortTime == null) {
                return 0;
            }
            if (left.sortTime == null) {
                return -1;
            }
            if (right.sortTime == null) {
                return 1;
            }
            return left.sortTime < right.sortTime ? -1 : (left.sortTime > right.sortTime ? 1 : 0);
        }
    }
}