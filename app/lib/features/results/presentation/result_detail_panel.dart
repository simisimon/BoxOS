import 'dart:convert';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/block_leaderboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// A result with its photo, fist bumps and comments. [workoutId] is the
/// WOD whose leaderboard to refresh after a change.
Future<void> showResultDetailPanel(
  BuildContext context, {
  required int resultId,
  int? workoutId,
}) {
  return showAppSidePanel<void>(
    context,
    builder: (_) => ResultDetailPanel(resultId: resultId, workoutId: workoutId),
  );
}

class ResultDetailPanel extends ConsumerStatefulWidget {
  const ResultDetailPanel({super.key, required this.resultId, this.workoutId});

  final int resultId;
  final int? workoutId;

  @override
  ConsumerState<ResultDetailPanel> createState() => _ResultDetailPanelState();
}

class _ResultDetailPanelState extends ConsumerState<ResultDetailPanel> {
  final _comment = TextEditingController();
  final _picker = ImagePicker();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(resultDetailProvider(widget.resultId));
    final workoutId = widget.workoutId;
    if (workoutId != null) ref.invalidate(leaderboardProvider(workoutId));
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      _refresh();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: failure))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    await _run(() async {
      await ref
          .read(resultsRepositoryProvider)
          .addComment(widget.resultId, text);
      _comment.clear();
    }, 'Could not post the comment.');
  }

  Future<void> _deleteComment(ResultComment comment) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete this comment?',
      message: '"${comment.body}" by ${comment.name} is removed for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(resultsRepositoryProvider).deleteComment(comment.id),
      'Could not delete the comment.',
    );
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    final name = picked.name.toLowerCase();
    final contentType = switch (picked.mimeType) {
      final type? when type.trim().isNotEmpty => type,
      _ when name.endsWith('.png') => 'image/png',
      _ when name.endsWith('.webp') => 'image/webp',
      _ => 'image/jpeg',
    };
    await _run(
      () => ref
          .read(resultsRepositoryProvider)
          .uploadPhoto(
            widget.resultId,
            filename: picked.name,
            contentType: contentType,
            dataBase64: base64Encode(bytes),
          ),
      'Could not upload the photo.',
    );
  }

  Future<void> _removePhoto(ResultDetail result) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Remove the photo?',
      message: result.isMe
          ? 'The photo is taken off your result.'
          : 'The photo is taken off ${result.name}\'s result.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(resultsRepositoryProvider).removePhoto(widget.resultId),
      'Could not remove the photo.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(resultDetailProvider(widget.resultId));
    final result = detail.value;
    final localizations = MaterialLocalizations.of(context);
    return AppSidePanel(
      title: result?.name ?? 'Result',
      subtitle: result == null
          ? null
          : '${result.title} · ${localizations.formatMediumDate(result.performedOn)}',
      child: result == null
          ? detail.hasError
                ? const Text(
                    'Could not load the result.',
                    style: TextStyle(color: appDanger),
                  )
                : const LinearProgressIndicator()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      result.scoreLabel,
                      style: const TextStyle(
                        color: appText,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: appSpaceSm),
                    AppPill(
                      label: result.division == ResultDivision.rx
                          ? 'Rx'
                          : 'Scaled',
                      intent: AppPillIntent.neutral,
                      dense: true,
                    ),
                    const Spacer(),
                    FistBumpButton(
                      key: const ValueKey('detail-bump'),
                      count: result.bumpCount,
                      bumped: result.bumpedByMe,
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => ref
                                  .read(resultsRepositoryProvider)
                                  .setBump(
                                    widget.resultId,
                                    bumped: !result.bumpedByMe,
                                  ),
                              'Could not send the fist bump.',
                            ),
                    ),
                  ],
                ),
                if (result.bumpedBy.isNotEmpty) ...[
                  const SizedBox(height: appSpaceXs),
                  Text(
                    'Fist bumps from ${result.bumpedBy.join(', ')}',
                    style: const TextStyle(color: appSubtleText, fontSize: 12),
                  ),
                ],
                if (result.notes.isNotEmpty) ...[
                  const SizedBox(height: appSpaceMd),
                  Text(
                    result.notes,
                    style: const TextStyle(color: appMutedText, height: 1.4),
                  ),
                ],
                const SizedBox(height: appSpaceLg),
                _Photo(
                  result: result,
                  busy: _busy,
                  onPick: _pickPhoto,
                  onRemove: () => _removePhoto(result),
                ),
                const SizedBox(height: appSpaceLg),
                Text('COMMENTS', style: appMono(fontSize: 10)),
                const SizedBox(height: appSpaceSm),
                if (result.comments.isEmpty)
                  const Text(
                    'No comments yet.',
                    style: TextStyle(color: appSubtleText, fontSize: 13),
                  ),
                for (final comment in result.comments)
                  _CommentRow(
                    comment: comment,
                    onDelete: comment.canDelete
                        ? () => _deleteComment(comment)
                        : null,
                  ),
                const SizedBox(height: appSpaceSm),
                TextField(
                  key: const ValueKey('result-comment'),
                  controller: _comment,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Write a comment',
                    suffixIcon: IconButton(
                      tooltip: 'Send',
                      onPressed: _busy ? null : _send,
                      icon: const Icon(Icons.send_rounded, size: 18),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({
    required this.result,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final ResultDetail result;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final url = AppAvatar.resolveUrl(result.photoUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (url != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(appRadiusLg),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    'Could not load the photo.',
                    style: TextStyle(color: appSubtleText),
                  ),
                ),
              ),
            ),
          ),
        if (result.canEditPhoto || result.canRemovePhoto)
          OverflowBar(
            alignment: MainAxisAlignment.start,
            spacing: appSpaceSm,
            children: [
              if (result.canEditPhoto)
                TextButton.icon(
                  onPressed: busy ? null : onPick,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(url == null ? 'Add photo' : 'Change photo'),
                ),
              if (result.canRemovePhoto)
                TextButton.icon(
                  onPressed: busy ? null : onRemove,
                  style: TextButton.styleFrom(foregroundColor: appDanger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remove photo'),
                ),
            ],
          ),
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, this.onDelete});

  final ResultComment comment;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: appSpaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(
            displayName: comment.name,
            imageUrl: comment.avatarUrl.isEmpty ? null : comment.avatarUrl,
            size: 28,
          ),
          const SizedBox(width: appSpaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.name,
                  style: const TextStyle(
                    color: appText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  comment.body,
                  style: const TextStyle(color: appMutedText, height: 1.4),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete comment',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: appSubtleText,
              ),
            ),
        ],
      ),
    );
  }
}
