// Notifications — arrival-alert preferences.
//
// v1 delivers in-app alerts: while Leyne is open, a banner appears as a
// pinned bus gets close. Background (app-closed) delivery needs an OS
// notification channel and is on the roadmap — the screen is honest about
// that so the toggle never over-promises.

import 'package:flutter/material.dart';

import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/atoms.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

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
                      const SizedBox(height: 14),
                      _note(
                        t,
                        Icons.bolt_outlined,
                        'While Leyne is open, you’ll get a heads-up the moment '
                        'a pinned bus is about a minute from its stop.',
                      ),
                      const SizedBox(height: 10),
                      _note(
                        t,
                        Icons.schedule_outlined,
                        'Background alerts — buzzing you with the app closed — '
                        'are on the roadmap and need an OS notification '
                        'channel. They’re not active yet.',
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
