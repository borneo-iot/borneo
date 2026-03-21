import 'package:borneo_app/devices/view_models/device_ota_view_model.dart';
import 'package:borneo_app/shared/widgets/confirmation_sheet.dart';
import 'package:borneo_app/shared/widgets/buttons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:provider/provider.dart';

/// OTA firmware update screen.
///
/// Pass an already-constructed [DeviceOtaViewModel] whose [initialize] method
/// will be called once in [initState].
class DeviceOtaScreen extends StatefulWidget {
  final DeviceOtaViewModel vm;
  const DeviceOtaScreen(this.vm, {super.key});

  @override
  State<DeviceOtaScreen> createState() => _DeviceOtaScreenState();
}

class _DeviceOtaScreenState extends State<DeviceOtaScreen> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    widget.vm.initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // Confirm upgrade dialog
  // -----------------------------------------------------------------------
  Future<bool> _confirmUpgrade(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(context.translate('Firmware Update')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.translate('Before proceeding, please read the following warnings carefully:'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _WarningItem(
                icon: Icons.power,
                text: context.translate(
                  'Do NOT power off the device during the update. Interrupting power may permanently damage the device.',
                ),
              ),
              const SizedBox(height: 8),
              _WarningItem(
                icon: Icons.wifi,
                text: context.translate('Keep the device connected to your network throughout the update.'),
              ),
              const SizedBox(height: 8),
              _WarningItem(
                icon: Icons.timer,
                text: context.translate('The update may take several minutes. Do not close this app.'),
              ),
              const SizedBox(height: 8),
              _WarningItem(
                icon: Icons.refresh,
                text: context.translate('The device will restart automatically after the update is complete.'),
              ),
              const SizedBox(height: 16),
              Text(
                context.translate('Do you want to start the firmware update now?'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(context.translate('Cancel'))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(context.translate('Update Now'))),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DeviceOtaViewModel>.value(
      value: widget.vm,
      child: Consumer<DeviceOtaViewModel>(
        builder: (context, vm, _) {
          return PopScope(
            canPop: !vm.isUpgrading,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              // vm.isUpgrading is true here, ask user to confirm abort
              final confirmed = await AsyncConfirmationSheet.show(
                context,
                message: context.translate(
                  'Firmware update is in progress. Interrupting the update may permanently damage the device. Are you sure you want to abort?',
                ),
              );
              if (confirmed) {
                vm.cancelUpgrade();
              }
            },
            child: Scaffold(
              appBar: AppBar(
                title: Text(context.translate('Firmware Update')),
                automaticallyImplyLeading: !vm.isUpgrading,
              ),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              const SizedBox(height: 24),
                              _buildStatusIcon(context, vm),
                              const SizedBox(height: 24),
                              _buildStatusText(context, vm),
                              const SizedBox(height: 32),
                              _buildVersionCard(context, vm),
                              if (vm.isUpgrading) ...[const SizedBox(height: 32), _buildProgressSection(context, vm)],
                              if (vm.isError) ...[const SizedBox(height: 16), _buildErrorCard(context, vm)],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildActionButton(context, vm),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Status icon
  // -----------------------------------------------------------------------
  Widget _buildStatusIcon(BuildContext context, DeviceOtaViewModel vm) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (vm.state) {
      case OtaState.idle:
      case OtaState.checking:
        return SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(strokeWidth: 3, color: colorScheme.primary.withValues(alpha: 0.4)),
              ),
              Icon(Icons.system_update_alt, size: 52, color: colorScheme.primary),
            ],
          ),
        );

      case OtaState.upToDate:
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (ctx, v, _) => Transform.scale(
            scale: v,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.withValues(alpha: 0.12)),
              child: const Icon(Icons.check_circle, size: 68, color: Colors.green),
            ),
          ),
        );

      case OtaState.updateAvailable:
        return ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.primary.withValues(alpha: 0.12)),
            child: Icon(Icons.system_update, size: 68, color: colorScheme.primary),
          ),
        );

      case OtaState.upgrading:
        return SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  strokeWidth: 5,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: colorScheme.primary,
                ),
              ),
              Icon(Icons.system_update_alt, size: 40, color: colorScheme.primary),
            ],
          ),
        );

      case OtaState.success:
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 700),
          curve: Curves.elasticOut,
          builder: (ctx, v, _) => Transform.scale(
            scale: v,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.withValues(alpha: 0.12)),
              child: const Icon(Icons.check_circle, size: 68, color: Colors.green),
            ),
          ),
        );

      case OtaState.error:
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (ctx, v, _) => Transform.scale(
            scale: v,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orange.withValues(alpha: 0.12)),
              child: const Icon(Icons.error_outline, size: 68, color: Colors.orange),
            ),
          ),
        );
    }
  }

  // -----------------------------------------------------------------------
  // Status text
  // -----------------------------------------------------------------------
  Widget _buildStatusText(BuildContext context, DeviceOtaViewModel vm) {
    String title;
    String subtitle;
    switch (vm.state) {
      case OtaState.idle:
        title = context.translate('Firmware Update');
        subtitle = '';
      case OtaState.checking:
        title = context.translate('Checking for updates...');
        subtitle = context.translate('Fetching the latest firmware information from the server.');
      case OtaState.upToDate:
        title = context.translate('Your firmware is up to date');
        subtitle = vm.upgradeInfo != null
            ? context.translate('Version {0} is the latest version.', pArgs: [vm.upgradeInfo!.localVersion.toString()])
            : '';
      case OtaState.updateAvailable:
        title = context.translate('New firmware available');
        subtitle = vm.upgradeInfo != null
            ? context.translate(
                'Version {0} is available. Tap the button below to update.',
                pArgs: [vm.upgradeInfo!.remoteVersion.toString()],
              )
            : '';
      case OtaState.upgrading:
        title = context.translate('Updating firmware...');
        subtitle = context.translate('Please keep the device powered on and connected to the network.');
      case OtaState.success:
        title = context.translate('Update successful!');
        subtitle = context.translate('The device has been updated and will restart shortly.');
      case OtaState.error:
        title = context.translate('Update failed');
        subtitle = context.translate('An error occurred. Please retry or contact support.');
    }
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Version info card
  // -----------------------------------------------------------------------
  Widget _buildVersionCard(BuildContext context, DeviceOtaViewModel vm) {
    final info = vm.upgradeInfo;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            _VersionRow(
              label: context.translate('Current version'),
              value: info != null ? info.localVersion.toString() : context.translate('Unknown'),
              valueColor: vm.hasUpdate || vm.isUpgrading || vm.isSucceeded
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurface,
            ),
            if (info != null && (vm.hasUpdate || vm.isUpgrading || vm.isSucceeded)) ...[
              const Divider(height: 16),
              _VersionRow(
                label: context.translate('New version'),
                value: info.remoteVersion.toString(),
                valueColor: colorScheme.primary,
                bold: true,
              ),
              const Divider(height: 16),
              _VersionRow(label: context.translate('Release date'), value: _formatDate(info.remoteTime)),
            ],
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Progress section (shown during upgrade)
  // -----------------------------------------------------------------------
  Widget _buildProgressSection(BuildContext context, DeviceOtaViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // the circular indicator already shows progress, so
        // we drop the horizontal bar and just keep the label/percent
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.translate('Do not power off the device or close this app.'),
                  style: const TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Error detail card
  // -----------------------------------------------------------------------
  Widget _buildErrorCard(BuildContext context, DeviceOtaViewModel vm) {
    final msg = vm.errorMessage ?? context.translate('Unknown error');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(msg, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 12)),
    );
  }

  // -----------------------------------------------------------------------
  // Action button
  // -----------------------------------------------------------------------
  Widget _buildActionButton(BuildContext context, DeviceOtaViewModel vm) {
    if (vm.isUpgrading) {
      return SizedBox(
        width: double.infinity,
        child: FilledButtonDanger.danger(
          context: context,
          onPressed: () async {
            final confirmed = await AsyncConfirmationSheet.show(
              context,
              message: context.translate(
                'Firmware update is in progress. Interrupting the update may permanently damage the device. Are you sure you want to cancel?',
              ),
            );
            if (confirmed) {
              vm.cancelUpgrade();
            }
          },
          child: Text(context.translate('Cancel')),
        ),
      );
    }

    if (vm.isSucceeded) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.check),
          label: Text(context.translate('Done')),
        ),
      );
    }

    if (vm.hasUpdate) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () async {
            final ok = await _confirmUpgrade(context);
            if (ok && context.mounted) {
              await vm.startUpgrade();
            }
          },
          icon: const Icon(Icons.system_update),
          label: Text(context.translate('Upgrade to {0}', pArgs: [vm.upgradeInfo!.remoteVersion.toString()])),
        ),
      );
    }

    // Default: check / retry
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: vm.canCheck ? () => vm.checkUpdate() : null,
            icon: const Icon(Icons.refresh),
            label: Text(
              vm.isChecking
                  ? context.translate('Checking...')
                  : vm.isError
                  ? context.translate('Retry')
                  : context.translate('Check for updates'),
            ),
          ),
        ),
        if (kDebugMode && vm.canForceUpgrade) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5)),
              ),
              onPressed: () async {
                final ok = await _confirmUpgrade(context);
                if (ok && context.mounted) {
                  await vm.startUpgrade(force: true);
                }
              },
              icon: const Icon(Icons.bug_report),
              label: Text(context.translate('[Debug] Force Update')),
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

class _WarningItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _WarningItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.orange),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const _VersionRow({required this.label, required this.value, this.valueColor, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: valueColor, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        ),
      ],
    );
  }
}
