import 'package:flutter/material.dart';

import 'account.dart';
import 'connectors.dart';
import 'theme.dart';
import 'ui.dart';

/// Checks a typed address against the source registry without ever visiting it.
String reviewAddress(String raw, List<SourceConnector> connectors) {
  final text = raw.trim();
  if (text.isEmpty) return 'Type a website address first.';
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  final host = uri?.host.toLowerCase() ?? '';
  if (uri == null || host.isEmpty || !host.contains('.') || (uri.scheme != 'https' && uri.scheme != 'http')) return 'That doesn\'t look like a website address.';
  if (uri.userInfo.isNotEmpty) return 'Addresses with a login inside them aren\'t allowed.';
  final numeric = RegExp(r'^[\d.]+$').hasMatch(host) || host.contains(':');
  if (numeric || host == 'localhost' || host.endsWith('.local') || host.endsWith('.internal')) return 'Private and numeric addresses aren\'t allowed.';
  for (final c in connectors) {
    if (c.domains.any((d) => host == d || host.endsWith('.$d'))) {
      return c is ReviewedConnector ? '${c.name} is reviewed and unavailable. ${c.reason}' : '${c.name} is already connected.';
    }
  }
  return '$host hasn\'t been reviewed, so it isn\'t connected. Vortex adds a source once it has an official way in and the rights to its anime.';
}

class SourcesScreen extends StatefulWidget {
  final Account account;

  const SourcesScreen({super.key, required this.account});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  late final List<SourceConnector> _connectors = buildConnectors(widget.account);
  final _results = <String, ConnectorResult>{};
  final _busy = <String>{};
  final _address = TextEditingController();
  String? _review;

  @override
  void initState() {
    super.initState();
    for (final c in _connectors) {
      _check(c);
    }
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _check(SourceConnector c) async {
    setState(() => _busy.add(c.id));
    final result = await c.check();
    if (!mounted) return;
    setState(() {
      _busy.remove(c.id);
      _results[c.id] = result;
    });
  }

  String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  Widget _card(SourceConnector c) {
    final r = _results[c.id];
    final busy = _busy.contains(c.id);
    final reviewed = c is ReviewedConnector ? c : null;
    return _SourceCard(
      name: c.name,
      good: r?.ok ?? false,
      detail: busy && r == null ? 'Checking' : (reviewed != null ? reviewed.reason : '${r?.message ?? ''}${r != null && r.ok ? '. Checked ${_time(r.at)}' : ''}'),
      extra: reviewed == null ? null : 'Website: ${reviewed.website}\nIntegration: ${reviewed.integration}',
      can: c.provides,
      cannot: c.lacks,
      action: reviewed != null ? null : TextButton(onPressed: busy ? null : () => _check(c), child: const Text('Refresh')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final side = pageSide(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: Palette.background, scrolledUnderElevation: 0, title: const Text('SOURCES', style: TextStyle(fontFamily: 'Bebas', fontSize: 28, letterSpacing: 0.6))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(side, 8, side, 40),
        children: [
          const _Heading('Connected'),
          for (final c in _connectors.where((c) => c is! ReviewedConnector)) _card(c),
          const _Heading('Reviewed, unavailable'),
          const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Checked on Nov 7, 2026. None has an authorized way to share its catalog or video, so Vortex never contacts them and their scripts can\'t reach you.', style: TextStyle(color: Palette.muted, fontSize: 13, height: 1.4))),
          for (final c in _connectors.whereType<ReviewedConnector>()) _card(c),
          const _Heading('Privacy'),
          const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Vortex has no ads or trackers of its own. AniList and Kitsu only see which show you opened. The player runs YouTube\'s official stream, so YouTube sees what\'s playing and may show its ads.', style: TextStyle(color: Palette.muted, fontSize: 13, height: 1.4))),
          const _Heading('Check another site'),
          const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('The address is only compared with this list and is never visited.', style: TextStyle(color: Palette.muted, fontSize: 13, height: 1.4))),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (v) => setState(() => _review = reviewAddress(v, _connectors)),
            decoration: const InputDecoration(hintText: 'Website address', prefixIcon: Icon(Icons.link_rounded, color: Palette.muted)),
          ),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: () => setState(() => _review = reviewAddress(_address.text, _connectors)), child: const Text('Check site'))),
          if (_review != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_review!, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: Text(text.toUpperCase(), style: const TextStyle(fontFamily: 'Bebas', fontSize: 24, letterSpacing: 0.5, color: Palette.lavender)));
}

class _SourceCard extends StatelessWidget {
  final String name;
  final bool good;
  final String detail;
  final String? extra;
  final List<String> can;
  final List<String> cannot;
  final Widget? action;

  const _SourceCard({required this.name, required this.good, required this.detail, this.extra, required this.can, required this.cannot, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: Palette.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: good ? Palette.free : Palette.muted)),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              ?action,
            ],
          ),
          Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail, style: const TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.4))),
          if (extra != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(extra!, style: const TextStyle(color: Palette.muted, fontSize: 12, height: 1.45))),
          if (can.isNotEmpty || cannot.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in can) _Chip(c, true),
                for (final c in cannot) _Chip(c, false),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool yes;

  const _Chip(this.text, this.yes);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(yes ? Icons.check_rounded : Icons.close_rounded, size: 14, color: yes ? Palette.free : Palette.muted),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: yes ? Colors.white : Palette.muted)),
      ],
    );
  }
}
