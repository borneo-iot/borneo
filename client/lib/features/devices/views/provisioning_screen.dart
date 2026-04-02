import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/services/devices/ble_provisioner.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';
import 'package:borneo_app/features/devices/models/ble_provision_state.dart';
import 'package:borneo_app/features/devices/providers/new_device_candidates_store.dart';
import 'package:borneo_app/features/devices/view_models/provisioning_wizard_view_model.dart';
import 'package:borneo_app/routes/app_routes.dart';
import 'package:borneo_app/shared/widgets/app_bar_apply_button.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:timelines_plus/timelines_plus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry-point
// ─────────────────────────────────────────────────────────────────────────────

/// A single-page provisioning wizard.
///
/// Returns `{'refresh': true}` via [Navigator.pop] when provisioning succeeds,
/// or `null` otherwise.
class ProvisioningScreen extends StatelessWidget {
  final String deviceName;

  const ProvisioningScreen({super.key, required this.deviceName});

  @override
  Widget build(BuildContext context) {
    final gt = GettextLocalizations.of(context);
    return ChangeNotifierProvider(
      create: (context) => ProvisioningWizardViewModel(
        context.read<IBleProvisioner>(),
        context.read<IDeviceManager>(),
        context.read<NewDeviceCandidatesStore>(),
        deviceName,
        globalEventBus: context.read<EventBus>(),
        gt: gt,
        notificationService: context.read<IAppNotificationService>(),
        logger: context.read<Logger>(),
      )..onInitialize(),
      child: const _ProvisioningScreenBody(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen body
// ─────────────────────────────────────────────────────────────────────────────

class _ProvisioningScreenBody extends StatelessWidget {
  const _ProvisioningScreenBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProvisioningWizardViewModel>();
    // treat as "in progress" only while still within registration countdown
    final provisioning = vm.step == ProvisioningWizardStep.provisioning && vm.registerRemainingSeconds > 0;

    return PopScope(
      // Block the system back gesture while provisioning is in progress.
      canPop: !provisioning,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.translate('Device Setup')),
          // Hide the default back button while provisioning.
          automaticallyImplyLeading: !provisioning,
          actions: [
            if (provisioning)
              AppBarApplyButton(onPressed: () => Navigator.of(context).pop(), label: context.translate('Cancel')),
          ],
        ),
        body: Column(
          children: [
            _WizardTimeline(currentStep: vm.step),
            const Divider(height: 1),
            Expanded(
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                child: _StepContent(vm: vm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline indicator (powered by timelines_plus)
// ─────────────────────────────────────────────────────────────────────────────

class _WizardTimeline extends StatelessWidget {
  final ProvisioningWizardStep currentStep;

  const _WizardTimeline({required this.currentStep});

  // Semantic icon for each step (shown when not yet completed).
  static const _icons = [
    Icons.wifi_find_outlined,
    Icons.lock_outline,
    Icons.wifi_tethering_outlined,
    Icons.check_circle_outline,
  ];

  static const _indicatorSize = 30.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = ProvisioningWizardStep.values.length;
    final currentIndex = currentStep.index;

    // Each step gets an equal Expanded slot containing:
    //   Row( half-connector | indicator | half-connector )
    //   label (single line, centred)
    //
    // Adjacent half-connectors from neighbouring steps share the same colour,
    // so they appear as one continuous line perfectly centred on the indicators.
    // compute translated labels once per build
    final labels = [
      context.translate('Select WiFi'),
      context.translate('Enter Password'),
      context.translate('Provisioning'),
      context.translate('Done'),
    ];

    return IndicatorTheme(
      data: IndicatorThemeData(size: _indicatorSize, color: cs.primary),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(total, (i) {
            final isCompleted = i < currentIndex;
            final isCurrent = i == currentIndex;

            final leftColor = i <= currentIndex ? cs.primary : cs.outlineVariant;
            final rightColor = i < currentIndex ? cs.primary : cs.outlineVariant;

            final Widget indicator = SizedBox(
              width: _indicatorSize,
              height: _indicatorSize,
              child: isCompleted
                  ? DotIndicator(
                      color: cs.primary,
                      child: Icon(Icons.check, size: 16, color: cs.onPrimary),
                    )
                  : isCurrent
                  ? DotIndicator(
                      color: cs.primary,
                      child: Icon(_icons[i], size: 16, color: cs.onPrimary),
                    )
                  : OutlinedDotIndicator(
                      color: cs.outlineVariant,
                      borderWidth: 1.5,
                      child: Icon(_icons[i], size: 14, color: cs.onSurfaceVariant),
                    ),
            );

            return Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : leftColor)),
                      indicator,
                      Expanded(child: Container(height: 2, color: i == total - 1 ? Colors.transparent : rightColor)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // compute labels here so they can be translated
                  Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isCurrent
                          ? cs.primary
                          : (isCompleted ? cs.primary.withValues(alpha: 0.75) : cs.onSurfaceVariant),
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step content dispatcher
// ─────────────────────────────────────────────────────────────────────────────

class _StepContent extends StatelessWidget {
  final ProvisioningWizardViewModel vm;

  const _StepContent({required this.vm});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Align(
        alignment: Alignment.topCenter,
        child: KeyedSubtree(
          key: ValueKey(vm.step),
          child: switch (vm.step) {
            ProvisioningWizardStep.selectWifi => _SelectWifiStep(vm: vm),
            ProvisioningWizardStep.enterPassword => _EnterPasswordStep(vm: vm),
            ProvisioningWizardStep.provisioning => _ProvisioningStep(vm: vm),
            ProvisioningWizardStep.done => _DoneStep(vm: vm),
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 – Select WiFi
// ─────────────────────────────────────────────────────────────────────────────

class _SelectWifiStep extends StatelessWidget {
  final ProvisioningWizardViewModel vm;

  const _SelectWifiStep({required this.vm});

  Icon _wifiIcon(int rssi) {
    if (rssi >= -50) return const Icon(Icons.wifi, color: Colors.green);
    if (rssi >= -70) return const Icon(Icons.wifi_2_bar, color: Colors.yellow);
    if (rssi >= -80) return const Icon(Icons.wifi_1_bar, color: Colors.orange);
    return const Icon(Icons.wifi_1_bar, color: Colors.red);
  }

  @override
  Widget build(BuildContext context) {
    if (vm.isBusy) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vm.networks == null || vm.networks!.isEmpty) {
      return RefreshIndicator(
        onRefresh: vm.scanNetworks,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Center(child: Text(context.translate('No WiFi networks found'))),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: vm.scanNetworks,
                icon: const Icon(Icons.refresh),
                label: Text(context.translate('Refresh')),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: vm.scanNetworks,
      child: ListView.separated(
        itemCount: vm.networks!.length,
        separatorBuilder: (_, idx) => Divider(height: 1, indent: 16, color: Theme.of(context).dividerColor),
        itemBuilder: (context, i) {
          final network = vm.networks![i];
          return ListTile(
            title: Text(network.ssid),
            trailing: _wifiIcon(network.rssi),
            onTap: () => vm.selectNetwork(network.ssid),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 – Enter password
// ─────────────────────────────────────────────────────────────────────────────

class _EnterPasswordStep extends StatefulWidget {
  final ProvisioningWizardViewModel vm;

  const _EnterPasswordStep({required this.vm});

  @override
  State<_EnterPasswordStep> createState() => _EnterPasswordStepState();
}

class _EnterPasswordStepState extends State<_EnterPasswordStep> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ssid = widget.vm.selectedSsid ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // WiFi name indicator
            Row(
              children: [
                const Icon(Icons.wifi, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ssid,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Password field
            TextFormField(
              autofocus: true,
              controller: _passwordController,
              obscureText: _obscure,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                labelText: context.translate('Password'),
                // no explicit border here so the decoration theme (used by
                // other screens such as group_edit_screen) applies consistently
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.translate('Please enter a password');
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.vm.backToWifiSelection,
                    child: Text(context.translate('Back')),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(onPressed: _submit, child: Text(context.translate('Provision'))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.vm.startProvisioning(_passwordController.text);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 3 – Provisioning progress
// ─────────────────────────────────────────────────────────────────────────────

class _ProvisioningStep extends StatelessWidget {
  final ProvisioningWizardViewModel vm;

  const _ProvisioningStep({required this.vm});

  static const _progressSteps = [
    (BleProvisioningState.sendingCredentials, 'Sending Credentials'),
    (BleProvisioningState.connectingToWifi, 'Connecting to WiFi'),
    (BleProvisioningState.registeringDevice, 'Registering Device'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.wifi_tethering_outlined, size: 96, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 32),
          ..._progressSteps.map((entry) => _buildProgressRow(context, entry.$1, entry.$2)),
          if (vm.provisioningState == BleProvisioningState.registeringDevice) ...[
            const SizedBox(height: 24),
            Text(
              vm.registerRemainingSeconds > 0
                  ? context.translate('Time remaining: {0} seconds', pArgs: [vm.registerRemainingSeconds])
                  : context.translate('Waiting for device to join network'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressRow(BuildContext context, BleProvisioningState step, String label) {
    final cs = Theme.of(context).colorScheme;
    final state = vm.provisioningState;
    final isCompleted = state.index > step.index || state == BleProvisioningState.success;
    final isCurrent = state == step;
    final isPending = state.index < step.index;

    final Widget icon;
    if (isCompleted) {
      icon = Icon(Icons.check_circle_outline, color: cs.primary);
    } else if (isCurrent) {
      icon = SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary));
    } else {
      icon = Icon(Icons.radio_button_unchecked, color: cs.onSurface.withValues(alpha: 0.38));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 24, height: 24, child: Center(child: icon)),
          const SizedBox(width: 16),
          Text(
            context.translate(label),
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isPending ? cs.onSurface.withValues(alpha: 0.38) : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 4 – Done (success or failure)
// ─────────────────────────────────────────────────────────────────────────────

class _DoneStep extends StatefulWidget {
  final ProvisioningWizardViewModel vm;

  const _DoneStep({required this.vm});

  @override
  State<_DoneStep> createState() => _DoneStepState();
}

class _DoneStepState extends State<_DoneStep> {
  @override
  void initState() {
    super.initState();
    // all business logic lives in the ViewModel; nothing to subscribe here
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final succeeded = widget.vm.provisioningSucceeded;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(succeeded ? Icons.check_circle : Icons.error, size: 72, color: succeeded ? cs.primary : cs.error),
          const SizedBox(height: 24),
          Text(
            succeeded
                ? context.translate('Provisioning Successful!')
                : (widget.vm.errorMessage ?? context.translate('Unknown Error')),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: succeeded ? null : cs.error),
          ),
          const SizedBox(height: 32),
          if (succeeded) ...[
            if (!widget.vm.autoAdded) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                  const SizedBox(width: 12),
                  Text(context.translate('Adding device to your list...')),
                ],
              ),
              const SizedBox(height: 24),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (widget.vm.autoAdded || widget.vm.registerRemainingSeconds <= 0)
                    ? () {
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.settings.name == AppRoutes.kDevices || route.isFirst);
                      }
                    : null,
                label: Text(context.translate('Done')),
              ),
            ),
            if (!widget.vm.autoAdded && widget.vm.registerRemainingSeconds <= 0) ...[
              const SizedBox(height: 12),
              Text(
                context.translate('You can finish now without waiting.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.translate('Close'))),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: widget.vm.retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.translate('Retry')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
