// RAG Demo View
//
// Full-screen RAG document Q&A UI.
// Mirrors iOS DocumentRAGView.swift adapted for Material Design.
// Allows model selection, document ingestion, chat Q&A with expandable
// retrieved chunks and timing metrics.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:runanywhere/public/types/rag_types.dart';

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/rag/rag_view_model.dart';

/// RagDemoView — Full-page RAG document Q&A screen.
///
/// Entry point: pushed from Chat tab AppBar via Navigator.push.
/// Manages its own [RAGViewModel] lifecycle.
class RagDemoView extends StatefulWidget {
  const RagDemoView({super.key});

  @override
  State<RagDemoView> createState() => _RagDemoViewState();
}

class _RagDemoViewState extends State<RagDemoView> {
  final RAGViewModel _viewModel = RAGViewModel();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _questionController = TextEditingController();

  ModelInfo? _selectedEmbeddingModel;
  ModelInfo? _selectedLLMModel;

  // MARK: - Computed

  bool get _areModelsReady =>
      _selectedEmbeddingModel?.localPath != null &&
      _selectedLLMModel?.localPath != null;

  // MARK: - Lifecycle

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _scrollController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    // Sync question controller with view model (for external clears)
    if (_viewModel.currentQuestion != _questionController.text) {
      // Only sync when viewModel clears the field (askQuestion resets it)
      if (_viewModel.currentQuestion.isEmpty) {
        _questionController.clear();
      }
    }
    // Auto-scroll on new messages
    _scrollToBottom();
  }

  // MARK: - Path Resolution (mirrors iOS exactly)

  /// Resolve the actual embedding model file path.
  ///
  /// Multi-file models store localPath as a directory containing model.onnx.
  String _resolveEmbeddingFilePath(String localPath) {
    if (Directory(localPath).existsSync()) {
      return '$localPath/model.onnx';
    }
    return localPath;
  }

  /// Resolve the actual LLM model file path.
  ///
  /// Single-file LlamaCpp models live inside a directory — find the first .gguf file.
  String _resolveLLMFilePath(String localPath) {
    if (!Directory(localPath).existsSync()) {
      return localPath;
    }
    final dir = Directory(localPath);
    final ggufFile = dir
        .listSync()
        .whereType<File>()
        .firstWhere(
          (f) => f.path.toLowerCase().endsWith('.gguf'),
          orElse: () => File(localPath),
        );
    return ggufFile.path;
  }

  /// Resolve the vocab.txt path for the embedding model.
  ///
  /// For multi-file models (directory) vocab.txt is inside the directory.
  /// For single-file models vocab.txt is a sibling file.
  String? _resolveVocabPath(ModelInfo embeddingModel) {
    final localPath = embeddingModel.localPath;
    if (localPath == null) return null;

    if (Directory(localPath).existsSync()) {
      return '$localPath/vocab.txt';
    }
    // Single-file: sibling vocab.txt
    final parent = File(localPath).parent.path;
    return '$parent/vocab.txt';
  }

  /// Build a [RAGConfiguration] from selected models with resolved paths.
  RAGConfiguration? _buildRagConfig() {
    final embeddingPath = _selectedEmbeddingModel?.localPath;
    final llmPath = _selectedLLMModel?.localPath;
    if (embeddingPath == null || llmPath == null) return null;

    final vocabPath = _resolveVocabPath(_selectedEmbeddingModel!);
    final embeddingConfigJson =
        vocabPath != null ? '{"vocab_path":"$vocabPath"}' : null;

    return RAGConfiguration(
      embeddingModelPath: _resolveEmbeddingFilePath(embeddingPath),
      llmModelPath: _resolveLLMFilePath(llmPath),
      embeddingConfigJSON: embeddingConfigJson,
    );
  }

  // MARK: - Actions

  void _showEmbeddingModelSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ModelSelectionSheet(
        context: ModelSelectionContext.ragEmbedding,
        onModelSelected: (model) async {
          // RAG model selection does NOT pre-load into memory — just record selection
          setState(() {
            _selectedEmbeddingModel = model;
          });
        },
      ),
    ));
  }

  void _showLLMModelSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ModelSelectionSheet(
        context: ModelSelectionContext.ragLLM,
        onModelSelected: (model) async {
          // RAG model selection does NOT pre-load into memory — just record selection
          setState(() {
            _selectedLLMModel = model;
          });
        },
      ),
    ));
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'json'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;

      final ragConfig = _buildRagConfig();
      if (ragConfig == null) return;

      await _viewModel.loadDocument(filePath, ragConfig);
    } catch (e) {
      _viewModel.error = 'Failed to pick file: $e';
    }
  }

  Future<void> _changeDocument() async {
    await _viewModel.clearDocument();
    await _pickDocument();
  }

  void _sendQuestion() {
    if (!_viewModel.canAskQuestion) return;
    unawaited(_viewModel.askQuestion());
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        unawaited(_scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppLayout.animationFast,
          curve: Curves.easeOut,
        ));
      }
    });
  }

  // MARK: - Build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Q&A'),
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return Column(
            children: [
              _buildModelSetupSection(),
              const Divider(height: 1),
              _buildDocumentStatusBar(),
              const Divider(height: 1),
              if (_viewModel.error != null) _buildErrorBanner(),
              Expanded(child: _buildMessagesArea()),
              _buildInputBar(),
            ],
          );
        },
      ),
    );
  }

  // MARK: - Model Setup Section

  Widget _buildModelSetupSection() {
    return Container(
      color: AppColors.backgroundPrimary(context),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.mediumLarge,
      ),
      child: Column(
        children: [
          _buildModelPickerRow(
            label: 'Embedding Model',
            icon: Icons.psychology_outlined,
            model: _selectedEmbeddingModel,
            onTap: _showEmbeddingModelSheet,
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          _buildModelPickerRow(
            label: 'LLM Model',
            icon: Icons.chat_bubble_outline,
            model: _selectedLLMModel,
            onTap: _showLLMModelSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildModelPickerRow({
    required String label,
    required IconData icon,
    required ModelInfo? model,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xSmall),
        child: Row(
          children: [
            Icon(
              icon,
              size: AppSpacing.iconRegular,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(width: AppSpacing.mediumLarge),
            Text(
              label,
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
            const Spacer(),
            if (model != null) ...[
              Flexible(
                child: Text(
                  model.name,
                  style: AppTypography.subheadline(context).copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: AppSpacing.xSmall),
              const Icon(
                Icons.check_circle,
                size: AppSpacing.iconRegular,
                color: AppColors.primaryGreen,
              ),
            ] else ...[
              Text(
                'Not selected',
                style: AppTypography.subheadline(context).copyWith(
                  color: AppColors.primaryAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.xSmall),
              Icon(
                Icons.chevron_right,
                size: AppSpacing.iconRegular,
                color: AppColors.textSecondary(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // MARK: - Document Status Bar

  Widget _buildDocumentStatusBar() {
    if (_viewModel.isLoadingDocument) {
      return _buildLoadingStatus();
    }
    if (_viewModel.isDocumentLoaded && _viewModel.documentName != null) {
      return _buildLoadedStatus(_viewModel.documentName!);
    }
    return _buildNoDocumentStatus();
  }

  Widget _buildNoDocumentStatus() {
    return Container(
      color: AppColors.backgroundPrimary(context),
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Center(
        child: ElevatedButton.icon(
          onPressed: _areModelsReady ? _pickDocument : null,
          icon: const Icon(Icons.add_to_photos_outlined),
          label: const Text('Select Document'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xLarge,
              vertical: AppSpacing.mediumLarge,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingStatus() {
    return Container(
      color: AppColors.backgroundPrimary(context),
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.mediumLarge),
          Text(
            'Loading document...',
            style: AppTypography.subheadline(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedStatus(String documentName) {
    return Container(
      color: AppColors.backgroundPrimary(context),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.mediumLarge,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: AppColors.primaryGreen,
            size: AppSpacing.iconRegular + 4,
          ),
          const SizedBox(width: AppSpacing.mediumLarge),
          Expanded(
            child: Text(
              documentName,
              style: AppTypography.subheadline(context).copyWith(
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          TextButton(
            onPressed: _changeDocument,
            child: Text(
              'Change',
              style: AppTypography.caption(context).copyWith(
                color: AppColors.primaryAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Error Banner

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.smallMedium,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mediumLarge,
        vertical: AppSpacing.smallMedium,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryRed.withValues(alpha: 0.1),
        borderRadius:
            BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.primaryRed,
            size: AppSpacing.iconRegular,
          ),
          const SizedBox(width: AppSpacing.mediumLarge),
          Expanded(
            child: Text(
              _viewModel.error!,
              style: AppTypography.caption(context).copyWith(
                color: AppColors.primaryRed,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: AppSpacing.iconRegular),
            onPressed: () => _viewModel.error = null,
            color: AppColors.textSecondary(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // MARK: - Messages Area

  Widget _buildMessagesArea() {
    final messages = _viewModel.messages;

    if (messages.isEmpty) {
      return _buildEmptyState();
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.large,
        ),
        itemCount: messages.length + (_viewModel.isQuerying ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length && _viewModel.isQuerying) {
            return _buildQueryingIndicator();
          }
          return _RAGMessageBubble(message: messages[index]);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final String title;
    final String subtitle;
    if (_viewModel.isDocumentLoaded) {
      title = 'Document loaded';
      subtitle = 'Ask a question below to get started';
    } else if (!_areModelsReady) {
      title = 'Select models to get started';
      subtitle =
          'Choose an embedding model and an LLM model above, then pick a document';
    } else {
      title = 'No document selected';
      subtitle = 'Pick a PDF or JSON document to start asking questions';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.find_in_page_outlined,
              size: AppSpacing.iconXXLarge,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(height: AppSpacing.large),
            Text(
              title,
              style: AppTypography.headline(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              subtitle,
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueryingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.large),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.smallMedium),
          Text(
            'Searching document...',
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Input Bar

  Widget _buildInputBar() {
    final canSend = _viewModel.canAskQuestion;
    final isQuerying = _viewModel.isQuerying;
    final isDocumentLoaded = _viewModel.isDocumentLoaded;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary(context),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: AppSpacing.shadowLarge,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _questionController,
                maxLines: 4,
                minLines: 1,
                enabled: isDocumentLoaded && !isQuerying,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Ask a question...',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.cornerRadiusBubble),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.large,
                    vertical: AppSpacing.mediumLarge,
                  ),
                ),
                onChanged: (value) => _viewModel.currentQuestion = value,
                onSubmitted: (_) => _sendQuestion(),
              ),
            ),
            const SizedBox(width: AppSpacing.smallMedium),
            IconButton.filled(
              onPressed: canSend ? _sendQuestion : null,
              icon: isQuerying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - RAG Message Bubble

/// Chat bubble widget for a single RAG conversation message.
///
/// User messages: right-aligned blue gradient bubble.
/// Assistant messages: left-aligned gray bubble with timing metrics and
/// expandable retrieved-chunks section.
class _RAGMessageBubble extends StatefulWidget {
  final RAGMessage message;

  const _RAGMessageBubble({required this.message});

  @override
  State<_RAGMessageBubble> createState() => _RAGMessageBubbleState();
}

class _RAGMessageBubbleState extends State<_RAGMessageBubble> {
  bool _showChunks = false;

  bool get _isUser => widget.message.role == RAGMessageRole.user;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.mediumLarge),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Column(
          crossAxisAlignment:
              _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Main bubble
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mediumLarge,
                vertical: AppSpacing.smallMedium,
              ),
              decoration: BoxDecoration(
                gradient: _isUser
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.userBubbleGradientStart,
                          AppColors.userBubbleGradientEnd,
                        ],
                      )
                    : null,
                color: _isUser ? null : AppColors.backgroundGray5(context),
                borderRadius:
                    BorderRadius.circular(AppSpacing.cornerRadiusBubble),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowLight,
                    blurRadius: AppSpacing.shadowSmall,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: _isUser
                  ? Text(
                      widget.message.text,
                      style: AppTypography.body(context).copyWith(
                        color: AppColors.textWhite,
                      ),
                    )
                  : MarkdownBody(
                      data: widget.message.text,
                      styleSheet: MarkdownStyleSheet(
                        p: AppTypography.body(context),
                        code: AppTypography.monospaced.copyWith(
                          backgroundColor:
                              AppColors.backgroundGray6(context),
                        ),
                      ),
                    ),
            ),

            // Timing metrics (assistant only, always visible when result available)
            if (!_isUser && widget.message.result != null)
              _buildTimingMetrics(context, widget.message.result!),

            // Expandable chunks section (assistant only)
            if (!_isUser &&
                widget.message.result != null &&
                widget.message.result!.retrievedChunks.isNotEmpty)
              _buildChunksSection(context, widget.message.result!),
          ],
        ),
      ),
    );
  }

  Widget _buildTimingMetrics(BuildContext context, RAGResult result) {
    final retrievalMs = result.retrievalTimeMs.round();
    final generationS = (result.generationTimeMs / 1000).toStringAsFixed(1);
    final totalS = (result.totalTimeMs / 1000).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xSmall),
      child: Text(
        'Retrieved: ${retrievalMs}ms  Generated: ${generationS}s  Total: ${totalS}s',
        style: AppTypography.caption(context).copyWith(
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }

  Widget _buildChunksSection(BuildContext context, RAGResult result) {
    final count = result.retrievedChunks.length;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.smallMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle button
          GestureDetector(
            onTap: () => setState(() => _showChunks = !_showChunks),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.format_quote,
                  size: AppSpacing.iconRegular,
                  color: AppColors.primaryAccent,
                ),
                const SizedBox(width: AppSpacing.xSmall),
                Text(
                  _showChunks ? 'Hide chunks' : 'Show $count chunk${count == 1 ? '' : 's'}',
                  style: AppTypography.caption(context).copyWith(
                    color: AppColors.primaryAccent,
                  ),
                ),
                Icon(
                  _showChunks
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: AppSpacing.iconRegular,
                  color: AppColors.primaryAccent,
                ),
              ],
            ),
          ),

          // Expanded chunk list
          if (_showChunks) ...[
            const SizedBox(height: AppSpacing.xSmall),
            ...result.retrievedChunks.map(
              (chunk) => _buildChunkCard(context, chunk),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChunkCard(BuildContext context, RAGSearchResult chunk) {
    const maxSnippetLength = 200;
    final snippet = chunk.text.length > maxSnippetLength
        ? '${chunk.text.substring(0, maxSnippetLength)}...'
        : chunk.text;
    final scorePercent =
        (chunk.similarityScore * 100).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xSmall),
      padding: const EdgeInsets.all(AppSpacing.smallMedium),
      decoration: BoxDecoration(
        color: AppColors.backgroundGray6(context),
        borderRadius:
            BorderRadius.circular(AppSpacing.cornerRadiusRegular),
        border: Border.all(
          color: AppColors.borderMedium,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Similarity score badge
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.small,
                  vertical: AppSpacing.xxSmall,
                ),
                decoration: BoxDecoration(
                  color: AppColors.badgeBlue,
                  borderRadius: BorderRadius.circular(
                      AppSpacing.cornerRadiusSmall),
                ),
                child: Text(
                  '$scorePercent%',
                  style: AppTypography.caption2(context).copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxSmall),
          // Chunk text snippet
          Text(
            snippet,
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
