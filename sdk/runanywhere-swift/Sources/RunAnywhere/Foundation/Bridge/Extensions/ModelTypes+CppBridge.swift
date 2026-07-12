//
//  ModelTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  Conversion extensions for Swift model types to C++ model types.
//

import CRACommons

// MARK: - ModelCategory C++ Conversion

extension ModelCategory {
    /// Convert to C++ model category type.
    /// Delegates to commons' `rac_model_category_from_proto`.
    func toC() -> rac_model_category_t {
        var out: rac_model_category_t = RAC_MODEL_CATEGORY_UNKNOWN
        _ = rac_model_category_from_proto(Int32(self.rawValue), &out)
        return out
    }
}

// MARK: - ModelFormat C++ Conversion

extension ModelFormat {
    /// Convert to C++ model format type.
    /// Delegates to commons' `rac_model_format_from_proto`.
    func toC() -> rac_model_format_t {
        var out: rac_model_format_t = RAC_MODEL_FORMAT_UNKNOWN
        _ = rac_model_format_from_proto(Int32(self.rawValue), &out)
        return out
    }
}
