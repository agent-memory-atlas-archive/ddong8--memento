import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Memory Tree Filter Tests', () {
    final mockTree = [
      {
        'id': 'dir:/project',
        'name': 'project',
        'title': '项目与业务系统',
        'category': 'project',
        'tree_path': '/project',
        'is_folder': true,
        'children': [
          {
            'id': 'dir:/project/quant_future',
            'name': 'quant_future',
            'title': '量化期货多因子回测',
            'category': 'project',
            'tree_path': '/project/quant_future',
            'is_folder': true,
            'children': [
              {
                'id': 'mem-1',
                'name': 'overview',
                'title': 'proj_quant_future_overview',
                'key': 'proj_quant_future_overview',
                'category': 'project',
                'tree_path': '/project/quant_future/overview',
                'content': '量化交易与多因子策略回测系统',
                'confidence': 0.95,
                'is_folder': false,
              }
            ],
          },
          {
            'id': 'dir:/project/pubchem',
            'name': 'pubchem',
            'title': 'PubChem 化学数据库',
            'category': 'project',
            'tree_path': '/project/pubchem',
            'is_folder': true,
            'children': [
              {
                'id': 'mem-2',
                'name': 'overview',
                'title': 'proj_pubchem_overview',
                'key': 'proj_pubchem_overview',
                'category': 'project',
                'tree_path': '/project/pubchem/overview',
                'content': '海量化学分子式与反应物索引管线',
                'confidence': 0.98,
                'is_folder': false,
              }
            ],
          },
        ],
      },
    ];

    List<dynamic> filterTreeNodes(List<dynamic> nodes, String query) {
      if (query.isEmpty) return nodes;
      final q = query.toLowerCase().trim();
      final List<dynamic> filtered = [];

      for (final node in nodes) {
        if (node is! Map<String, dynamic>) continue;
        final isFolder = node['is_folder'] == true;
        final name = (node['name']?.toString() ?? '').toLowerCase();
        final title = (node['title']?.toString() ?? '').toLowerCase();
        final key = (node['key']?.toString() ?? '').toLowerCase();
        final content = (node['content']?.toString() ?? '').toLowerCase();
        final treePath = (node['tree_path']?.toString() ?? '').toLowerCase();

        final selfMatches = name.contains(q) ||
            title.contains(q) ||
            key.contains(q) ||
            content.contains(q) ||
            treePath.contains(q);

        if (isFolder) {
          final children = node['children'] as List<dynamic>? ?? [];
          final filteredChildren = filterTreeNodes(children, query);
          if (selfMatches || filteredChildren.isNotEmpty) {
            final copy = Map<String, dynamic>.from(node);
            copy['children'] = filteredChildren.isNotEmpty ? filteredChildren : children;
            filtered.add(copy);
          }
        } else {
          if (selfMatches) {
            filtered.add(node);
          }
        }
      }
      return filtered;
    }

    test('Empty query returns full tree untouched', () {
      final res = filterTreeNodes(mockTree, '');
      expect(res.length, equals(1));
      final projChildren = res[0]['children'] as List;
      expect(projChildren.length, equals(2));
    });

    test('Filtering by "quant" matches quant_future and prunes pubchem', () {
      final res = filterTreeNodes(mockTree, 'quant');
      expect(res.length, equals(1));
      final projChildren = res[0]['children'] as List;
      expect(projChildren.length, equals(1));
      expect(projChildren[0]['name'], equals('quant_future'));
    });

    test('Filtering by Chinese keyword "化学" matches pubchem', () {
      final res = filterTreeNodes(mockTree, '化学');
      expect(res.length, equals(1));
      final projChildren = res[0]['children'] as List;
      expect(projChildren.length, equals(1));
      expect(projChildren[0]['name'], equals('pubchem'));
    });

    test('Filtering by non-existent query returns empty', () {
      final res = filterTreeNodes(mockTree, 'non_existent_project_xyz');
      expect(res.isEmpty, isTrue);
    });
  });
}
