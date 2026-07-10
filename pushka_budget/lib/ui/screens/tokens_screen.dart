import 'package:flutter/material.dart' hide Column;
import 'package:flutter/material.dart' as m show Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/months.dart';
import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../state.dart';
import '../util.dart';
import '../widgets/common.dart';

/// NEW screen (required by the port): manage Monobank personal tokens.
/// Tokens live in flutter_secure_storage (Android Keystore); this screen
/// only ever shows the owner label, never the token value after saving.
/// Visual language matches More: drow-style rows, mcard chrome, В/А badges.
class TokensScreen extends ConsumerWidget {
  const TokensScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tk(context);
    final l = L.of(context);
    final ui = ref.watch(uiProvider);
    final settings = settingsOf(ref);
    final locale = localeOf(settings);
    final tokens = ref.watch(tokensProvider).value ?? const <MonoToken>[];

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
                child: Icon(Icons.vpn_key_rounded, size: 20, color: t.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l.xTokensSub,
                    style:
                        TextStyle(fontSize: 12.5, color: t.ink2, height: 1.5)),
              ),
            ]),
          ),
        ),
        if (tokens.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            child: Text(l.xNoTokens,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.ink3, fontSize: 14, height: 1.6)),
          ),
        for (final (i, tok) in tokens.indexed)
          Enter(
            index: i + 1,
            child: Press(
              onTap: () => _editSheet(context, ref, tok),
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  OwnerBadge(
                      tok.ownerKey,
                      tok.ownerKey == 'vadim'
                          ? 'В'
                          : tok.ownerKey == 'alisa'
                              ? 'А'
                              : tok.label.isNotEmpty
                                  ? tok.label[0].toUpperCase()
                                  : '?'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: m.Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tok.label,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: t.ink)),
                          const SizedBox(height: 2),
                          Text(
                              '${l.xLastSync}: ${tok.lastSyncedAt > 0 ? fmtDayMonth(DateTime.fromMillisecondsSinceEpoch(tok.lastSyncedAt * 1000), locale) : l.xNever}',
                              style: TextStyle(
                                  fontSize: 12, color: t.ink3)),
                        ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: t.ink3),
                ]),
              ),
            ),
          ),
        Btn('＋ ${l.xTokenAdd}', onTap: () => _addSheet(context, ref)),
        Btn(l.xSyncNow, kind: 'ghost', onTap: () async {
          ToastHost.show(context, l.syncing);
          final res = await runForegroundSync(ref);
          if (!context.mounted || res == null) return;
          ToastHost.show(
              context,
              res.errors.isNotEmpty && res.newTx == 0
                  ? l.syncErr
                  : l.xSyncedN('${res.newTx}'));
        }),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(l.xBackfillNote,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: t.ink3)),
        ),
        // ---- AI categorization key (same vault policy as bank tokens) ----
        SecH(l.xAiSection),
        AppCard(
          child: _AiKeyRow(),
        ),
      ],
    );
  }

  Future<void> _addSheet(BuildContext context, WidgetRef ref) async {
    final l = L.of(context);
    final vault = ref.read(vaultProvider);
    final labelCtl = TextEditingController();
    final tokenCtl = TextEditingController();

    await showAppSheet(
      context,
      Builder(builder: (context) {
        final t = tk(context);
        return m.Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetTitle(l.xTokenAdd),
              SheetMeta(l.xTokenHint),
              Fld(l.xTokenLabel,
                  child: AppInput(
                      controller: labelCtl, placeholder: l.xTokenLabelPh)),
              Fld(l.xTokenValue,
                  child: AppInput(controller: tokenCtl, obscure: true)),
              Btn(l.save, onTap: () async {
                final label = labelCtl.text.trim();
                final token = tokenCtl.text.trim();
                if (label.isEmpty || token.isEmpty) {
                  ToastHost.show(context, l.xNeedNameAmount);
                  return;
                }
                // owner keys 'vadim'/'alisa' keep legacy badge/credit logic
                final slug = _slugOwner(label);
                await vault.add(token: token, ownerKey: slug, label: label);
                if (!context.mounted) return;
                Navigator.pop(context);
                ToastHost.show(context, l.xTokenAdded);
                await runForegroundSync(ref);
              }),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l.xBackfillNote,
                    style: TextStyle(fontSize: 11.5, color: t.ink3)),
              ),
            ]);
      }),
    );
  }

  Future<void> _editSheet(
      BuildContext context, WidgetRef ref, MonoToken tok) async {
    final l = L.of(context);
    final vault = ref.read(vaultProvider);
    final labelCtl = TextEditingController(text: tok.label);

    await showAppSheet(
      context,
      Builder(builder: (context) {
        final t = tk(context);
        return m.Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetTitle(tok.label),
              Fld(l.xTokenLabel, child: AppInput(controller: labelCtl)),
              Btn(l.save, onTap: () async {
                final label = labelCtl.text.trim();
                if (label.isEmpty) return;
                // renaming keeps the owner key stable so history attribution
                // doesn't shift — only the display label changes
                await vault.rename(tok.id,
                    ownerKey: tok.ownerKey, label: label);
                if (!context.mounted) return;
                Navigator.pop(context);
                ToastHost.show(context, l.saved);
              }),
              Btn(l.xTokenRemove, kind: 'danger', onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: t.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    content: Text(l.xTokenRemoveQ(tok.label),
                        style: TextStyle(color: t.ink, fontSize: 14.5)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l.xCancel,
                              style: TextStyle(color: t.ink2))),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l.deleteBtn,
                              style: TextStyle(
                                  color: t.expense,
                                  fontWeight: FontWeight.w700))),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                await vault.remove(tok.id);
                if (!context.mounted) return;
                Navigator.pop(context);
                ToastHost.show(context, l.deleted);
              }),
            ]);
      }),
    );
  }
}

/// Anthropic key row — powers «✨ AI-розкидати» (local replacement of the
/// worker's /ai-categorize; the key lives in flutter_secure_storage).
class _AiKeyRow extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AiKeyRow> createState() => _AiKeyRowState();
}

class _AiKeyRowState extends ConsumerState<_AiKeyRow> {
  final _ctl = TextEditingController();
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    ref.read(aiServiceProvider).configured.then((v) {
      if (mounted) setState(() => _configured = v);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final l = L.of(context);
    return m.Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Fld('${l.xAiKeyLabel}${_configured ? ' · ✓' : ''}',
          child: AppInput(
              controller: _ctl,
              placeholder: _configured ? '••••••••' : 'sk-ant-…',
              obscure: true)),
      Text(l.xAiKeyHint, style: TextStyle(fontSize: 11.5, color: t.ink3)),
      Btn(l.save, onTap: () async {
        await ref.read(aiServiceProvider).setKey(_ctl.text);
        final on = _ctl.text.trim().isNotEmpty;
        _ctl.clear();
        if (mounted) {
          setState(() => _configured = on);
          ToastHost.show(context, on ? l.xAiKeySaved : l.xAiKeyRemoved);
        }
      }),
    ]);
  }
}

/// Owner label → stable owner key. «Вадім»/“Vadim” → 'vadim',
/// «Аліса»/“Alisa” → 'alisa' (preserves the per-person badge & credit logic);
/// anything else becomes its own lowercase key.
String _slugOwner(String label) {
  final low = label.toLowerCase();
  if (low.startsWith('вадім') || low.startsWith('вадим') || low.startsWith('vadim')) {
    return 'vadim';
  }
  if (low.startsWith('аліса') || low.startsWith('алиса') || low.startsWith('alisa')) {
    return 'alisa';
  }
  return low.replaceAll(RegExp(r'\s+'), '_');
}
