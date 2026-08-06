// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/native/dart_bridge_lora.dart';
import 'package:runanywhere/runanywhere_protos.dart'
    show
        LoraAdapterCatalogEntry,
        LoraAdapterCatalogGetRequest,
        LoraAdapterCatalogGetResult,
        LoraAdapterCatalogListRequest,
        LoraAdapterCatalogListResult,
        LoraAdapterCatalogQuery,
        LoraAdapterConfig,
        LoraAdapterInfo,
        LoraApplyRequest,
        LoraApplyResult,
        LoraRemoveRequest,
        LoraState;

void main() {
  tearDown(() {
    DartBridgeLoraRegistry.setRegisterProtoForTesting(null);
    DartBridgeLoraRegistry.setListCatalogProtoForTesting(null);
    DartBridgeLoraRegistry.setQueryCatalogProtoForTesting(null);
    DartBridgeLoraRegistry.setGetCatalogEntryProtoForTesting(null);
  });

  group('LoRA proto shape', () {
    test('uses generated apply request/result contracts', () {
      final config = LoraAdapterConfig(
        adapterId: 'style-a',
        adapterPath: '/models/style-a.gguf',
        scale: 0.75,
      );
      // `LoraApplyRequest.replaceExisting` was renamed `keepExisting` — an
      // inverted-polarity field (idl/lora_options.proto): SET semantics
      // (`keepExisting: false`) is the old `replaceExisting: true`.
      final request = LoraApplyRequest(
        requestId: 'apply-1',
        adapters: [config],
        keepExisting: false,
      );

      final roundTrip = LoraApplyRequest.fromBuffer(request.writeToBuffer());

      expect(roundTrip.requestId, 'apply-1');
      expect(roundTrip.adapters, hasLength(1));
      expect(roundTrip.adapters.single.adapterId, 'style-a');
      expect(roundTrip.adapters.single.adapterPath, '/models/style-a.gguf');
      expect(roundTrip.adapters.single.scale, closeTo(0.75, 0.0001));
      expect(roundTrip.keepExisting, isFalse);

      final result = LoraApplyResult(
        requestId: roundTrip.requestId,
        adapters: [
          LoraAdapterInfo(
            adapterId: 'style-a',
            adapterPath: '/models/style-a.gguf',
            scale: 0.75,
            applied: true,
          ),
        ],
      );

      final resultRoundTrip = LoraApplyResult.fromBuffer(
        result.writeToBuffer(),
      );

      expect(resultRoundTrip.requestId, 'apply-1');
      expect(resultRoundTrip.hasError(), isFalse);
      expect(resultRoundTrip.adapters.single.applied, isTrue);
    });

    test('uses generated remove request and state contracts', () {
      final request = LoraRemoveRequest(
        adapterIds: const ['style-a'],
        clearAll: true,
      );

      final roundTrip = LoraRemoveRequest.fromBuffer(request.writeToBuffer());

      expect(roundTrip.adapterIds, contains('style-a'));
      expect(roundTrip.clearAll, isTrue);

      final state = LoraState(
        loadedAdapters: [
          LoraAdapterInfo(
            adapterId: 'style-a',
            adapterPath: '/models/style-a.gguf',
            scale: 0.75,
            applied: true,
          ),
        ],
        baseModelId: 'base-model',
      );

      final stateRoundTrip = LoraState.fromBuffer(state.writeToBuffer());

      expect(stateRoundTrip.loadedAdapters.single.adapterId, 'style-a');
      expect(stateRoundTrip.baseModelId, 'base-model');
    });

    test('uses generated catalog query/get contracts', () {
      // Everything generic about the artifact (url, filename, size,
      // checksum, author, license, description) moved to `ModelInfo`
      // (idl/lora_options.proto) — the catalog entry now carries only the
      // adapter-specific facts.
      final entry = LoraAdapterCatalogEntry(
        id: 'style-a',
        name: 'Style A',
        compatibleModels: const ['base-a', 'base-b'],
        defaultScale: 0.7,
        tags: const ['style', 'demo'],
        localPath: '/models/lora/style-a.gguf',
      );

      final entryRoundTrip = LoraAdapterCatalogEntry.fromBuffer(
        entry.writeToBuffer(),
      );

      expect(entryRoundTrip.id, 'style-a');
      expect(entryRoundTrip.compatibleModels, contains('base-b'));
      expect(entryRoundTrip.defaultScale, closeTo(0.7, 0.0001));
      expect(entryRoundTrip.localPath, '/models/lora/style-a.gguf');

      final query = LoraAdapterCatalogQuery(
        adapterId: 'style-a',
        modelId: 'base-a',
        downloadedOnly: true,
        searchQuery: 'style',
        tags: const ['demo'],
      );
      final listRequest = LoraAdapterCatalogListRequest(query: query);
      final listResult = LoraAdapterCatalogListResult(
        entries: [entryRoundTrip],
        totalCount: 1,
        downloadedCount: 1,
      );

      final requestRoundTrip = LoraAdapterCatalogListRequest.fromBuffer(
        listRequest.writeToBuffer(),
      );
      final resultRoundTrip = LoraAdapterCatalogListResult.fromBuffer(
        listResult.writeToBuffer(),
      );

      expect(requestRoundTrip.query.modelId, 'base-a');
      expect(requestRoundTrip.query.downloadedOnly, isTrue);
      expect(resultRoundTrip.hasError(), isFalse);
      expect(resultRoundTrip.entries.single.id, 'style-a');
      expect(resultRoundTrip.downloadedCount, 1);

      final getRequest = LoraAdapterCatalogGetRequest(adapterId: 'style-a');
      final getResult = LoraAdapterCatalogGetResult(
        found: true,
        entry: entryRoundTrip,
      );

      expect(
        LoraAdapterCatalogGetRequest.fromBuffer(
          getRequest.writeToBuffer(),
        ).adapterId,
        'style-a',
      );
      expect(
        LoraAdapterCatalogGetResult.fromBuffer(
          getResult.writeToBuffer(),
        ).entry.id,
        'style-a',
      );
    });
  });

  group('LoRA catalog bridge behavior', () {
    test('forwards generated catalog list/query/get messages', () {
      final entry = LoraAdapterCatalogEntry(
        id: 'style-a',
        name: 'Style A',
        compatibleModels: const ['base-a'],
      );

      late LoraAdapterCatalogListRequest seenList;
      DartBridgeLoraRegistry.setListCatalogProtoForTesting((request) {
        seenList = request;
        return LoraAdapterCatalogListResult(entries: [entry], totalCount: 1);
      });

      final list = DartBridgeLoraRegistry.shared.listCatalog(
        LoraAdapterCatalogListRequest(
          query: LoraAdapterCatalogQuery(modelId: 'base-a'),
        ),
      );

      expect(seenList.query.modelId, 'base-a');
      expect(list.entries.single.id, 'style-a');

      late LoraAdapterCatalogQuery seenQuery;
      DartBridgeLoraRegistry.setQueryCatalogProtoForTesting((query) {
        seenQuery = query;
        return LoraAdapterCatalogListResult(entries: [entry]);
      });

      final queryResult = DartBridgeLoraRegistry.shared.queryCatalog(
        LoraAdapterCatalogQuery(downloadedOnly: true, tags: const ['style']),
      );

      expect(seenQuery.downloadedOnly, isTrue);
      expect(seenQuery.tags, contains('style'));
      expect(queryResult.entries.single.id, 'style-a');

      late LoraAdapterCatalogGetRequest seenGet;
      DartBridgeLoraRegistry.setGetCatalogEntryProtoForTesting((request) {
        seenGet = request;
        return LoraAdapterCatalogGetResult(found: true, entry: entry);
      });

      final getResult = DartBridgeLoraRegistry.shared.getCatalogEntry(
        LoraAdapterCatalogGetRequest(adapterId: 'style-a'),
      );

      expect(seenGet.adapterId, 'style-a');
      expect(getResult.found, isTrue);
      expect(getResult.entry.id, 'style-a');
    });

    test('compatibility helpers use generated list and query ABI', () {
      DartBridgeLoraRegistry.setQueryCatalogProtoForTesting((query) {
        expect(query.modelId, 'base-a');
        return LoraAdapterCatalogListResult(
          entries: [LoraAdapterCatalogEntry(id: 'style-a', name: 'Style A')],
        );
      });
      DartBridgeLoraRegistry.setListCatalogProtoForTesting((request) {
        expect(request.hasQuery(), isFalse);
        return LoraAdapterCatalogListResult(
          entries: [
            LoraAdapterCatalogEntry(id: 'style-a', name: 'Style A'),
            LoraAdapterCatalogEntry(id: 'tone-a', name: 'Tone A'),
          ],
        );
      });

      final forModel = DartBridgeLoraRegistry.shared.getForModel('base-a');
      final all = DartBridgeLoraRegistry.shared.getAll();

      expect(forModel.map((entry) => entry.id), ['style-a']);
      expect(all.map((entry) => entry.id), ['style-a', 'tone-a']);
    });

    test('binds generated catalog ABI and removes C-array fallback catalog',
        () {
      final bridge =
          File('lib/native/dart_bridge_lora.dart').readAsStringSync();
      final bindings =
          File('lib/core/native/rac_native.dart').readAsStringSync();

      for (final symbol in [
        'rac_lora_catalog_list_proto',
        'rac_lora_catalog_query_proto',
        'rac_lora_catalog_get_proto',
      ]) {
        expect(bindings, contains(symbol));
        expect(bridge, contains(symbol));
      }

      for (final stale in [
        'RacLoraEntryCStruct',
        'rac_get_lora_for_model',
        'rac_lora_registry_get_all',
        'rac_lora_entry_array_free',
        // `rac_lora_catalog_mark_download_completed_proto` and
        // `rac_lora_adapter_import_proto` are permanently-retired stubs
        // (idl/lora_options.proto, lora-delete-download-import-bookkeeping)
        // — the bridge no longer calls either.
        'rac_lora_catalog_mark_download_completed_proto',
        'rac_lora_adapter_import_proto',
      ]) {
        expect(bridge, isNot(contains(stale)));
      }
    });
  });
}
