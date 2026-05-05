//
//  Generated code. Do not modify.
//  source: embeddings_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'embeddings_options.pb.dart' as $2;
import 'embeddings_options.pbjson.dart';

export 'embeddings_options.pb.dart';

abstract class EmbeddingsServiceBase extends $pb.GeneratedService {
  $async.Future<$2.EmbeddingsResult> embed($pb.ServerContext ctx, $2.EmbeddingsRequest request);
  $async.Future<$2.EmbeddingsResult> embedBatch($pb.ServerContext ctx, $2.EmbeddingsRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Embed': return $2.EmbeddingsRequest();
      case 'EmbedBatch': return $2.EmbeddingsRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Embed': return this.embed(ctx, request as $2.EmbeddingsRequest);
      case 'EmbedBatch': return this.embedBatch(ctx, request as $2.EmbeddingsRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => EmbeddingsServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => EmbeddingsServiceBase$messageJson;
}

