import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../widgets/common.dart';

/// Household sync — pairing UI. One phone hosts (shows IP + invitation code),
/// the other joins; both merge. Styled like the rest of More (drow/mcard).
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});
  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _addrCtl = TextEditingController();
  final _codeCtl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _addrCtl.dispose();
    _codeCtl.dispose();
    // leaving the screen stops hosting — the server shouldn't linger
    ref.read(householdSyncProvider).stopHost();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final l = L.of(context);
    final ui = ref.watch(uiProvider);
    final sync = ref.watch(householdSyncProvider);
    final settings = settingsOf(ref);
    final hasPair = settings['pair'] is Map;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 130,
              child: Btn(l.back, kind: 'ghost', margin: EdgeInsets.zero,
                  onTap: () => ui.setTab('more')),
            ),
          ),
        ),
        Enter(
          index: 0,
          child: AppCard(
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(13)),
                child: Icon(Icons.sync_rounded, size: 20, color: t.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l.xSyncSub,
                    style:
                        TextStyle(fontSize: 12.5, color: t.ink2, height: 1.5)),
              ),
            ]),
          ),
        ),
        // ---- host side ----
        Enter(
          index: 1,
          child: AppCard(
            child:
                m.Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!sync.hosting)
                Btn(l.xSyncHostBtn, kind: 'ghost', margin: EdgeInsets.zero,
                    onTap: () async {
                  await ref.read(householdSyncProvider).startHost();
                })
              else ...[
                Text(l.xSyncHostHint,
                    style: TextStyle(fontSize: 12.5, color: t.ink2)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: t.surface2,
                      border: Border.all(color: t.accent),
                      borderRadius: BorderRadius.circular(14)),
                  child: m.Column(children: [
                    for (final a in sync.addresses)
                      Text('$a:8765',
                          style: TextStyle(
                              fontFamily: 'Unbounded',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: t.ink)),
                    const SizedBox(height: 8),
                    Text(sync.code ?? '',
                        style: TextStyle(
                            fontFamily: 'Unbounded',
                            fontSize: 26,
                            letterSpacing: 6,
                            fontWeight: FontWeight.w700,
                            color: t.accent)),
                  ]),
                ),
                if (sync.status.startsWith('ok:'))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Center(
                      child: Text('✓ ${l.synced}',
                          style: TextStyle(
                              color: t.income,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5)),
                    ),
                  ),
                Btn(l.xSyncStopBtn, kind: 'ghost',
                    onTap: () => ref.read(householdSyncProvider).stopHost()),
              ],
            ]),
          ),
        ),
        // ---- join side ----
        Enter(
          index: 2,
          child: AppCard(
            child:
                m.Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Fld(l.xSyncAddr,
                  child: AppInput(
                      controller: _addrCtl, placeholder: '192.168.1.5')),
              Fld(l.xSyncCode,
                  child: AppInput(
                      controller: _codeCtl,
                      placeholder: 'ABC123',
                      textAlign: TextAlign.center)),
              Btn(_busy ? '…' : l.xSyncJoinBtn, margin: EdgeInsets.zero,
                  onTap: _busy
                      ? null
                      : () => _run(() => ref
                          .read(householdSyncProvider)
                          .joinAndSync(_addrCtl.text.trim(), _codeCtl.text))),
              if (hasPair)
                Btn(l.xSyncAgainBtn, kind: 'ghost',
                    onTap: _busy
                        ? null
                        : () => _run(() async {
                              final pair = settings['pair'] as Map;
                              return ref.read(householdSyncProvider).joinAndSync(
                                  pair['host'] as String,
                                  pair['key'] as String);
                            })),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(l.xSyncWhat,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: t.ink3, height: 1.5)),
        ),
      ],
    );
  }

  Future<void> _run(
      Future<({int sent, int applied})> Function() fn) async {
    final l = L.of(context);
    setState(() => _busy = true);
    try {
      final r = await fn();
      if (mounted) {
        ToastHost.show(context, l.xSyncDone('${r.applied}', '${r.sent}'));
      }
    } catch (_) {
      if (mounted) ToastHost.show(context, l.xSyncFail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
