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
        private struct Metadata {
            let sdkBinding: String
            let appIdentifier: String
            let appName: String
            let appVersion: String
            let appBuild: String
            let locale: String
            let timezone: String
        }

        private struct CStringPointers {
            let sdkBinding: UnsafePointer<CChar>
            let appIdentifier: UnsafePointer<CChar>
            let appName: UnsafePointer<CChar>
            let appVersion: UnsafePointer<CChar>
            let appBuild: UnsafePointer<CChar>
            let locale: UnsafePointer<CChar>
            let timezone: UnsafePointer<CChar>
        }

        static func register() {
            let bundle = Bundle.main
            let metadata = Metadata(
                sdkBinding: SDKConstants.binding,
                appIdentifier: bundle.bundleIdentifier ?? "",
                appName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? "",
                appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String
                    ?? "",
                appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ?? "",
                locale: Locale.current.identifier(.bcp47),
                timezone: TimeZone.current.identifier
            )

            withCStringPointers(metadata) { pointers in
                var info = rac_client_info_t()
                info.sdk_binding = pointers.sdkBinding
                info.app_identifier = pointers.appIdentifier
                info.app_name = pointers.appName
                info.app_version = pointers.appVersion
                info.app_build = pointers.appBuild
                info.locale = pointers.locale
                info.timezone = pointers.timezone
                rac_sdk_set_client_info(&info)
            }
        }

        private static func withCStringPointers<Result>(
            _ metadata: Metadata,
            _ body: (CStringPointers) -> Result
        ) -> Result {
            metadata.sdkBinding.withCString { sdkBinding in
                metadata.appIdentifier.withCString { appIdentifier in
                    metadata.appName.withCString { appName in
                        metadata.appVersion.withCString { appVersion in
                            metadata.appBuild.withCString { appBuild in
                                metadata.locale.withCString { locale in
                                    metadata.timezone.withCString { timezone in
                                        body(
                                            CStringPointers(
                                                sdkBinding: sdkBinding,
                                                appIdentifier: appIdentifier,
                                                appName: appName,
                                                appVersion: appVersion,
                                                appBuild: appBuild,
                                                locale: locale,
                                                timezone: timezone
                                            )
                                        )
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
