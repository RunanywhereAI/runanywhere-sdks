import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "google.protobuf";
/** The full set of known editions. */
export declare enum Edition {
    /** EDITION_UNKNOWN - A placeholder for an unknown edition value. */
    EDITION_UNKNOWN = 0,
    /**
     * EDITION_LEGACY - A placeholder edition for specifying default behaviors *before* a feature
     * was first introduced.  This is effectively an "infinite past".
     */
    EDITION_LEGACY = 900,
    /**
     * EDITION_PROTO2 - Legacy syntax "editions".  These pre-date editions, but behave much like
     * distinct editions.  These can't be used to specify the edition of proto
     * files, but feature definitions must supply proto2/proto3 defaults for
     * backwards compatibility.
     */
    EDITION_PROTO2 = 998,
    EDITION_PROTO3 = 999,
    /**
     * EDITION_2023 - Editions that have been released.  The specific values are arbitrary and
     * should not be depended on, but they will always be time-ordered for easy
     * comparison.
     */
    EDITION_2023 = 1000,
    EDITION_2024 = 1001,
    EDITION_2026 = 1002,
    /** EDITION_UNSTABLE - A placeholder edition for developing and testing unscheduled features. */
    EDITION_UNSTABLE = 9999,
    /**
     * EDITION_1_TEST_ONLY - Placeholder editions for testing feature resolution.  These should not be
     * used or relied on outside of tests.
     */
    EDITION_1_TEST_ONLY = 1,
    EDITION_2_TEST_ONLY = 2,
    EDITION_99997_TEST_ONLY = 99997,
    EDITION_99998_TEST_ONLY = 99998,
    EDITION_99999_TEST_ONLY = 99999,
    /**
     * EDITION_MAX - Placeholder for specifying unbounded edition support.  This should only
     * ever be used by plugins that can expect to never require any changes to
     * support a new edition.
     */
    EDITION_MAX = 2147483647,
    UNRECOGNIZED = -1
}
export declare function editionFromJSON(object: any): Edition;
export declare function editionToJSON(object: Edition): string;
/**
 * Describes the 'visibility' of a symbol with respect to the proto import
 * system. Symbols can only be imported when the visibility rules do not prevent
 * it (ex: local symbols cannot be imported).  Visibility modifiers can only set
 * on `message` and `enum` as they are the only types available to be referenced
 * from other files.
 */
export declare enum SymbolVisibility {
    VISIBILITY_UNSET = 0,
    VISIBILITY_LOCAL = 1,
    VISIBILITY_EXPORT = 2,
    UNRECOGNIZED = -1
}
export declare function symbolVisibilityFromJSON(object: any): SymbolVisibility;
export declare function symbolVisibilityToJSON(object: SymbolVisibility): string;
/**
 * The protocol compiler can output a FileDescriptorSet containing the .proto
 * files it parses.
 */
export interface FileDescriptorSet {
    file: FileDescriptorProto[];
}
/** Describes a complete .proto file. */
export interface FileDescriptorProto {
    /** file name, relative to root of source tree */
    name?: string | undefined;
    /** e.g. "foo", "foo.bar", etc. */
    package?: string | undefined;
    /** Names of files imported by this file. */
    dependency: string[];
    /** Indexes of the public imported files in the dependency list above. */
    publicDependency: number[];
    /**
     * Indexes of the weak imported files in the dependency list.
     * For Google-internal migration only. Do not use.
     */
    weakDependency: number[];
    /**
     * Names of files imported by this file purely for the purpose of providing
     * option extensions. These are excluded from the dependency list above.
     */
    optionDependency: string[];
    /** All top-level definitions in this file. */
    messageType: DescriptorProto[];
    enumType: EnumDescriptorProto[];
    service: ServiceDescriptorProto[];
    extension: FieldDescriptorProto[];
    options?: FileOptions | undefined;
    /**
     * This field contains optional information about the original source code.
     * You may safely remove this entire field without harming runtime
     * functionality of the descriptors -- the information is needed only by
     * development tools.
     */
    sourceCodeInfo?: SourceCodeInfo | undefined;
    /**
     * The syntax of the proto file.
     * The supported values are "proto2", "proto3", and "editions".
     *
     * If `edition` is present, this value must be "editions".
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    syntax?: string | undefined;
    /**
     * The edition of the proto file.
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    edition?: Edition | undefined;
}
/** Describes a message type. */
export interface DescriptorProto {
    name?: string | undefined;
    field: FieldDescriptorProto[];
    extension: FieldDescriptorProto[];
    nestedType: DescriptorProto[];
    enumType: EnumDescriptorProto[];
    extensionRange: DescriptorProto_ExtensionRange[];
    oneofDecl: OneofDescriptorProto[];
    options?: MessageOptions | undefined;
    reservedRange: DescriptorProto_ReservedRange[];
    /**
     * Reserved field names, which may not be used by fields in the same message.
     * A given name may only be reserved once.
     */
    reservedName: string[];
    /** Support for `export` and `local` keywords on enums. */
    visibility?: SymbolVisibility | undefined;
}
export interface DescriptorProto_ExtensionRange {
    /** Inclusive. */
    start?: number | undefined;
    /** Exclusive. */
    end?: number | undefined;
    options?: ExtensionRangeOptions | undefined;
}
/**
 * Range of reserved tag numbers. Reserved tag numbers may not be used by
 * fields or extension ranges in the same message. Reserved ranges may
 * not overlap.
 */
export interface DescriptorProto_ReservedRange {
    /** Inclusive. */
    start?: number | undefined;
    /** Exclusive. */
    end?: number | undefined;
}
export interface ExtensionRangeOptions {
    /** The parser stores options it doesn't recognize here. See above. */
    uninterpretedOption: UninterpretedOption[];
    /**
     * For external users: DO NOT USE. We are in the process of open sourcing
     * extension declaration and executing internal cleanups before it can be
     * used externally.
     */
    declaration: ExtensionRangeOptions_Declaration[];
    /** Any features defined in the specific edition. */
    features?: FeatureSet | undefined;
    /**
     * The verification state of the range.
     * TODO: flip the default to DECLARATION once all empty ranges
     * are marked as UNVERIFIED.
     */
    verification?: ExtensionRangeOptions_VerificationState | undefined;
}
/** The verification state of the extension range. */
export declare enum ExtensionRangeOptions_VerificationState {
    /** DECLARATION - All the extensions of the range must be declared. */
    DECLARATION = 0,
    UNVERIFIED = 1,
    UNRECOGNIZED = -1
}
export declare function extensionRangeOptions_VerificationStateFromJSON(object: any): ExtensionRangeOptions_VerificationState;
export declare function extensionRangeOptions_VerificationStateToJSON(object: ExtensionRangeOptions_VerificationState): string;
export interface ExtensionRangeOptions_Declaration {
    /** The extension number declared within the extension range. */
    number?: number | undefined;
    /**
     * The fully-qualified name of the extension field. There must be a leading
     * dot in front of the full name.
     */
    fullName?: string | undefined;
    /**
     * The fully-qualified type name of the extension field. Unlike
     * Metadata.type, Declaration.type must have a leading dot for messages
     * and enums.
     */
    type?: string | undefined;
    /**
     * If true, indicates that the number is reserved in the extension range,
     * and any extension field with the number will fail to compile. Set this
     * when a declared extension field is deleted.
     */
    reserved?: boolean | undefined;
    /**
     * If true, indicates that the extension must be defined as repeated.
     * Otherwise the extension must be defined as optional.
     */
    repeated?: boolean | undefined;
}
/** Describes a field within a message. */
export interface FieldDescriptorProto {
    name?: string | undefined;
    number?: number | undefined;
    label?: FieldDescriptorProto_Label | undefined;
    /**
     * If type_name is set, this need not be set.  If both this and type_name
     * are set, this must be one of TYPE_ENUM, TYPE_MESSAGE or TYPE_GROUP.
     */
    type?: FieldDescriptorProto_Type | undefined;
    /**
     * For message and enum types, this is the name of the type.  If the name
     * starts with a '.', it is fully-qualified.  Otherwise, C++-like scoping
     * rules are used to find the type (i.e. first the nested types within this
     * message are searched, then within the parent, on up to the root
     * namespace).
     */
    typeName?: string | undefined;
    /**
     * For extensions, this is the name of the type being extended.  It is
     * resolved in the same manner as type_name.
     */
    extendee?: string | undefined;
    /**
     * For numeric types, contains the original text representation of the value.
     * For booleans, "true" or "false".
     * For strings, contains the default text contents (not escaped in any way).
     * For bytes, contains the C escaped value.  All bytes >= 128 are escaped.
     */
    defaultValue?: string | undefined;
    /**
     * If set, gives the index of a oneof in the containing type's oneof_decl
     * list.  This field is a member of that oneof.
     */
    oneofIndex?: number | undefined;
    /**
     * JSON name of this field. The value is set by protocol compiler. If the
     * user has set a "json_name" option on this field, that option's value
     * will be used. Otherwise, it's deduced from the field's name by converting
     * it to camelCase.
     */
    jsonName?: string | undefined;
    options?: FieldOptions | undefined;
    /**
     * If true, this is a proto3 "optional". When a proto3 field is optional, it
     * tracks presence regardless of field type.
     *
     * When proto3_optional is true, this field must belong to a oneof to signal
     * to old proto3 clients that presence is tracked for this field. This oneof
     * is known as a "synthetic" oneof, and this field must be its sole member
     * (each proto3 optional field gets its own synthetic oneof). Synthetic oneofs
     * exist in the descriptor only, and do not generate any API. Synthetic oneofs
     * must be ordered after all "real" oneofs.
     *
     * For message fields, proto3_optional doesn't create any semantic change,
     * since non-repeated message fields always track presence. However it still
     * indicates the semantic detail of whether the user wrote "optional" or not.
     * This can be useful for round-tripping the .proto file. For consistency we
     * give message fields a synthetic oneof also, even though it is not required
     * to track presence. This is especially important because the parser can't
     * tell if a field is a message or an enum, so it must always create a
     * synthetic oneof.
     *
     * Proto2 optional fields do not set this flag, because they already indicate
     * optional with `LABEL_OPTIONAL`.
     */
    proto3Optional?: boolean | undefined;
}
export declare enum FieldDescriptorProto_Type {
    /**
     * TYPE_DOUBLE - 0 is reserved for errors.
     * Order is weird for historical reasons.
     */
    TYPE_DOUBLE = 1,
    TYPE_FLOAT = 2,
    /**
     * TYPE_INT64 - Not ZigZag encoded.  Negative numbers take 10 bytes.  Use TYPE_SINT64 if
     * negative values are likely.
     */
    TYPE_INT64 = 3,
    TYPE_UINT64 = 4,
    /**
     * TYPE_INT32 - Not ZigZag encoded.  Negative numbers take 10 bytes.  Use TYPE_SINT32 if
     * negative values are likely.
     */
    TYPE_INT32 = 5,
    TYPE_FIXED64 = 6,
    TYPE_FIXED32 = 7,
    TYPE_BOOL = 8,
    TYPE_STRING = 9,
    /**
     * TYPE_GROUP - Tag-delimited aggregate.
     * Group type is deprecated and not supported after google.protobuf. However, Proto3
     * implementations should still be able to parse the group wire format and
     * treat group fields as unknown fields.  In Editions, the group wire format
     * can be enabled via the `message_encoding` feature.
     */
    TYPE_GROUP = 10,
    /** TYPE_MESSAGE - Length-delimited aggregate. */
    TYPE_MESSAGE = 11,
    /** TYPE_BYTES - New in version 2. */
    TYPE_BYTES = 12,
    TYPE_UINT32 = 13,
    TYPE_ENUM = 14,
    TYPE_SFIXED32 = 15,
    TYPE_SFIXED64 = 16,
    /** TYPE_SINT32 - Uses ZigZag encoding. */
    TYPE_SINT32 = 17,
    /** TYPE_SINT64 - Uses ZigZag encoding. */
    TYPE_SINT64 = 18,
    UNRECOGNIZED = -1
}
export declare function fieldDescriptorProto_TypeFromJSON(object: any): FieldDescriptorProto_Type;
export declare function fieldDescriptorProto_TypeToJSON(object: FieldDescriptorProto_Type): string;
export declare enum FieldDescriptorProto_Label {
    /** LABEL_OPTIONAL - 0 is reserved for errors */
    LABEL_OPTIONAL = 1,
    LABEL_REPEATED = 3,
    /**
     * LABEL_REQUIRED - The required label is only allowed in google.protobuf.  In proto3 and Editions
     * it's explicitly prohibited.  In Editions, the `field_presence` feature
     * can be used to get this behavior.
     */
    LABEL_REQUIRED = 2,
    UNRECOGNIZED = -1
}
export declare function fieldDescriptorProto_LabelFromJSON(object: any): FieldDescriptorProto_Label;
export declare function fieldDescriptorProto_LabelToJSON(object: FieldDescriptorProto_Label): string;
/** Describes a oneof. */
export interface OneofDescriptorProto {
    name?: string | undefined;
    options?: OneofOptions | undefined;
}
/** Describes an enum type. */
export interface EnumDescriptorProto {
    name?: string | undefined;
    value: EnumValueDescriptorProto[];
    options?: EnumOptions | undefined;
    /**
     * Range of reserved numeric values. Reserved numeric values may not be used
     * by enum values in the same enum declaration. Reserved ranges may not
     * overlap.
     */
    reservedRange: EnumDescriptorProto_EnumReservedRange[];
    /**
     * Reserved enum value names, which may not be reused. A given name may only
     * be reserved once.
     */
    reservedName: string[];
    /** Support for `export` and `local` keywords on enums. */
    visibility?: SymbolVisibility | undefined;
}
/**
 * Range of reserved numeric values. Reserved values may not be used by
 * entries in the same enum. Reserved ranges may not overlap.
 *
 * Note that this is distinct from DescriptorProto.ReservedRange in that it
 * is inclusive such that it can appropriately represent the entire int32
 * domain.
 */
export interface EnumDescriptorProto_EnumReservedRange {
    /** Inclusive. */
    start?: number | undefined;
    /** Inclusive. */
    end?: number | undefined;
}
/** Describes a value within an enum. */
export interface EnumValueDescriptorProto {
    name?: string | undefined;
    number?: number | undefined;
    options?: EnumValueOptions | undefined;
}
/** Describes a service. */
export interface ServiceDescriptorProto {
    name?: string | undefined;
    method: MethodDescriptorProto[];
    options?: ServiceOptions | undefined;
}
/** Describes a method of a service. */
export interface MethodDescriptorProto {
    name?: string | undefined;
    /**
     * Input and output type names.  These are resolved in the same way as
     * FieldDescriptorProto.type_name, but must refer to a message type.
     */
    inputType?: string | undefined;
    outputType?: string | undefined;
    options?: MethodOptions | undefined;
    /** Identifies if client streams multiple client messages */
    clientStreaming?: boolean | undefined;
    /** Identifies if server streams multiple server messages */
    serverStreaming?: boolean | undefined;
}
export interface FileOptions {
    /**
     * Sets the Java package where classes generated from this .proto will be
     * placed.  By default, the proto package is used, but this is often
     * inappropriate because proto packages do not normally start with backwards
     * domain names.
     */
    javaPackage?: string | undefined;
    /**
     * Controls the name of the wrapper Java class generated for the .proto file.
     * That class will always contain the .proto file's getDescriptor() method as
     * well as any top-level extensions defined in the .proto file.
     * If java_multiple_files is disabled, then all the other classes from the
     * .proto file will be nested inside the single wrapper outer class.
     */
    javaOuterClassname?: string | undefined;
    /**
     * If enabled, then the Java code generator will generate a separate .java
     * file for each top-level message, enum, and service defined in the .proto
     * file.  Thus, these types will *not* be nested inside the wrapper class
     * named by java_outer_classname.  However, the wrapper class will still be
     * generated to contain the file's getDescriptor() method as well as any
     * top-level extensions defined in the file.
     */
    javaMultipleFiles?: boolean | undefined;
    /**
     * This option does nothing.
     *
     * @deprecated
     */
    javaGenerateEqualsAndHash?: boolean | undefined;
    /**
     * A proto2 file can set this to true to opt in to UTF-8 checking for Java,
     * which will throw an exception if invalid UTF-8 is parsed from the wire or
     * assigned to a string field.
     *
     * TODO: clarify exactly what kinds of field types this option
     * applies to, and update these docs accordingly.
     *
     * Proto3 files already perform these checks. Setting the option explicitly to
     * false has no effect: it cannot be used to opt proto3 files out of UTF-8
     * checks.
     */
    javaStringCheckUtf8?: boolean | undefined;
    optimizeFor?: FileOptions_OptimizeMode | undefined;
    /**
     * Sets the Go package where structs generated from this .proto will be
     * placed. If omitted, the Go package will be derived from the following:
     *   - The basename of the package import path, if provided.
     *   - Otherwise, the package statement in the .proto file, if present.
     *   - Otherwise, the basename of the .proto file, without extension.
     */
    goPackage?: string | undefined;
    /**
     * Should generic services be generated in each language?  "Generic" services
     * are not specific to any particular RPC system.  They are generated by the
     * main code generators in each language (without additional plugins).
     * Generic services were the only kind of service generation supported by
     * early versions of google.protobuf.
     *
     * Generic services are now considered deprecated in favor of using plugins
     * that generate code specific to your particular RPC system.  Therefore,
     * these default to false.  Old code which depends on generic services should
     * explicitly set them to true.
     */
    ccGenericServices?: boolean | undefined;
    javaGenericServices?: boolean | undefined;
    pyGenericServices?: boolean | undefined;
    /**
     * Is this file deprecated?
     * Depending on the target platform, this can emit Deprecated annotations
     * for everything in the file, or it will be completely ignored; in the very
     * least, this is a formalization for deprecating files.
     */
    deprecated?: boolean | undefined;
    /**
     * Enables the use of arenas for the proto messages in this file. This applies
     * only to generated classes for C++.
     */
    ccEnableArenas?: boolean | undefined;
    /**
     * Sets the objective c class prefix which is prepended to all objective c
     * generated classes from this .proto. There is no default.
     */
    objcClassPrefix?: string | undefined;
    /** Namespace for generated classes; defaults to the package. */
    csharpNamespace?: string | undefined;
    /**
     * By default Swift generators will take the proto package and CamelCase it
     * replacing '.' with underscore and use that to prefix the types/symbols
     * defined. When this options is provided, they will use this value instead
     * to prefix the types/symbols defined.
     */
    swiftPrefix?: string | undefined;
    /**
     * Sets the php class prefix which is prepended to all php generated classes
     * from this .proto. Default is empty.
     */
    phpClassPrefix?: string | undefined;
    /**
     * Use this option to change the namespace of php generated classes. Default
     * is empty. When this option is empty, the package name will be used for
     * determining the namespace.
     */
    phpNamespace?: string | undefined;
    /**
     * Use this option to change the namespace of php generated metadata classes.
     * Default is empty. When this option is empty, the proto file name will be
     * used for determining the namespace.
     */
    phpMetadataNamespace?: string | undefined;
    /**
     * Use this option to change the package of ruby generated classes. Default
     * is empty. When this option is not set, the package name will be used for
     * determining the ruby package.
     */
    rubyPackage?: string | undefined;
    /**
     * Any features defined in the specific edition.
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    features?: FeatureSet | undefined;
    /**
     * The parser stores options it doesn't recognize here.
     * See the documentation for the "Options" section above.
     */
    uninterpretedOption: UninterpretedOption[];
}
/** Generated classes can be optimized for speed or code size. */
export declare enum FileOptions_OptimizeMode {
    /** SPEED - Generate complete code for parsing, serialization, */
    SPEED = 1,
    /** CODE_SIZE - etc. */
    CODE_SIZE = 2,
    /** LITE_RUNTIME - Generate code using MessageLite and the lite runtime. */
    LITE_RUNTIME = 3,
    UNRECOGNIZED = -1
}
export declare function fileOptions_OptimizeModeFromJSON(object: any): FileOptions_OptimizeMode;
export declare function fileOptions_OptimizeModeToJSON(object: FileOptions_OptimizeMode): string;
export interface MessageOptions {
    /**
     * Set true to use the old proto1 MessageSet wire format for extensions.
     * This is provided for backwards-compatibility with the MessageSet wire
     * format.  You should not use this for any other reason:  It's less
     * efficient, has fewer features, and is more complicated.
     *
     * The message must be defined exactly as follows:
     *   message Foo {
     *     option message_set_wire_format = true;
     *     extensions 4 to max;
     *   }
     * Note that the message cannot have any defined fields; MessageSets only
     * have extensions.
     *
     * All extensions of your type must be singular messages; e.g. they cannot
     * be int32s, enums, or repeated messages.
     *
     * Because this is an option, the above two restrictions are not enforced by
     * the protocol compiler.
     */
    messageSetWireFormat?: boolean | undefined;
    /**
     * Disables the generation of the standard "descriptor()" accessor, which can
     * conflict with a field of the same name.  This is meant to make migration
     * from proto1 easier; new code should avoid fields named "descriptor".
     */
    noStandardDescriptorAccessor?: boolean | undefined;
    /**
     * Is this message deprecated?
     * Depending on the target platform, this can emit Deprecated annotations
     * for the message, or it will be completely ignored; in the very least,
     * this is a formalization for deprecating messages.
     */
    deprecated?: boolean | undefined;
    /**
     * Whether the message is an automatically generated map entry type for the
     * maps field.
     *
     * For maps fields:
     *     map<KeyType, ValueType> map_field = 1;
     * The parsed descriptor looks like:
     *     message MapFieldEntry {
     *         option map_entry = true;
     *         optional KeyType key = 1;
     *         optional ValueType value = 2;
     *     }
     *     repeated MapFieldEntry map_field = 1;
     *
     * Implementations may choose not to generate the map_entry=true message, but
     * use a native map in the target language to hold the keys and values.
     * The reflection APIs in such implementations still need to work as
     * if the field is a repeated message field.
     *
     * NOTE: Do not set the option in .proto files. Always use the maps syntax
     * instead. The option should only be implicitly set by the proto compiler
     * parser.
     */
    mapEntry?: boolean | undefined;
    /**
     * Enable the legacy handling of JSON field name conflicts.  This lowercases
     * and strips underscored from the fields before comparison in proto3 only.
     * The new behavior takes `json_name` into account and applies to proto2 as
     * well.
     *
     * This should only be used as a temporary measure against broken builds due
     * to the change in behavior for JSON field name conflicts.
     *
     * TODO This is legacy behavior we plan to remove once downstream
     * teams have had time to migrate.
     *
     * @deprecated
     */
    deprecatedLegacyJsonFieldConflicts?: boolean | undefined;
    /**
     * Any features defined in the specific edition.
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    features?: FeatureSet | undefined;
    /** The parser stores options it doesn't recognize here. See above. */
    uninterpretedOption: UninterpretedOption[];
}
export interface FieldOptions {
    /**
     * NOTE: ctype is deprecated. Use `features.(pb.cpp).string_type` instead.
     * The ctype option instructs the C++ code generator to use a different
     * representation of the field than it normally would.  See the specific
     * options below.  This option is only implemented to support use of
     * [ctype=CORD] and [ctype=STRING] (the default) on non-repeated fields of
     * type "bytes" in the open source release.
     * TODO: make ctype actually deprecated.
     */
    ctype?: FieldOptions_CType | undefined;
    /**
     * The packed option can be enabled for repeated primitive fields to enable
     * a more efficient representation on the wire. Rather than repeatedly
     * writing the tag and type for each element, the entire array is encoded as
     * a single length-delimited blob. In proto3, only explicit setting it to
     * false will avoid using packed encoding.  This option is prohibited in
     * Editions, but the `repeated_field_encoding` feature can be used to control
     * the behavior.
     */
    packed?: boolean | undefined;
    /**
     * The jstype option determines the JavaScript type used for values of the
     * field.  The option is permitted only for 64 bit integral and fixed types
     * (int64, uint64, sint64, fixed64, sfixed64).  A field with jstype JS_STRING
     * is represented as JavaScript string, which avoids loss of precision that
     * can happen when a large value is converted to a floating point JavaScript.
     * Specifying JS_NUMBER for the jstype causes the generated JavaScript code to
     * use the JavaScript "number" type.  The behavior of the default option
     * JS_NORMAL is implementation dependent.
     *
     * This option is an enum to permit additional types to be added, e.g.
     * goog.math.Integer.
     */
    jstype?: FieldOptions_JSType | undefined;
    /**
     * Should this field be parsed lazily?  Lazy applies only to message-type
     * fields.  It means that when the outer message is initially parsed, the
     * inner message's contents will not be parsed but instead stored in encoded
     * form.  The inner message will actually be parsed when it is first accessed.
     *
     * This is only a hint.  Implementations are free to choose whether to use
     * eager or lazy parsing regardless of the value of this option.  However,
     * setting this option true suggests that the protocol author believes that
     * using lazy parsing on this field is worth the additional bookkeeping
     * overhead typically needed to implement it.
     *
     * This option does not affect the public interface of any generated code;
     * all method signatures remain the same.  Furthermore, thread-safety of the
     * interface is not affected by this option; const methods remain safe to
     * call from multiple threads concurrently, while non-const methods continue
     * to require exclusive access.
     *
     * Note that lazy message fields are still eagerly verified to check
     * ill-formed wireformat or missing required fields. Calling IsInitialized()
     * on the outer message would fail if the inner message has missing required
     * fields. Failed verification would result in parsing failure (except when
     * uninitialized messages are acceptable).
     */
    lazy?: boolean | undefined;
    /**
     * unverified_lazy does no correctness checks on the byte stream. This should
     * only be used where lazy with verification is prohibitive for performance
     * reasons.
     */
    unverifiedLazy?: boolean | undefined;
    /**
     * Is this field deprecated?
     * Depending on the target platform, this can emit Deprecated annotations
     * for accessors, or it will be completely ignored; in the very least, this
     * is a formalization for deprecating fields.
     */
    deprecated?: boolean | undefined;
    /**
     * DEPRECATED. DO NOT USE!
     * For Google-internal migration only. Do not use.
     *
     * @deprecated
     */
    weak?: boolean | undefined;
    /**
     * Indicate that the field value should not be printed out when using debug
     * formats, e.g. when the field contains sensitive credentials.
     */
    debugRedact?: boolean | undefined;
    retention?: FieldOptions_OptionRetention | undefined;
    targets: FieldOptions_OptionTargetType[];
    editionDefaults: FieldOptions_EditionDefault[];
    /**
     * Any features defined in the specific edition.
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    features?: FeatureSet | undefined;
    featureSupport?: FieldOptions_FeatureSupport | undefined;
    /** The parser stores options it doesn't recognize here. See above. */
    uninterpretedOption: UninterpretedOption[];
}
export declare enum FieldOptions_CType {
    /** STRING - Default mode. */
    STRING = 0,
    /**
     * CORD - The option [ctype=CORD] may be applied to a non-repeated field of type
     * "bytes". It indicates that in C++, the data should be stored in a Cord
     * instead of a string.  For very large strings, this may reduce memory
     * fragmentation. It may also allow better performance when parsing from a
     * Cord, or when parsing with aliasing enabled, as the parsed Cord may then
     * alias the original buffer.
     */
    CORD = 1,
    STRING_PIECE = 2,
    UNRECOGNIZED = -1
}
export declare function fieldOptions_CTypeFromJSON(object: any): FieldOptions_CType;
export declare function fieldOptions_CTypeToJSON(object: FieldOptions_CType): string;
export declare enum FieldOptions_JSType {
    /** JS_NORMAL - Use the default type. */
    JS_NORMAL = 0,
    /** JS_STRING - Use JavaScript strings. */
    JS_STRING = 1,
    /** JS_NUMBER - Use JavaScript numbers. */
    JS_NUMBER = 2,
    UNRECOGNIZED = -1
}
export declare function fieldOptions_JSTypeFromJSON(object: any): FieldOptions_JSType;
export declare function fieldOptions_JSTypeToJSON(object: FieldOptions_JSType): string;
/** If set to RETENTION_SOURCE, the option will be omitted from the binary. */
export declare enum FieldOptions_OptionRetention {
    RETENTION_UNKNOWN = 0,
    RETENTION_RUNTIME = 1,
    RETENTION_SOURCE = 2,
    UNRECOGNIZED = -1
}
export declare function fieldOptions_OptionRetentionFromJSON(object: any): FieldOptions_OptionRetention;
export declare function fieldOptions_OptionRetentionToJSON(object: FieldOptions_OptionRetention): string;
/**
 * This indicates the types of entities that the field may apply to when used
 * as an option. If it is unset, then the field may be freely used as an
 * option on any kind of entity.
 */
export declare enum FieldOptions_OptionTargetType {
    TARGET_TYPE_UNKNOWN = 0,
    TARGET_TYPE_FILE = 1,
    TARGET_TYPE_EXTENSION_RANGE = 2,
    TARGET_TYPE_MESSAGE = 3,
    TARGET_TYPE_FIELD = 4,
    TARGET_TYPE_ONEOF = 5,
    TARGET_TYPE_ENUM = 6,
    TARGET_TYPE_ENUM_ENTRY = 7,
    TARGET_TYPE_SERVICE = 8,
    TARGET_TYPE_METHOD = 9,
    UNRECOGNIZED = -1
}
export declare function fieldOptions_OptionTargetTypeFromJSON(object: any): FieldOptions_OptionTargetType;
export declare function fieldOptions_OptionTargetTypeToJSON(object: FieldOptions_OptionTargetType): string;
export interface FieldOptions_EditionDefault {
    edition?: Edition | undefined;
    /** Textproto value. */
    value?: string | undefined;
}
/** Information about the support window of a feature. */
export interface FieldOptions_FeatureSupport {
    /**
     * The edition that this feature was first available in.  In editions
     * earlier than this one, the default assigned to EDITION_LEGACY will be
     * used, and proto files will not be able to override it.
     */
    editionIntroduced?: Edition | undefined;
    /**
     * The edition this feature becomes deprecated in.  Using this after this
     * edition may trigger warnings.
     */
    editionDeprecated?: Edition | undefined;
    /**
     * The deprecation warning text if this feature is used after the edition it
     * was marked deprecated in.
     */
    deprecationWarning?: string | undefined;
    /**
     * The edition this feature is no longer available in.  In editions after
     * this one, the last default assigned will be used, and proto files will
     * not be able to override it.
     */
    editionRemoved?: Edition | undefined;
    /**
     * The removal error text if this feature is used after the edition it was
     * removed in.
     */
    removalError?: string | undefined;
}
export interface OneofOptions {
    /**
     * Any features defined in the specific edition.
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    features?: FeatureSet | undefined;
    /** The parser stores options it doesn't recognize here. See above. */
    uninterpretedOption: UninterpretedOption[];
}
export interface EnumOptions {
    /**
     * Set this option to true to allow mapping different tag names to the same
     * value.
     */
    allowAlias?: boolean | undefined;
    /**
     * Is this enum deprecated?
     * Depending on the target platform, this can emit Deprecated annotations
     * for the enum, or it will be completely ignored; in the very least, this
     * is a formalization for deprecating enums.
     */
    deprecated?: boolean | undefined;
    /**
     * Enable the legacy handling of JSON field name conflicts.  This lowercases
     * and strips underscored from the fields before comparison in proto3 only.
     * The new behavior takes `json_name` into account and applies to proto2 as
     * well.
     * TODO Remove this legacy behavior once downstream teams have
     * had time to migrate.
     *
     * @deprecated
     */
    deprecatedLegacyJsonFieldConflicts?: boolean | undefined;
    /**
     * Any features defined in the specific edition.
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    features?: FeatureSet | undefined;
    /** The parser stores options it doesn't recognize here. See above. */
    uninterpretedOption: UninterpretedOption[];
}
export interface EnumValueOptions {
    /**
     * Is this enum value deprecated?
     * Depending on the target platform, this can emit Deprecated annotations
     * for the enum value, or it will be completely ignored; in the very least,
     * this is a formalization for deprecating enum values.
     */
    deprecated?: boolean | undefined;
    /**
     * Any features defined in the specific edition.
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    features?: FeatureSet | undefined;
    /**
     * Indicate that fields annotated with this enum value should not be printed
     * out when using debug formats, e.g. when the field contains sensitive
     * credentials.
     */
    debugRedact?: boolean | undefined;
    /** Information about the support window of a feature value. */
    featureSupport?: FieldOptions_FeatureSupport | undefined;
    /** The parser stores options it doesn't recognize here. See above. */
    uninterpretedOption: UninterpretedOption[];
}
export interface ServiceOptions {
    /**
     * Any features defined in the specific edition.
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    features?: FeatureSet | undefined;
    /**
     * Is this service deprecated?
     * Depending on the target platform, this can emit Deprecated annotations
     * for the service, or it will be completely ignored; in the very least,
     * this is a formalization for deprecating services.
     */
    deprecated?: boolean | undefined;
    /** The parser stores options it doesn't recognize here. See above. */
    uninterpretedOption: UninterpretedOption[];
}
export interface MethodOptions {
    /**
     * Is this method deprecated?
     * Depending on the target platform, this can emit Deprecated annotations
     * for the method, or it will be completely ignored; in the very least,
     * this is a formalization for deprecating methods.
     */
    deprecated?: boolean | undefined;
    idempotencyLevel?: MethodOptions_IdempotencyLevel | undefined;
    /**
     * Any features defined in the specific edition.
     * WARNING: This field should only be used by protobuf plugins or special
     * cases like the proto compiler. Other uses are discouraged and
     * developers should rely on the protoreflect APIs for their client language.
     */
    features?: FeatureSet | undefined;
    /** The parser stores options it doesn't recognize here. See above. */
    uninterpretedOption: UninterpretedOption[];
}
/**
 * Is this method side-effect-free (or safe in HTTP parlance), or idempotent,
 * or neither? HTTP based RPC implementation may choose GET verb for safe
 * methods, and PUT verb for idempotent methods instead of the default POST.
 */
export declare enum MethodOptions_IdempotencyLevel {
    IDEMPOTENCY_UNKNOWN = 0,
    /** NO_SIDE_EFFECTS - implies idempotent */
    NO_SIDE_EFFECTS = 1,
    /** IDEMPOTENT - idempotent, but may have side effects */
    IDEMPOTENT = 2,
    UNRECOGNIZED = -1
}
export declare function methodOptions_IdempotencyLevelFromJSON(object: any): MethodOptions_IdempotencyLevel;
export declare function methodOptions_IdempotencyLevelToJSON(object: MethodOptions_IdempotencyLevel): string;
/**
 * A message representing a option the parser does not recognize. This only
 * appears in options protos created by the compiler::Parser class.
 * DescriptorPool resolves these when building Descriptor objects. Therefore,
 * options protos in descriptor objects (e.g. returned by Descriptor::options(),
 * or produced by Descriptor::CopyTo()) will never have UninterpretedOptions
 * in them.
 */
export interface UninterpretedOption {
    name: UninterpretedOption_NamePart[];
    /**
     * The value of the uninterpreted option, in whatever type the tokenizer
     * identified it as during parsing. Exactly one of these should be set.
     */
    identifierValue?: string | undefined;
    positiveIntValue?: number | undefined;
    negativeIntValue?: number | undefined;
    doubleValue?: number | undefined;
    stringValue?: Uint8Array | undefined;
    aggregateValue?: string | undefined;
}
/**
 * The name of the uninterpreted option.  Each string represents a segment in
 * a dot-separated name.  is_extension is true iff a segment represents an
 * extension (denoted with parentheses in options specs in .proto files).
 * E.g.,{ ["foo", false], ["bar.baz", true], ["moo", false] } represents
 * "foo.(bar.baz).moo".
 */
export interface UninterpretedOption_NamePart {
    namePart: string;
    isExtension: boolean;
}
/**
 * TODO Enums in C++ gencode (and potentially other languages) are
 * not well scoped.  This means that each of the feature enums below can clash
 * with each other.  The short names we've chosen maximize call-site
 * readability, but leave us very open to this scenario.  A future feature will
 * be designed and implemented to handle this, hopefully before we ever hit a
 * conflict here.
 */
export interface FeatureSet {
    fieldPresence?: FeatureSet_FieldPresence | undefined;
    enumType?: FeatureSet_EnumType | undefined;
    repeatedFieldEncoding?: FeatureSet_RepeatedFieldEncoding | undefined;
    utf8Validation?: FeatureSet_Utf8Validation | undefined;
    messageEncoding?: FeatureSet_MessageEncoding | undefined;
    jsonFormat?: FeatureSet_JsonFormat | undefined;
    enforceNamingStyle?: FeatureSet_EnforceNamingStyle | undefined;
    defaultSymbolVisibility?: FeatureSet_VisibilityFeature_DefaultSymbolVisibility | undefined;
}
export declare enum FeatureSet_FieldPresence {
    FIELD_PRESENCE_UNKNOWN = 0,
    EXPLICIT = 1,
    IMPLICIT = 2,
    LEGACY_REQUIRED = 3,
    UNRECOGNIZED = -1
}
export declare function featureSet_FieldPresenceFromJSON(object: any): FeatureSet_FieldPresence;
export declare function featureSet_FieldPresenceToJSON(object: FeatureSet_FieldPresence): string;
export declare enum FeatureSet_EnumType {
    ENUM_TYPE_UNKNOWN = 0,
    OPEN = 1,
    CLOSED = 2,
    UNRECOGNIZED = -1
}
export declare function featureSet_EnumTypeFromJSON(object: any): FeatureSet_EnumType;
export declare function featureSet_EnumTypeToJSON(object: FeatureSet_EnumType): string;
export declare enum FeatureSet_RepeatedFieldEncoding {
    REPEATED_FIELD_ENCODING_UNKNOWN = 0,
    PACKED = 1,
    EXPANDED = 2,
    UNRECOGNIZED = -1
}
export declare function featureSet_RepeatedFieldEncodingFromJSON(object: any): FeatureSet_RepeatedFieldEncoding;
export declare function featureSet_RepeatedFieldEncodingToJSON(object: FeatureSet_RepeatedFieldEncoding): string;
export declare enum FeatureSet_Utf8Validation {
    UTF8_VALIDATION_UNKNOWN = 0,
    VERIFY = 2,
    NONE = 3,
    UNRECOGNIZED = -1
}
export declare function featureSet_Utf8ValidationFromJSON(object: any): FeatureSet_Utf8Validation;
export declare function featureSet_Utf8ValidationToJSON(object: FeatureSet_Utf8Validation): string;
export declare enum FeatureSet_MessageEncoding {
    MESSAGE_ENCODING_UNKNOWN = 0,
    LENGTH_PREFIXED = 1,
    DELIMITED = 2,
    UNRECOGNIZED = -1
}
export declare function featureSet_MessageEncodingFromJSON(object: any): FeatureSet_MessageEncoding;
export declare function featureSet_MessageEncodingToJSON(object: FeatureSet_MessageEncoding): string;
export declare enum FeatureSet_JsonFormat {
    JSON_FORMAT_UNKNOWN = 0,
    ALLOW = 1,
    LEGACY_BEST_EFFORT = 2,
    UNRECOGNIZED = -1
}
export declare function featureSet_JsonFormatFromJSON(object: any): FeatureSet_JsonFormat;
export declare function featureSet_JsonFormatToJSON(object: FeatureSet_JsonFormat): string;
export declare enum FeatureSet_EnforceNamingStyle {
    ENFORCE_NAMING_STYLE_UNKNOWN = 0,
    STYLE2024 = 1,
    STYLE_LEGACY = 2,
    STYLE2026 = 3,
    UNRECOGNIZED = -1
}
export declare function featureSet_EnforceNamingStyleFromJSON(object: any): FeatureSet_EnforceNamingStyle;
export declare function featureSet_EnforceNamingStyleToJSON(object: FeatureSet_EnforceNamingStyle): string;
export interface FeatureSet_VisibilityFeature {
}
export declare enum FeatureSet_VisibilityFeature_DefaultSymbolVisibility {
    DEFAULT_SYMBOL_VISIBILITY_UNKNOWN = 0,
    /** EXPORT_ALL - Default pre-EDITION_2024, all UNSET visibility are export. */
    EXPORT_ALL = 1,
    /** EXPORT_TOP_LEVEL - All top-level symbols default to export, nested default to local. */
    EXPORT_TOP_LEVEL = 2,
    /** LOCAL_ALL - All symbols default to local. */
    LOCAL_ALL = 3,
    /**
     * STRICT - All symbols local by default. Nested types cannot be exported.
     * With special case caveat for message { enum {} reserved 1 to max; }
     * This is the recommended setting for new protos.
     */
    STRICT = 4,
    UNRECOGNIZED = -1
}
export declare function featureSet_VisibilityFeature_DefaultSymbolVisibilityFromJSON(object: any): FeatureSet_VisibilityFeature_DefaultSymbolVisibility;
export declare function featureSet_VisibilityFeature_DefaultSymbolVisibilityToJSON(object: FeatureSet_VisibilityFeature_DefaultSymbolVisibility): string;
/**
 * A compiled specification for the defaults of a set of features.  These
 * messages are generated from FeatureSet extensions and can be used to seed
 * feature resolution. The resolution with this object becomes a simple search
 * for the closest matching edition, followed by proto merges.
 */
export interface FeatureSetDefaults {
    defaults: FeatureSetDefaults_FeatureSetEditionDefault[];
    /**
     * The minimum supported edition (inclusive) when this was constructed.
     * Editions before this will not have defaults.
     */
    minimumEdition?: Edition | undefined;
    /**
     * The maximum known edition (inclusive) when this was constructed. Editions
     * after this will not have reliable defaults.
     */
    maximumEdition?: Edition | undefined;
}
/**
 * A map from every known edition with a unique set of defaults to its
 * defaults. Not all editions may be contained here.  For a given edition,
 * the defaults at the closest matching edition ordered at or before it should
 * be used.  This field must be in strict ascending order by edition.
 */
export interface FeatureSetDefaults_FeatureSetEditionDefault {
    edition?: Edition | undefined;
    /** Defaults of features that can be overridden in this edition. */
    overridableFeatures?: FeatureSet | undefined;
    /** Defaults of features that can't be overridden in this edition. */
    fixedFeatures?: FeatureSet | undefined;
}
/**
 * Encapsulates information about the original source file from which a
 * FileDescriptorProto was generated.
 */
export interface SourceCodeInfo {
    /**
     * A Location identifies a piece of source code in a .proto file which
     * corresponds to a particular definition.  This information is intended
     * to be useful to IDEs, code indexers, documentation generators, and similar
     * tools.
     *
     * For example, say we have a file like:
     *   message Foo {
     *     optional string foo = 1;
     *   }
     * Let's look at just the field definition:
     *   optional string foo = 1;
     *   ^       ^^     ^^  ^  ^^^
     *   a       bc     de  f  ghi
     * We have the following locations:
     *   span   path               represents
     *   [a,i)  [ 4, 0, 2, 0 ]     The whole field definition.
     *   [a,b)  [ 4, 0, 2, 0, 4 ]  The label (optional).
     *   [c,d)  [ 4, 0, 2, 0, 5 ]  The type (string).
     *   [e,f)  [ 4, 0, 2, 0, 1 ]  The name (foo).
     *   [g,h)  [ 4, 0, 2, 0, 3 ]  The number (1).
     *
     * Notes:
     * - A location may refer to a repeated field itself (i.e. not to any
     *   particular index within it).  This is used whenever a set of elements are
     *   logically enclosed in a single code segment.  For example, an entire
     *   extend block (possibly containing multiple extension definitions) will
     *   have an outer location whose path refers to the "extensions" repeated
     *   field without an index.
     * - Multiple locations may have the same path.  This happens when a single
     *   logical declaration is spread out across multiple places.  The most
     *   obvious example is the "extend" block again -- there may be multiple
     *   extend blocks in the same scope, each of which will have the same path.
     * - A location's span is not always a subset of its parent's span.  For
     *   example, the "extendee" of an extension declaration appears at the
     *   beginning of the "extend" block and is shared by all extensions within
     *   the block.
     * - Just because a location's span is a subset of some other location's span
     *   does not mean that it is a descendant.  For example, a "group" defines
     *   both a type and a field in a single declaration.  Thus, the locations
     *   corresponding to the type and field and their components will overlap.
     * - Code which tries to interpret locations should probably be designed to
     *   ignore those that it doesn't understand, as more types of locations could
     *   be recorded in the future.
     */
    location: SourceCodeInfo_Location[];
}
export interface SourceCodeInfo_Location {
    /**
     * Identifies which part of the FileDescriptorProto was defined at this
     * location.
     *
     * Each element is a field number or an index.  They form a path from
     * the root FileDescriptorProto to the place where the definition appears.
     * For example, this path:
     *   [ 4, 3, 2, 7, 1 ]
     * refers to:
     *   file.message_type(3)  // 4, 3
     *       .field(7)         // 2, 7
     *       .name()           // 1
     * This is because FileDescriptorProto.message_type has field number 4:
     *   repeated DescriptorProto message_type = 4;
     * and DescriptorProto.field has field number 2:
     *   repeated FieldDescriptorProto field = 2;
     * and FieldDescriptorProto.name has field number 1:
     *   optional string name = 1;
     *
     * Thus, the above path gives the location of a field name.  If we removed
     * the last element:
     *   [ 4, 3, 2, 7 ]
     * this path refers to the whole field declaration (from the beginning
     * of the label to the terminating semicolon).
     */
    path: number[];
    /**
     * Always has exactly three or four elements: start line, start column,
     * end line (optional, otherwise assumed same as start line), end column.
     * These are packed into a single field for efficiency.  Note that line
     * and column numbers are zero-based -- typically you will want to add
     * 1 to each before displaying to a user.
     */
    span: number[];
    /**
     * If this SourceCodeInfo represents a complete declaration, these are any
     * comments appearing before and after the declaration which appear to be
     * attached to the declaration.
     *
     * A series of line comments appearing on consecutive lines, with no other
     * tokens appearing on those lines, will be treated as a single comment.
     *
     * leading_detached_comments will keep paragraphs of comments that appear
     * before (but not connected to) the current element. Each paragraph,
     * separated by empty lines, will be one comment element in the repeated
     * field.
     *
     * Only the comment content is provided; comment markers (e.g. //) are
     * stripped out.  For block comments, leading whitespace and an asterisk
     * will be stripped from the beginning of each line other than the first.
     * Newlines are included in the output.
     *
     * Examples:
     *
     *   optional int32 foo = 1;  // Comment attached to foo.
     *   // Comment attached to bar.
     *   optional int32 bar = 2;
     *
     *   optional string baz = 3;
     *   // Comment attached to baz.
     *   // Another line attached to baz.
     *
     *   // Comment attached to moo.
     *   //
     *   // Another line attached to moo.
     *   optional double moo = 4;
     *
     *   // Detached comment for corge. This is not leading or trailing comments
     *   // to moo or corge because there are blank lines separating it from
     *   // both.
     *
     *   // Detached comment for corge paragraph 2.
     *
     *   optional string corge = 5;
     *   /* Block comment attached
     *    * to corge.  Leading asterisks
     *    * will be removed. * /
     *   /* Block comment attached to
     *    * grault. * /
     *   optional int32 grault = 6;
     *
     *   // ignored detached comments.
     */
    leadingComments?: string | undefined;
    trailingComments?: string | undefined;
    leadingDetachedComments: string[];
}
/**
 * Describes the relationship between generated code and its original source
 * file. A GeneratedCodeInfo message is associated with only one generated
 * source file, but may contain references to different source .proto files.
 */
export interface GeneratedCodeInfo {
    /**
     * An Annotation connects some span of text in generated code to an element
     * of its generating .proto file.
     */
    annotation: GeneratedCodeInfo_Annotation[];
}
export interface GeneratedCodeInfo_Annotation {
    /**
     * Identifies the element in the original source .proto file. This field
     * is formatted the same as SourceCodeInfo.Location.path.
     */
    path: number[];
    /** Identifies the filesystem path to the original source .proto. */
    sourceFile?: string | undefined;
    /**
     * Identifies the starting offset in bytes in the generated code
     * that relates to the identified object.
     */
    begin?: number | undefined;
    /**
     * Identifies the ending offset in bytes in the generated code that
     * relates to the identified object. The end offset should be one past
     * the last relevant byte (so the length of the text = end - begin).
     */
    end?: number | undefined;
    semantic?: GeneratedCodeInfo_Annotation_Semantic | undefined;
}
/**
 * Represents the identified object's effect on the element in the original
 * .proto file.
 */
export declare enum GeneratedCodeInfo_Annotation_Semantic {
    /** NONE - There is no effect or the effect is indescribable. */
    NONE = 0,
    /** SET - The element is set or otherwise mutated. */
    SET = 1,
    /** ALIAS - An alias to the element is returned. */
    ALIAS = 2,
    UNRECOGNIZED = -1
}
export declare function generatedCodeInfo_Annotation_SemanticFromJSON(object: any): GeneratedCodeInfo_Annotation_Semantic;
export declare function generatedCodeInfo_Annotation_SemanticToJSON(object: GeneratedCodeInfo_Annotation_Semantic): string;
export declare const FileDescriptorSet: MessageFns<FileDescriptorSet>;
export declare const FileDescriptorProto: MessageFns<FileDescriptorProto>;
export declare const DescriptorProto: MessageFns<DescriptorProto>;
export declare const DescriptorProto_ExtensionRange: MessageFns<DescriptorProto_ExtensionRange>;
export declare const DescriptorProto_ReservedRange: MessageFns<DescriptorProto_ReservedRange>;
export declare const ExtensionRangeOptions: MessageFns<ExtensionRangeOptions>;
export declare const ExtensionRangeOptions_Declaration: MessageFns<ExtensionRangeOptions_Declaration>;
export declare const FieldDescriptorProto: MessageFns<FieldDescriptorProto>;
export declare const OneofDescriptorProto: MessageFns<OneofDescriptorProto>;
export declare const EnumDescriptorProto: MessageFns<EnumDescriptorProto>;
export declare const EnumDescriptorProto_EnumReservedRange: MessageFns<EnumDescriptorProto_EnumReservedRange>;
export declare const EnumValueDescriptorProto: MessageFns<EnumValueDescriptorProto>;
export declare const ServiceDescriptorProto: MessageFns<ServiceDescriptorProto>;
export declare const MethodDescriptorProto: MessageFns<MethodDescriptorProto>;
export declare const FileOptions: MessageFns<FileOptions>;
export declare const MessageOptions: MessageFns<MessageOptions>;
export declare const FieldOptions: MessageFns<FieldOptions>;
export declare const FieldOptions_EditionDefault: MessageFns<FieldOptions_EditionDefault>;
export declare const FieldOptions_FeatureSupport: MessageFns<FieldOptions_FeatureSupport>;
export declare const OneofOptions: MessageFns<OneofOptions>;
export declare const EnumOptions: MessageFns<EnumOptions>;
export declare const EnumValueOptions: MessageFns<EnumValueOptions>;
export declare const ServiceOptions: MessageFns<ServiceOptions>;
export declare const MethodOptions: MessageFns<MethodOptions>;
export declare const UninterpretedOption: MessageFns<UninterpretedOption>;
export declare const UninterpretedOption_NamePart: MessageFns<UninterpretedOption_NamePart>;
export declare const FeatureSet: MessageFns<FeatureSet>;
export declare const FeatureSet_VisibilityFeature: MessageFns<FeatureSet_VisibilityFeature>;
export declare const FeatureSetDefaults: MessageFns<FeatureSetDefaults>;
export declare const FeatureSetDefaults_FeatureSetEditionDefault: MessageFns<FeatureSetDefaults_FeatureSetEditionDefault>;
export declare const SourceCodeInfo: MessageFns<SourceCodeInfo>;
export declare const SourceCodeInfo_Location: MessageFns<SourceCodeInfo_Location>;
export declare const GeneratedCodeInfo: MessageFns<GeneratedCodeInfo>;
export declare const GeneratedCodeInfo_Annotation: MessageFns<GeneratedCodeInfo_Annotation>;
type Builtin = Date | Function | Uint8Array | string | number | boolean | undefined;
export type DeepPartial<T> = T extends Builtin ? T : T extends globalThis.Array<infer U> ? globalThis.Array<DeepPartial<U>> : T extends ReadonlyArray<infer U> ? ReadonlyArray<DeepPartial<U>> : T extends {} ? {
    [K in keyof T]?: DeepPartial<T[K]>;
} : Partial<T>;
type KeysOfUnion<T> = T extends T ? keyof T : never;
export type Exact<P, I extends P> = P extends Builtin ? P : P & {
    [K in keyof P]: Exact<P[K], I[K]>;
} & {
    [K in Exclude<keyof I, KeysOfUnion<P>>]: never;
};
export interface MessageFns<T> {
    encode(message: T, writer?: BinaryWriter): BinaryWriter;
    decode(input: BinaryReader | Uint8Array, length?: number): T;
    fromJSON(object: any): T;
    toJSON(message: T): unknown;
    create<I extends Exact<DeepPartial<T>, I>>(base?: I): T;
    fromPartial<I extends Exact<DeepPartial<T>, I>>(object: I): T;
}
export {};
