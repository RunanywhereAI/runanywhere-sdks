// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Federated-package entry point. Re-exports the canonical adapter
// from `sdk/dart/lib/` so consumers get the same public surface
// whether they depend on the top-level `runanywhere` single package
// or this federated `runanywhere` package.

export '../../../lib/runanywhere.dart';
