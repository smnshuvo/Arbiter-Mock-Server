import 'package:equatable/equatable.dart';

/// A named pass-through base URL the user has used before, so switching a
/// server between e.g. "Staging" and "Prod" doesn't mean retyping hosts.
class SavedBaseUrl extends Equatable {
  final String name;
  final String url;
  final DateTime lastUsedAt;

  const SavedBaseUrl({required this.name, required this.url, required this.lastUsedAt});

  /// Trailing slashes and surrounding whitespace don't make a different URL.
  static String normalize(String url) => url.trim().replaceFirst(RegExp(r'/+$'), '');

  /// Default name suggestion: the host, else the URL itself.
  static String suggestName(String url) {
    final host = Uri.tryParse(normalize(url))?.host ?? '';
    return host.isNotEmpty ? host : normalize(url);
  }

  SavedBaseUrl copyWith({String? name, DateTime? lastUsedAt}) => SavedBaseUrl(
        name: name ?? this.name,
        url: url,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'url': url, 'lastUsedAt': lastUsedAt.toIso8601String()};

  factory SavedBaseUrl.fromJson(Map<String, dynamic> json) => SavedBaseUrl(
        name: json['name'] as String,
        url: json['url'] as String,
        lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ?? DateTime(2000),
      );

  @override
  List<Object?> get props => [name, url, lastUsedAt];
}
