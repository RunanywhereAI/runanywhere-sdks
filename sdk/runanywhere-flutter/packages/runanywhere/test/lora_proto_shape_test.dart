// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/native/dart_bridge_lora.dart';
import 'package:runanywhere/runanywhere.dart'
    show
        LoRAAdapterConfig,
        LoRAAdapterInfo,
        LoRAApplyRequest,
        LoRAApplyResult,
        LoRARemoveRequest,
        LoRAState,
        LoraAdapterCatalogEntry,
        LoraAdapterCatalogGetRequest,
        LoraAdapterCatalogGetResult,
        LoraAdapterCatalogListRequest,
        LoraAdapterCatalogListResult,
        LoraAdapterCatalogQuery,
        LoraAdapterDownloadCompletedRequest,
        LoraAdapterDownloadCompletedResult;

void main() {
  tearDown(() {
    DartBridgeLoraRegistry.setRegisterProtoForTesting(null);
    DartBridgeLoraRegistry.setListCatalogProtoForTesting(null);
    DartBridgeLoraRegistry.setQueryCatalogProtoForTesting(null);
    DartBridgeLoraRegistry.setGetCatalogEntryProtoForTesting(null);
    DartBridgeLoraRegistry.setMarkDownloadCompletedProtoForTesting(null);
  });

  group('LoRA proto shape', () {
    test('uses generated apply request/result contracts', () {
      final config = LoRAAdapterConfig(
        adapterId: 'style-a',
        adapterPath: '/models/style-a.gguf',
        scale: 0.75,
        targetModules: const ['q_proj'],
        metadata: <String, String>{'rank': '8'}.entries,
      );
      final request = LoRAApplyRequest(
        requestId: 'apply-1',
        adapters: [config],
        replaceExisting: true,
      );

      final roundTrip = LoRAApplyRequest.fromBuffer(request.writeToBuffer());

      expect(roundTrip.requestId, 'apply-1');
      expect(roundTrip.adapters, hasLength(1));
      expect(roundTrip.adapters.single.adapterId, 'style-a');
      expect(roundTrip.adapters.single.adapterPath, '/models/style-a.gguf');
      expect(roundTrip.adapters.single.scale, closeTo(0.75, 0.0001));
      expect(roundTrip.adapters.single.targetModules, contains('q_proj'));
      expect(roundTrip.adapters.single.metadata['rank'], '8');
      expect(roundTrip.replaceExisting, isTrue);

      final result = LoRAApplyResult(
        requestId: roundTrip.requestId,
        adapters: [
          LoRAAdapterInfo(
            adapterId: 'style-a',
            adapterPath: '/models/style-a.gguf',
            scale: 0.75,
            applied: true,
          ),
        ],
        success: true,
      );

      final resultRoundTrip =
          LoRAApplyResult.fromBuffer(result.writeToBuffer());

      expect(resultRoundTrip.requestId, 'apply-1');
      expect(resultRoundTrip.success, isTrue);
      expect(resultRoundTrip.adapters.single.applied, isTrue);
    });

    test('uses generated remove request and state contracts', () {
      final request = LoRARemoveRequest(
        requestId: 'remove-1',
        adapterIds: const ['style-a'],
        adapterPaths: const ['/models/style-a.gguf'],
        clearAll: true,
      );

      final roundTrip = LoRARemoveRequest.fromBuffer(request.writeToBuffer());

      expect(roundTrip.requestId, 'remove-1');
      expect(roundTrip.adapterIds, contains('style-a'));
      expect(roundTrip.adapterPaths, contains('/models/style-a.gguf'));
      expect(roundTrip.clearAll, isTrue);

      final state = LoRAState(
        loadedAdapters: [
          LoRAAdapterInfo(
            adapterId: 'style-a',
            adapterPath: '/models/style-a.gguf',
            scale: 0.75,
            applied: true,
          ),
        ],
        hasActiveAdapters: true,
        baseModelId: 'base-model',
      );

      final stateRoundTrip = LoRAState.fromBuffer(state.writeToBuffer());

      expect(stateRoundTrip.loadedAdapters.single.adapterId, 'style-a');
      expect(stateRoundTrip.hasActiveAdapters, isTrue);
      expect(stateRoundTrip.baseModelId, 'base-model');
    });

    test('uses generated catalog query/get/download-completion contracts', () {
      final entry = LoraAdapterCatalogEntry(
        id: 'style-a',
        name: 'Style A',
        description: 'style adapter',
        url: 'https://example.com/style-a.gguf',
        filename: 'style-a.gguf',
        compatibleModels: const ['base-a', 'base-b'],
        sizeBytes: fixnum.Int64(1234),
        author: 'RunAnywhere',
        defaultScale: 0.7,
        checksumSha256: 'abc123',
        license: 'Apache-2.0',
        tags: const ['style', 'demo'],
        metadata: <String, String>{'rank': '8'}.entries,
        localPath: '/models/lora/style-a.gguf',
        isDownloaded: true,
        downloadedAtUnixMs: fixnum.Int64(9999),
        isImported: false,
        statusMessage: 'ready',
      );

      final entryRoundTrip =
          LoraAdapterCatalogEntry.fromBuffer(entry.writeToBuffer());

      expect(entryRoundTrip.id, 'style-a');
      expect(entryRoundTrip.compatibleModels, contains('base-b'));
      expect(entryRoundTrip.sizeBytes.toInt(), 1234);
      expect(entryRoundTrip.defaultScale, closeTo(0.7, 0.0001));
      expect(entryRoundTrip.localPath, '/models/lora/style-a.gguf');
      expect(entryRoundTrip.isDownloaded, isTrue);
      expect(entryRoundTrip.downloadedAtUnixMs.toInt(), 9999);
      expect(entryRoundTrip.metadata['rank'], '8');

      final query = LoraAdapterCatalogQuery(
        adapterId: 'style-a',
        modelId: 'base-a',
        downloadedOnly: true,
        searchQuery: 'style',
        tags: const ['demo'],
      );
      final listRequest = LoraAdapterCatalogListRequest(
        query: query,
        includeCounts: true,
      );
      final listResult = LoraAdapterCatalogListResult(
        success: true,
        entries: [entryRoundTrip],
        totalCount: 1,
        filteredCount: 1,
        downloadedCount: 1,
      );

      final requestRoundTrip =
          LoraAdapterCatalogListRequest.fromBuffer(listRequest.writeToBuffer());
      final resultRoundTrip =
          LoraAdapterCatalogListResult.fromBuffer(listResult.writeToBuffer());

      expect(requestRoundTrip.query.modelId, 'base-a');
      expect(requestRoundTrip.query.downloadedOnly, isTrue);
      expect(requestRoundTrip.includeCounts, isTrue);
      expect(resultRoundTrip.success, isTrue);
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

      final completed = LoraAdapterDownloadCompletedRequest(
        adapterId: 'style-a',
        localPath: '/models/lora/style-a.gguf',
        sizeBytes: fixnum.Int64(1234),
        checksumSha256: 'abc123',
        completedAtUnixMs: fixnum.Int64(9999),
        imported: true,
        statusMessage: 'ready',
      );
      final completedResult = LoraAdapterDownloadCompletedResult(
        success: true,
        entry: entryRoundTrip,
        persisted: true,
      );

      expect(
        LoraAdapterDownloadCompletedRequest.fromBuffer(
          completed.writeToBuffer(),
        ).localPath,
        '/models/lora/style-a.gguf',
      );
      expect(
        LoraAdapterDownloadCompletedResult.fromBuffer(
          completedResult.writeToBuffer(),
        ).persisted,
        isTrue,
      );
    });
  });

  group('LoRA catalog bridge behavior', () {
    test('forwards generated catalog list/query/get/completion messages', () {
      final entry = LoraAdapterCatalogEntry(
        id: 'style-a',
        name: 'Style A',
        compatibleModels: const ['base-a'],
      );

      late LoraAdapterCatalogListRequest seenList;
      DartBridgeLoraRegistry.setListCatalogProtoForTesting((request) {
        seenList = request;
        return LoraAdapterCatalogListResult(
          success: true,
          entries: [entry],
          totalCount: 1,
        );
      });

      final list = DartBridgeLoraRegistry.shared.listCatalog(
        LoraAdapterCatalogListRequest(
          query: LoraAdapterCatalogQuery(modelId: 'base-a'),
          includeCounts: true,
        ),
      );

      expect(seenList.query.modelId, 'base-a');
      expect(seenList.includeCounts, isTrue);
      expect(list.entries.single.id, 'style-a');

      late LoraAdapterCatalogQuery seenQuery;
      DartBridgeLoraRegistry.setQueryCatalogProtoForTesting((query) {
        seenQuery = query;
        return LoraAdapterCatalogListResult(success: true, entries: [entry]);
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

      late LoraAdapterDownloadCompletedRequest seenCompleted;
      DartBridgeLoraRegistry.setMarkDownloadCompletedProtoForTesting(
        (request) {
          seenCompleted = request;
          return LoraAdapterDownloadCompletedResult(
            success: true,
            entry: entry,
            persisted: true,
          );
        },
      );

      final completedResult =
          DartBridgeLoraRegistry.shared.markDownloadCompleted(
        LoraAdapterDownloadCompletedRequest(
          adapterId: 'style-a',
          localPath: '/native-owned/style-a.gguf',
          imported: true,
        ),
      );

      expect(seenCompleted.adapterId, 'style-a');
      expect(seenCompleted.localPath, '/native-owned/style-a.gguf');
      expect(completedResult.persisted, isTrue);
    });

    test('compatibility helpers use generated list and query ABI', () {
      DartBridgeLoraRegistry.setQueryCatalogProtoForTesting((query) {
        expect(query.modelId, 'base-a');
        return LoraAdapterCatalogListResult(
          success: true,
          entries: [
            LoraAdapterCatalogEntry(id: 'style-a', name: 'Style A'),
          ],
        );
      });
      DartBridgeLoraRegistry.setListCatalogProtoForTesting((request) {
        expect(request.hasQuery(), isFalse);
        return LoraAdapterCatalogListResult(
          success: true,
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
        'rac_lora_catalog_mark_download_completed_proto',
      ]) {
        expect(bindings, contains(symbol));
        expect(bridge, contains(symbol));
      }

      for (final stale in [
        'RacLoraEntryCStruct',
        'rac_get_lora_for_model',
        'rac_lora_registry_get_all',
        'rac_lora_entry_array_free',
      ]) {
        expect(bridge, isNot(contains(stale)));
      }
    });
  });
}
