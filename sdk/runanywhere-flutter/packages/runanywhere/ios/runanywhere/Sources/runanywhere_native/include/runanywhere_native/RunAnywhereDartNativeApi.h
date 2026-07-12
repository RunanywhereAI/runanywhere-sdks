// SPDX-License-Identifier: Apache-2.0
//
// Minimal stable Dart native-port ABI used by the Flutter callback helpers.
// Keeping the subset here makes both CocoaPods and SwiftPM builds independent
// of a machine-specific Flutter SDK header path.

#ifndef RUNANYWHERE_DART_NATIVE_API_H_
#define RUNANYWHERE_DART_NATIVE_API_H_

#include <stdbool.h>
#include <stdint.h>

typedef int64_t Dart_Port;

typedef enum Dart_TypedData_Type {
    Dart_TypedData_kByteData = 0,
    Dart_TypedData_kInt8,
    Dart_TypedData_kUint8,
} Dart_TypedData_Type;

typedef enum Dart_CObject_Type {
    Dart_CObject_kNull = 0,
    Dart_CObject_kBool,
    Dart_CObject_kInt32,
    Dart_CObject_kInt64,
    Dart_CObject_kDouble,
    Dart_CObject_kString,
    Dart_CObject_kArray,
    Dart_CObject_kTypedData,
} Dart_CObject_Type;

typedef struct Dart_CObject Dart_CObject;

struct Dart_CObject {
    Dart_CObject_Type type;
    union {
        bool as_bool;
        int32_t as_int32;
        int64_t as_int64;
        double as_double;
        const char* as_string;
        struct {
            intptr_t length;
            Dart_CObject** values;
        } as_array;
        struct {
            Dart_TypedData_Type type;
            intptr_t length;
            const uint8_t* values;
        } as_typed_data;
    } value;
};

#endif  // RUNANYWHERE_DART_NATIVE_API_H_
