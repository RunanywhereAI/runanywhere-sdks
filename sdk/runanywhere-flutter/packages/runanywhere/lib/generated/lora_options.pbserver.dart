//
//  Generated code. Do not modify.
//  source: lora_options.proto
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

import 'lora_options.pb.dart' as $3;
import 'lora_options.pbjson.dart';

export 'lora_options.pb.dart';

abstract class LoRAServiceBase extends $pb.GeneratedService {
  $async.Future<$3.LoraAdapterCatalogEntry> registerCatalogEntry($pb.ServerContext ctx, $3.LoraAdapterCatalogEntry request);
  $async.Future<$3.LoraAdapterCatalogListResult> listCatalog($pb.ServerContext ctx, $3.LoraAdapterCatalogListRequest request);
  $async.Future<$3.LoraAdapterCatalogListResult> queryCatalog($pb.ServerContext ctx, $3.LoraAdapterCatalogQuery request);
  $async.Future<$3.LoraAdapterCatalogGetResult> getCatalogEntry($pb.ServerContext ctx, $3.LoraAdapterCatalogGetRequest request);
  $async.Future<$3.LoraAdapterDownloadCompletedResult> markDownloadCompleted($pb.ServerContext ctx, $3.LoraAdapterDownloadCompletedRequest request);
  $async.Future<$3.LoRAApplyResult> apply($pb.ServerContext ctx, $3.LoRAApplyRequest request);
  $async.Future<$3.LoRAState> remove($pb.ServerContext ctx, $3.LoRARemoveRequest request);
  $async.Future<$3.LoraCompatibilityResult> checkCompatibility($pb.ServerContext ctx, $3.LoRAAdapterConfig request);
  $async.Future<$3.LoRAState> list($pb.ServerContext ctx, $3.LoRAState request);
  $async.Future<$3.LoRAState> state($pb.ServerContext ctx, $3.LoRAState request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'RegisterCatalogEntry': return $3.LoraAdapterCatalogEntry();
      case 'ListCatalog': return $3.LoraAdapterCatalogListRequest();
      case 'QueryCatalog': return $3.LoraAdapterCatalogQuery();
      case 'GetCatalogEntry': return $3.LoraAdapterCatalogGetRequest();
      case 'MarkDownloadCompleted': return $3.LoraAdapterDownloadCompletedRequest();
      case 'Apply': return $3.LoRAApplyRequest();
      case 'Remove': return $3.LoRARemoveRequest();
      case 'CheckCompatibility': return $3.LoRAAdapterConfig();
      case 'List': return $3.LoRAState();
      case 'State': return $3.LoRAState();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'RegisterCatalogEntry': return this.registerCatalogEntry(ctx, request as $3.LoraAdapterCatalogEntry);
      case 'ListCatalog': return this.listCatalog(ctx, request as $3.LoraAdapterCatalogListRequest);
      case 'QueryCatalog': return this.queryCatalog(ctx, request as $3.LoraAdapterCatalogQuery);
      case 'GetCatalogEntry': return this.getCatalogEntry(ctx, request as $3.LoraAdapterCatalogGetRequest);
      case 'MarkDownloadCompleted': return this.markDownloadCompleted(ctx, request as $3.LoraAdapterDownloadCompletedRequest);
      case 'Apply': return this.apply(ctx, request as $3.LoRAApplyRequest);
      case 'Remove': return this.remove(ctx, request as $3.LoRARemoveRequest);
      case 'CheckCompatibility': return this.checkCompatibility(ctx, request as $3.LoRAAdapterConfig);
      case 'List': return this.list(ctx, request as $3.LoRAState);
      case 'State': return this.state(ctx, request as $3.LoRAState);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => LoRAServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => LoRAServiceBase$messageJson;
}

