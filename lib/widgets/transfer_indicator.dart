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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TransferManager.instance,
      builder: (context, _) {
        final manager = TransferManager.instance;
        final items = manager.items;
        if (items.isEmpty) return const SizedBox.shrink();

        final active = manager.activeItems;
        final completed = items.where((item) => item.status.isFinalState).length;

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            children: [
              ListTile(
                dense: true,
                leading: Icon(
                  active.any((item) => item.type == 'upload')
                      ? Icons.cloud_upload_outlined
                      : Icons.cloud_download_outlined,
                ),
                title: Text(
                  active.isEmpty
                      ? '$completed transfer(s) finished'
                      : '${active.length} transfer(s) active',
                ),
                subtitle: active.isEmpty
                    ? const Text('Transfers are complete.')
                    : Text(active.map((item) => item.filename).join(', ')),
                trailing: IconButton(
                  icon: const Icon(Icons.open_in_new),
                  tooltip: 'Transfers',
                  onPressed: () => _showTransfers(context),
                ),
              ),
              for (final item in active.take(3))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            item.type == 'upload'
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('${(item.progress * 100).round()}%'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: item.progress),
                      const SizedBox(height: 3),
                      Text(_status(item.status), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
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
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: manager,
          builder: (context, _) {
            final items = manager.items;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Transfers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      TextButton(
                        onPressed: manager.dismissFinished,
                        child: const Text('Clear finished'),
                      ),
                    ],
                  ),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No transfers.')),
                    )
                  else
                    ...items.map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(item.type == 'upload' ? Icons.upload : Icons.download),
                        title: Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: item.progress),
                            const SizedBox(height: 3),
                            Text('${(item.progress * 100).round()}% • ${_status(item.status)}'),
                          ],
                        ),
                        trailing: item.status.isFinalState
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => manager.cancel(item.taskId),
                              ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
