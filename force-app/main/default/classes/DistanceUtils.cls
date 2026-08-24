public class DistanceUtils {
    public static Double calculateDistanceInMeters(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
            return 0.0; // safe fallback
        }
        
        Double r = 6371000; // Earth radius in meters
        Double dLat = degreesToRadians((lat2 - lat1).doubleValue());
        Double dLon = degreesToRadians((lon2 - lon1).doubleValue());
        Double rLat1 = degreesToRadians(lat1.doubleValue());
        Double rLat2 = degreesToRadians(lat2.doubleValue());
        
        Double a = Math.pow(Math.sin(dLat / 2), 2) +
                   Math.cos(rLat1) * Math.cos(rLat2) *
                   Math.pow(Math.sin(dLon / 2), 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        
        return r * c; // distance in meters
    }
    
    public static Double degreesToRadians(Double degrees) {
        return degrees * (Math.PI / 180);
    }
}