//
//  Generated code. Do not modify.
//  source: rag.proto
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

import 'rag.pb.dart' as $4;
import 'rag.pbjson.dart';

export 'rag.pb.dart';

abstract class RAGServiceBase extends $pb.GeneratedService {
  $async.Future<$4.RAGServiceState> create($pb.ServerContext ctx, $4.RAGConfiguration request);
  $async.Future<$4.RAGIngestResult> ingest($pb.ServerContext ctx, $4.RAGIngestRequest request);
  $async.Future<$4.RAGResult> query($pb.ServerContext ctx, $4.RAGQueryRequest request);
  $async.Future<$4.RAGResult> search($pb.ServerContext ctx, $4.RAGQueryRequest request);
  $async.Future<$4.RAGStatistics> stats($pb.ServerContext ctx, $4.RAGServiceState request);
  $async.Future<$4.RAGServiceState> clear($pb.ServerContext ctx, $4.RAGServiceState request);
  $async.Future<$4.RAGStreamEvent> stream($pb.ServerContext ctx, $4.RAGQueryRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Create': return $4.RAGConfiguration();
      case 'Ingest': return $4.RAGIngestRequest();
      case 'Query': return $4.RAGQueryRequest();
      case 'Search': return $4.RAGQueryRequest();
      case 'Stats': return $4.RAGServiceState();
      case 'Clear': return $4.RAGServiceState();
      case 'Stream': return $4.RAGQueryRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Create': return this.create(ctx, request as $4.RAGConfiguration);
      case 'Ingest': return this.ingest(ctx, request as $4.RAGIngestRequest);
      case 'Query': return this.query(ctx, request as $4.RAGQueryRequest);
      case 'Search': return this.search(ctx, request as $4.RAGQueryRequest);
      case 'Stats': return this.stats(ctx, request as $4.RAGServiceState);
      case 'Clear': return this.clear(ctx, request as $4.RAGServiceState);
      case 'Stream': return this.stream(ctx, request as $4.RAGQueryRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => RAGServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => RAGServiceBase$messageJson;
}

