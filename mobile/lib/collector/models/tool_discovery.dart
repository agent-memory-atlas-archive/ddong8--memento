/// Represents a project discovered inside an AI development tool data directory.
class DiscoveredProject {
  final String name;
  final String path;
  final int sessionCount;
  final DateTime? lastModified;
  final Map<String, dynamic>? metadata;

  const DiscoveredProject({
    required this.name,
    required this.path,
    this.sessionCount = 0,
    this.lastModified,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'session_count': sessionCount,
        if (lastModified != null) 'last_modified': lastModified!.toUtc().toIso8601String(),
        if (metadata != null) ...metadata!,
      };

  factory DiscoveredProject.fromJson(Map<String, dynamic> json) {
    return DiscoveredProject(
      name: json['name'] as String? ?? 'unnamed',
      path: json['path'] as String? ?? '',
      sessionCount: json['session_count'] as int? ?? 0,
      lastModified: json['last_modified'] != null ? DateTime.tryParse(json['last_modified'] as String) : null,
      metadata: json,
    );
  }
}

/// Represents an AI tool installation (e.g. Claude Code, Codex, Antigravity, Obsidian).
class DiscoveredTool {
  final String id;
  final String name;
  final String root;
  final List<DiscoveredProject> projects;
  final Map<String, dynamic> metadata;

  const DiscoveredTool({
    required this.id,
    required this.name,
    required this.root,
    this.projects = const [],
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'root': root,
        'projects': projects.map((p) => p.toJson()).toList(),
        if (metadata.isNotEmpty) ...metadata,
      };
}
