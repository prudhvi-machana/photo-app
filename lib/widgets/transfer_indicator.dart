import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

import '../services/transfer_manager.dart';

class TransferIndicator extends StatelessWidget {
  const TransferIndicator({super.key});

  String _status(TaskStatus status) {
    switch (status) {
      case TaskStatus.running:
        return 'Transferring';
      case TaskStatus.enqueued:
        return 'Waiting';
      case TaskStatus.paused:
        return 'Paused';
      case TaskStatus.waitingToRetry:
        return 'Retrying';
      case TaskStatus.complete:
        return 'Complete';
      case TaskStatus.failed:
        return 'Failed';
      case TaskStatus.canceled:
        return 'Canceled';
      default:
        return status.name;
    }
  }

  String _size(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TransferManager.instance,
      builder: (context, _) {
        final manager = TransferManager.instance;
        final active = manager.activeItems;
        if (active.isEmpty) return const SizedBox.shrink();

        final first = active.first;
        final percent = (first.progress * 100).round();
        final suffix = active.length > 1 ? ' +${active.length - 1}' : '';

        return Positioned(
          right: 16,
          bottom: 20,
          child: SafeArea(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(28),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () => _showTransfers(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(value: first.progress, strokeWidth: 3),
                      ),
                      const SizedBox(width: 10),
                      Icon(first.type == 'upload' ? Icons.cloud_upload_outlined : Icons.cloud_download_outlined, size: 20),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text('${first.filename} • $percent%$suffix', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTransfers(BuildContext context) {
    final manager = TransferManager.instance;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: ListenableBuilder(
            listenable: manager,
            builder: (context, _) {
              final items = manager.items;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Transfers', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                        if (items.any((item) => item.status.isFinalState))
                          TextButton(onPressed: manager.dismissFinished, child: const Text('Clear finished')),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text('No transfers'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final transferred = _size(item.transferredBytes);
                              final total = _size(item.totalBytes);
                              final progressText = total.isEmpty ? '${(item.progress * 100).round()}%' : '$transferred / $total';
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(item.type == 'upload' ? Icons.arrow_upward : Icons.arrow_downward),
                                          const SizedBox(width: 10),
                                          Expanded(child: Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                                          Text('${(item.progress * 100).round()}%'),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      LinearProgressIndicator(value: item.progress),
                                      const SizedBox(height: 7),
                                      Row(
                                        children: [
                                          Expanded(child: Text('$progressText • ${_status(item.status)}', style: Theme.of(context).textTheme.bodySmall)),
                                          if (!item.status.isFinalState)
                                            IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: () => manager.cancel(item.taskId)),
                                        ],
                                      ),
                                      if (item.error != null) Text(item.error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
