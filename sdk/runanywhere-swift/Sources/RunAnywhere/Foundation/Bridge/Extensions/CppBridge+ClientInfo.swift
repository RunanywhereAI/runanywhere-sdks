//
//  CppBridge+ClientInfo.swift
//  RunAnywhere SDK
//
//  Host application/client metadata for backend device and telemetry APIs.
//

import CRACommons
import Foundation

extension CppBridge {

    enum ClientInfo {
        static func register() {
            let bundle = Bundle.main
            let appIdentifier = bundle.bundleIdentifier ?? ""
            let appName =
                bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? ""
            let appVersion =
                bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? ""
            let appBuild =
                bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                ?? ""
            let locale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
            let timezone = TimeZone.current.identifier

            "swift".withCString { sdkBinding in
                appIdentifier.withCString { appIdentifierPtr in
                    appName.withCString { appNamePtr in
                        appVersion.withCString { appVersionPtr in
                            appBuild.withCString { appBuildPtr in
                                locale.withCString { localePtr in
                                    timezone.withCString { timezonePtr in
                                        var info = rac_client_info_t()
                                        info.sdk_binding = sdkBinding
                                        info.app_identifier = appIdentifierPtr
                                        info.app_name = appNamePtr
                                        info.app_version = appVersionPtr
                                        info.app_build = appBuildPtr
                                        info.locale = localePtr
                                        info.timezone = timezonePtr
                                        rac_sdk_set_client_info(&info)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
