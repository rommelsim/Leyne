// Notifications — arrival-alert preferences.
//
// Now backed by native Android system notifications via
// flutter_local_notifications (lib/services/notifications.dart). The
// toggle drives `AppModel.setNotificationsEnabled`, which requests the
// Android 13+ runtime permission, schedules the in-flight set of
// alerts, and snaps back to off if the user denies.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/notifications.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/atoms.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh the system permission state on every entry — the user may
    // have flipped it from system Settings since we last looked.
    AppModel.shared.refreshNotificationAuth();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: AppModel.shared,
          builder: (context, _) {
            final m = AppModel.shared;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(t, context),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 10),
                        child: MicroLabel('Alerts'),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => m.setNotificationsEnabled(
                              !m.notificationsEnabled),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: t.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: t.line),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            child: Row(
                              children: [
                                Icon(Icons.directions_bus_outlined,
                                    size: 20, color: t.dim),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Arrival alerts',
                                          style: t.sans(14,
                                              weight: FontWeight.w500)),
                                      const SizedBox(height: 2),
                                      Text(
                                        m.notificationsEnabled
                                            ? 'On'
                                            : 'Off',
                                        style: t.mono(11, color: t.dim)
                                            .copyWith(letterSpacing: 0.4),
                                      ),
                                    ],
                                  ),
                                ),
                                LyneToggle(
                                  on: m.notificationsEnabled,
                                  onChanged: m.setNotificationsEnabled,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (m.notificationAuth ==
                              NotifPermStatus.permanentlyDenied ||
                          m.notificationAuth == NotifPermStatus.denied)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: _deniedBanner(t),
                        ),
                      const SizedBox(height: 14),
                      _note(
                        t,
                        Icons.notifications_active_outlined,
                        'A notification fires ~1 minute before a tracked '
                        'bus arrives — on the lock screen, even when '
                        'Leyne is closed.',
                      ),
                      const SizedBox(height: 10),
                      _note(
                        t,
                        Icons.tune,
                        'Fine-tune sound, visibility, and Do Not Disturb '
                        'behavior under Android Settings ▸ Notifications ▸ '
                        'Leyne ▸ Arrival alerts.',
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(LyneTheme t, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left),
            color: t.fg,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text('Notifications',
              style: t.sans(20, weight: FontWeight.w600)
                  .copyWith(letterSpacing: -0.2)),
        ],
      ),
    );
  }

  Widget _deniedBanner(LyneTheme t) {
    return Container(
      decoration: BoxDecoration(
        color: t.warnBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.warn.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: 16, color: t.warn),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications blocked in Android Settings',
                    style: t.sans(13, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Leyne needs notification permission to alert you when a '
                  'bus is nearly here. Re-enable it from the Android '
                  'Settings app.',
                  style: t.mono(11, color: t.dim)
                      .copyWith(height: 1.4, letterSpacing: 0.2),
                ),
                const SizedBox(height: 8),
                _OpenSettingsButton(t: t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(LyneTheme t, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 1),
          child: Icon(icon, size: 14, color: t.faint),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: t.mono(11, color: t.faint)
                  .copyWith(height: 1.5, letterSpacing: 0.3)),
        ),
      ],
    );
  }
}

class _OpenSettingsButton extends StatelessWidget {
  const _OpenSettingsButton({required this.t});
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () => openAppSettings(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: t.accent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text('Open Android Settings',
            style: t.sans(12, color: t.bg, weight: FontWeight.w600)),
      ),
    );
  }
}

