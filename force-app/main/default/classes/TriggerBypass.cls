public class TriggerBypass {
    public static Set<String> bypassed = new Set<String>();

    public static Boolean isBypassed(String name) {
        return bypassed.contains(name);
    }
}