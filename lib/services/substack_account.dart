import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/reading.dart';
import 'net.dart';

/// A publication the user follows on Substack.
class SubstackPub {
  final int id;
  final String name;

  /// e.g. `astralcodexten.substack.com`; custom domains redirect from here.
  final String host;
  final bool paid;

  /// What its posts count as in tonight's trio; `null` sorts each post by its
  /// content. Chosen by the user.
  final ReadingType? type;

  /// Whether its posts are offered at all.
  final bool on;

  const SubstackPub({
    required this.id,
    required this.name,
    required this.host,
    required this.paid,
    this.type,
    this.on = true,
  });

  SubstackPub copyWith({ReadingType? Function()? type, bool? on, bool? paid}) => SubstackPub(
        id: id,
        name: name,
        host: host,
        paid: paid ?? this.paid,
        type: type == null ? this.type : type(),
        on: on ?? this.on,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'host': host, 'paid': paid, 'type': type?.name ?? 'auto', 'on': on};

  factory SubstackPub.fromJson(Map<String, dynamic> j) => SubstackPub(
        id: j['id'] as int,
        name: j['name'] as String,
        host: j['host'] as String,
        paid: j['paid'] as bool? ?? false,
        type: switch (j['type'] as String?) { null || 'auto' => null, final t => ReadingType.values.byName(t) },
        on: j['on'] as bool? ?? true,
      );
}

/// The user's Substack: which publications they follow, read from their public
/// profile (no sign-in needed), plus an optional session for paid posts. The
/// session cookie is kept in secure storage and only ever sent to substack.com.
class SubstackAccount {
  static const cookieName = 'substack.sid';
  static const _key = 'substack.sid';
  static const _storage = FlutterSecureStorage();

  String? _session;
  bool get signedIn => _session != null;

  Future<void> load() async {
    try {
      _session = await _storage.read(key: _key);
    } on Exception {
      _session = null; // Keychain/keystore unavailable: behave as signed out.
    }
  }

  Future<void> signIn(String session) async {
    _session = session.trim();
    await _storage.write(key: _key, value: _session);
  }

  Future<void> signOut() async {
    _session = null;
    await _storage.delete(key: _key);
  }

  /// Reads a username out of `@name`, `name`, `substack.com/@name`,
  /// `substack.com/profile/123-name` or `name.substack.com`.
  static String? parseHandle(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    if (uri != null && uri.host.contains('.')) {
      final segs = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (segs.isNotEmpty && segs.first.startsWith('@')) {
        s = segs.first;
      } else if (segs.length > 1 && segs.first == 'profile') {
        s = segs[1].replaceFirst(RegExp(r'^\d+-'), '');
      } else if (uri.host.endsWith('.substack.com') && uri.host != 'www.substack.com') {
        s = uri.host.split('.').first;
      } else if (segs.isEmpty) {
        return null;
      }
    }
    s = s.replaceFirst('@', '');
    return RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(s) ? s : null;
  }

  /// GET on substack.com, authenticated when signed in.
  Future<dynamic> getJson(String path) async {
    final res = await Net.client.get(
      Uri.parse('https://substack.com$path'),
      headers: {
        'User-Agent': Net.userAgent,
        if (_session != null) 'Cookie': '$cookieName=$_session',
      },
    ).timeout(const Duration(seconds: 25));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SourceException(_session == null
          ? 'Substack refused the request'
          : 'Substack sign-in expired; sign in again under Sources › Accounts');
    }
    if (res.statusCode == 404) throw SourceException('Not found on Substack');
    if (res.statusCode == 429) throw RateLimitedException('substack.com');
    if (res.statusCode != 200) throw SourceException('HTTP ${res.statusCode} from substack.com');
    return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  /// Publications [handle] follows, from their public profile.
  Future<List<SubstackPub>> follows(String handle) async {
    final Map profile;
    try {
      profile = await getJson('/api/v1/user/${Uri.encodeComponent(handle)}/public_profile') as Map;
    } on SourceException catch (e) {
      if (e.message == 'Not found on Substack') throw SourceException('No Substack user called "$handle"');
      rethrow;
    }
    final pubs = <SubstackPub>[
      for (final s in (profile['subscriptions'] as List? ?? const []).cast<Map>())
        if ((s['publication'] as Map?)?['subdomain'] != null)
          SubstackPub(
            id: (s['publication'] as Map)['id'] as int,
            name: ((s['publication'] as Map)['name'] as String?)?.trim() ?? (s['publication'] as Map)['subdomain'] as String,
            host: '${(s['publication'] as Map)['subdomain']}.substack.com',
            paid: _isPaid(s),
          ),
    ];
    if (pubs.isEmpty) {
      throw SourceException('$handle\'s profile shows no subscriptions. On Substack, open Settings and make '
          'your subscriptions visible on your profile, then try again.');
    }
    pubs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return pubs;
  }

  static bool _isPaid(Map s) {
    final state = '${s['membership_state'] ?? ''}'.toLowerCase();
    return state.contains('paid') || state.contains('founding') || state.contains('comp') ||
        s['is_founding'] == true || s['is_paid'] == true || s['paid'] == true;
  }
}
