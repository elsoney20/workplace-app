import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../../feed/data/media_compressor.dart';
import '../../feed/domain/person.dart';

class DirectoryEntry {
  const DirectoryEntry({
    required this.person,
    required this.role,
    this.departmentId,
    this.departmentAr,
    this.departmentEn,
    this.bio,
    this.phone,
  });

  factory DirectoryEntry.fromJson(Map<String, dynamic> json) => DirectoryEntry(
    person: Person.fromJson(Map<String, dynamic>.from(json['person'] as Map)),
    role: json['role'] as String? ?? 'employee',
    departmentId: json['department_id'] as String?,
    departmentAr: json['department_ar'] as String?,
    departmentEn: json['department_en'] as String?,
    bio: json['bio'] as String?,
    phone: json['phone'] as String?,
  );

  final Person person;
  final String role;
  final String? departmentId;
  final String? departmentAr;
  final String? departmentEn;
  final String? bio;

  /// null = hidden by the person's privacy choice.
  final String? phone;

  String? department(String languageCode) => languageCode == 'ar'
      ? (departmentAr ?? departmentEn)
      : (departmentEn ?? departmentAr);
}

class MySettings {
  const MySettings({this.bio, required this.phoneVisibility, this.avatarPath});
  final String? bio;

  /// everyone | managers | nobody
  final String phoneVisibility;
  final String? avatarPath;
}

class DirectoryRepository {
  DirectoryRepository(SupabaseClient client) : _clientOrNull = client;
  DirectoryRepository.withoutClient() : _clientOrNull = null;

  final SupabaseClient? _clientOrNull;
  SupabaseClient get _client => _clientOrNull!;

  Future<List<DirectoryEntry>> list({
    String? query,
    String? departmentId,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_directory',
      params: {'p_query': query, 'p_department_id': departmentId},
    );
    return rows
        .map(
          (r) => DirectoryEntry.fromJson(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
  }

  Future<List<(String, String, String)>> departments() async {
    final rows = await _client
        .from('departments')
        .select('id, name_ar, name_en')
        .order('name_en');
    return [
      for (final r in rows)
        (r['id'] as String, r['name_ar'] as String, r['name_en'] as String),
    ];
  }

  Future<MySettings> mySettings() async {
    final rows = await _client.rpc<List<dynamic>>('get_my_settings');
    final r = rows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(rows.first as Map);
    return MySettings(
      bio: r['bio'] as String?,
      phoneVisibility: r['phone_visibility'] as String? ?? 'everyone',
      avatarPath: r['avatar_path'] as String?,
    );
  }

  Future<void> saveSettings(
    String profileId, {
    String? bio,
    required String phoneVisibility,
  }) => _client
      .from('profiles')
      .update({'bio': bio, 'phone_visibility': phoneVisibility})
      .eq('id', profileId);

  /// Uploads a square-ish photo (max 512 px) to `avatars/<profile_id>/`.
  Future<void> setAvatar(
    String profileId,
    Uint8List bytes,
    String mimeType,
  ) async {
    final compressed = await MediaCompressor.compressImage(
      bytes,
      mimeType,
      maxSide: 512,
    );
    final data = compressed?.bytes ?? bytes;
    final type = compressed?.mimeType ?? mimeType;
    final path =
        '$profileId/${DateTime.now().millisecondsSinceEpoch}.${type == 'image/png' ? 'png' : 'jpg'}';
    await _client.storage
        .from('avatars')
        .uploadBinary(path, data, fileOptions: FileOptions(contentType: type));
    final old = (await mySettings()).avatarPath;
    await _client
        .from('profiles')
        .update({'avatar_path': path})
        .eq('id', profileId);
    if (old != null) {
      await _client.storage
          .from('avatars')
          .remove([old])
          .catchError((_) => <FileObject>[]);
    }
  }

  Future<void> removeAvatar(String profileId) async {
    final old = (await mySettings()).avatarPath;
    await _client
        .from('profiles')
        .update({'avatar_path': null})
        .eq('id', profileId);
    if (old != null) {
      await _client.storage
          .from('avatars')
          .remove([old])
          .catchError((_) => <FileObject>[]);
    }
  }
}

final directoryRepositoryProvider = Provider<DirectoryRepository>(
  (ref) => DirectoryRepository(ref.watch(supabaseClientProvider)),
);
