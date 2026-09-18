/// Compile-time capabilities, independent of saved user preferences. The local
/// target cannot accidentally initialize CloudKit after importing old data.
public enum BuildFeatures {
    #if LOCAL_ONLY
    public static let cloudSync = false
    public static let shareExtension = false
    #else
    public static let cloudSync = true
    public static let shareExtension = true
    #endif
}
