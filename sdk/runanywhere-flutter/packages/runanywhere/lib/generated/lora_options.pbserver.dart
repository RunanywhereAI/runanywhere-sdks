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

import 'lora_options.pb.dart' as $17;
import 'lora_options.pbjson.dart';

export 'lora_options.pb.dart';

abstract class LoRAServiceBase extends $pb.GeneratedService {
  $async.Future<$17.LoraAdapterCatalogEntry> registerCatalogEntry($pb.ServerContext ctx, $17.LoraAdapterCatalogEntry request);
  $async.Future<$17.LoraAdapterCatalogListResult> listCatalog($pb.ServerContext ctx, $17.LoraAdapterCatalogListRequest request);
  $async.Future<$17.LoraAdapterCatalogListResult> queryCatalog($pb.ServerContext ctx, $17.LoraAdapterCatalogQuery request);
  $async.Future<$17.LoraAdapterCatalogGetResult> getCatalogEntry($pb.ServerContext ctx, $17.LoraAdapterCatalogGetRequest request);
  $async.Future<$17.LoraAdapterDownloadCompletedResult> markDownloadCompleted($pb.ServerContext ctx, $17.LoraAdapterDownloadCompletedRequest request);
  $async.Future<$17.LoRAApplyResult> apply($pb.ServerContext ctx, $17.LoRAApplyRequest request);
  $async.Future<$17.LoRAState> remove($pb.ServerContext ctx, $17.LoRARemoveRequest request);
  $async.Future<$17.LoraCompatibilityResult> checkCompatibility($pb.ServerContext ctx, $17.LoRAAdapterConfig request);
  $async.Future<$17.LoRAState> list($pb.ServerContext ctx, $17.LoRAState request);
  $async.Future<$17.LoRAState> state($pb.ServerContext ctx, $17.LoRAState request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'RegisterCatalogEntry': return $17.LoraAdapterCatalogEntry();
      case 'ListCatalog': return $17.LoraAdapterCatalogListRequest();
      case 'QueryCatalog': return $17.LoraAdapterCatalogQuery();
      case 'GetCatalogEntry': return $17.LoraAdapterCatalogGetRequest();
      case 'MarkDownloadCompleted': return $17.LoraAdapterDownloadCompletedRequest();
      case 'Apply': return $17.LoRAApplyRequest();
      case 'Remove': return $17.LoRARemoveRequest();
      case 'CheckCompatibility': return $17.LoRAAdapterConfig();
      case 'List': return $17.LoRAState();
      case 'State': return $17.LoRAState();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'RegisterCatalogEntry': return this.registerCatalogEntry(ctx, request as $17.LoraAdapterCatalogEntry);
      case 'ListCatalog': return this.listCatalog(ctx, request as $17.LoraAdapterCatalogListRequest);
      case 'QueryCatalog': return this.queryCatalog(ctx, request as $17.LoraAdapterCatalogQuery);
      case 'GetCatalogEntry': return this.getCatalogEntry(ctx, request as $17.LoraAdapterCatalogGetRequest);
      case 'MarkDownloadCompleted': return this.markDownloadCompleted(ctx, request as $17.LoraAdapterDownloadCompletedRequest);
      case 'Apply': return this.apply(ctx, request as $17.LoRAApplyRequest);
      case 'Remove': return this.remove(ctx, request as $17.LoRARemoveRequest);
      case 'CheckCompatibility': return this.checkCompatibility(ctx, request as $17.LoRAAdapterConfig);
      case 'List': return this.list(ctx, request as $17.LoRAState);
      case 'State': return this.state(ctx, request as $17.LoRAState);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => LoRAServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => LoRAServiceBase$messageJson;
}

