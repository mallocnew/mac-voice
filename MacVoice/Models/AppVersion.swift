import Foundation

enum AppVersion {
    /// 对外版本号，对应 MARKETING_VERSION / CFBundleShortVersionString
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// 构建号，对应 CURRENT_PROJECT_VERSION / CFBundleVersion
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// 展示用：1.0.0 (1)
    static var display: String {
        "\(marketing) (\(build))"
    }

    /// 短展示：v1.0.0
    static var shortDisplay: String {
        "v\(marketing)"
    }
}
