import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme/aurora_theme.dart';
import '../../models/search_hit.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_markdown.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- Tab 1: Search State ---
  final _searchController = TextEditingController();
  bool _semantic = true;
  bool _isSearchLoading = false;
  List<SearchHit> _hits = [];
  String? _searchError;

  // --- Tab 2: Core Memory State ---
  bool _isCoreLoading = false;
  bool _isTreeView = true;
  List<dynamic> _coreMemories = [];
  List<dynamic> _coreMemoryTree = [];
  String? _coreError;
  String? _selectedCategory;

  // --- Tab 3: Dreaming State ---
  bool _isDreamLoading = false;
  bool _isDreamingRunning = false;
  List<dynamic> _dreamJournals = [];
  Map<String, dynamic>? _tierStats;
  String? _dreamError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1 && _coreMemories.isEmpty && !_isCoreLoading) {
        _loadCoreMemories();
      } else if (_tabController.index == 2 && _dreamJournals.isEmpty && !_isDreamLoading) {
        _loadDreamData();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Search Handlers
  // ---------------------------------------------------------------------------
  void _doSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearchLoading = true;
      _searchError = null;
    });

    try {
      final res = await ApiClient().searchMemory(query, semantic: _semantic);
      final rawResults = res['results'] as List<dynamic>? ?? [];
      setState(() {
        _hits = rawResults.map((j) => SearchHit.fromJson(j)).toList();
        _isSearchLoading = false;
      });
    } catch (e) {
      setState(() {
        _searchError = '检索出错: $e';
        _isSearchLoading = false;
      });
    }
  }

  void _showDocumentDetail(String id, String title) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AuroraColors.surfaceSolid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<Map<String, dynamic>>(
              future: ApiClient().getDocument(id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AuroraColors.accent));
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return const Center(child: Text('加载文档失败', style: TextStyle(color: AuroraColors.danger)));
                }

                final doc = snapshot.data!;
                final content = doc['content']?.toString() ?? '无内容';
                final aiSummary = doc['ai_summary']?.toString();

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AuroraColors.fg3.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AuroraColors.fg1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (aiSummary != null && aiSummary.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AuroraColors.chip,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AuroraColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.auto_awesome, size: 14, color: AuroraColors.accent),
                                SizedBox(width: 6),
                                Text(
                                  'AI 摘要',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AuroraColors.accent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              aiSummary,
                              style: const TextStyle(fontSize: 13, color: AuroraColors.fg2, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Divider(color: AuroraColors.border),
                    const SizedBox(height: 12),
                    AppMarkdown(data: content),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Core Memory (MEMORY.md) Handlers
  // ---------------------------------------------------------------------------
  Future<void> _loadCoreMemories() async {
    setState(() {
      _isCoreLoading = true;
      _coreError = null;
    });
    try {
      final futures = await Future.wait([
        ApiClient().getCoreMemories(category: _selectedCategory),
        ApiClient().getCoreMemoryTree(),
      ]);
      setState(() {
        _coreMemories = futures[0] as List<dynamic>;
        _coreMemoryTree = (futures[1] as Map<String, dynamic>)['tree'] as List<dynamic>? ?? [];
        _isCoreLoading = false;
      });
    } catch (e) {
      setState(() {
        _coreError = '加载核心记忆失败: $e';
        _isCoreLoading = false;
      });
    }
  }

  void _showFullMemoryMarkdown() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AuroraColors.surfaceSolid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<String>(
              future: ApiClient().getCoreMemoryMarkdown(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AuroraColors.accent));
                }
                final md = snapshot.data ?? '无内容';
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AuroraColors.fg3.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Icon(Icons.description_outlined, color: AuroraColors.accent, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'MEMORY.md 全文预览',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AuroraColors.fg1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppMarkdown(data: md),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showAddOrEditMemoryDialog({
    Map<String, dynamic>? existing,
    String? defaultParentId,
    String? defaultTreePath,
    bool isFolderDefault = false,
  }) {
    final catController = TextEditingController(text: existing?['category'] ?? 'rule');
    final keyController = TextEditingController(text: existing?['key'] ?? '');
    final contentController = TextEditingController(text: existing?['content'] ?? '');
    final pathController = TextEditingController(
      text: existing?['tree_path'] ?? defaultTreePath ?? '',
    );
    bool isFolder = existing?['is_folder'] == true || isFolderDefault;
    final parentId = existing?['parent_id']?.toString() ?? defaultParentId;
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AuroraColors.surfaceSolid,
          title: Text(
            isEdit
                ? (isFolder ? '编辑目录分支' : '编辑核心记忆')
                : (isFolder ? '新建目录分支' : '添加长期核心记忆'),
            style: const TextStyle(color: AuroraColors.fg1, fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Switch(
                      value: isFolder,
                      activeColor: AuroraColors.accent,
                      onChanged: (val) {
                        setDialogState(() {
                          isFolder = val;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isFolder ? '📁 分支目录 (Folder Node)' : '📄 记忆条目 (Leaf Node)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isFolder ? AuroraColors.accent : AuroraColors.fg2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: ['rule', 'architecture', 'preference', 'project', 'general'].contains(catController.text)
                      ? catController.text
                      : 'general',
                  dropdownColor: AuroraColors.surfaceSolid,
                  style: const TextStyle(color: AuroraColors.fg1, fontSize: 13.5),
                  decoration: const InputDecoration(labelText: '根分类 (Category)'),
                  items: const [
                    DropdownMenuItem(value: 'rule', child: Text('规范铁律 (rule)')),
                    DropdownMenuItem(value: 'architecture', child: Text('架构决策 (architecture)')),
                    DropdownMenuItem(value: 'preference', child: Text('偏好习惯 (preference)')),
                    DropdownMenuItem(value: 'project', child: Text('项目约束 (project)')),
                    DropdownMenuItem(value: 'general', child: Text('通用常识 (general)')),
                  ],
                  onChanged: (v) => catController.text = v ?? 'general',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyController,
                  style: const TextStyle(color: AuroraColors.fg1, fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: isFolder ? '目录名称 (Key，如 desktop)' : '主题标识 (Key，如 windows_update_policy)',
                    hintText: '英文小写与下划线',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pathController,
                  style: const TextStyle(color: AuroraColors.fg1, fontSize: 13.5),
                  decoration: const InputDecoration(
                    labelText: '树状路径 (Tree Path，可选)',
                    hintText: '例如 /rules/desktop/windows_update',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  maxLines: isFolder ? 2 : 4,
                  style: const TextStyle(color: AuroraColors.fg1, fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: isFolder ? '目录说明 (Description)' : '记忆准则内容 (Content)',
                    hintText: isFolder ? '简要描述该分支收录的规则或模块...' : '描述具体规范、铁律或配置习惯...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: AuroraColors.fg3)),
            ),
            ElevatedButton(
              onPressed: () async {
                final cat = catController.text.trim();
                final key = keyController.text.trim();
                final content = contentController.text.trim();
                final path = pathController.text.trim().isEmpty ? null : pathController.text.trim();
                if (key.isEmpty || content.isEmpty) return;

                Navigator.pop(ctx);
                try {
                  if (isEdit) {
                    await ApiClient().updateCoreMemory(
                      existing['id'].toString(),
                      category: cat,
                      key: key,
                      content: content,
                      treePath: path,
                      isFolder: isFolder,
                    );
                  } else {
                    await ApiClient().createCoreMemory(
                      cat,
                      key,
                      content,
                      parentId: parentId,
                      treePath: path,
                      isFolder: isFolder,
                    );
                  }
                  _loadCoreMemories();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteMemory(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuroraColors.surfaceSolid,
        title: const Text('确认遗忘？', style: TextStyle(color: AuroraColors.fg1)),
        content: const Text('该条长期记忆将被永久移除。', style: TextStyle(color: AuroraColors.fg2)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('遗忘', style: TextStyle(color: AuroraColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiClient().deleteCoreMemory(id);
        _loadCoreMemories();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Dreaming & Journal Handlers
  // ---------------------------------------------------------------------------
  Future<void> _loadDreamData() async {
    setState(() {
      _isDreamLoading = true;
      _dreamError = null;
    });
    try {
      final tiersFuture = ApiClient().getMemoryTiers();
      final journalsFuture = ApiClient().getDreamJournals(limit: 20);
      final results = await Future.wait([tiersFuture, journalsFuture]);

      setState(() {
        _tierStats = results[0];
        _dreamJournals = results[1]['journals'] as List<dynamic>? ?? [];
        _isDreamLoading = false;
      });
    } catch (e) {
      setState(() {
        _dreamError = '加载做梦数据失败: $e';
        _isDreamLoading = false;
      });
    }
  }

  void _triggerDreamingNow() async {
    setState(() => _isDreamingRunning = true);
    try {
      final res = await ApiClient().triggerDream(daysBack: 1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌙 做梦反思与记忆固化已完成！'),
          backgroundColor: AuroraColors.accent,
        ),
      );
      _loadDreamData();
      _loadCoreMemories();
      if (res['report_markdown'] != null) {
        _showDreamReportModal(res['report_markdown'].toString());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('做梦反思失败: $e'), backgroundColor: AuroraColors.danger),
      );
    } finally {
      if (mounted) {
        setState(() => _isDreamingRunning = false);
      }
    }
  }

  void _showDreamReportModal(String markdown) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AuroraColors.surfaceSolid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AuroraColors.fg3.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppMarkdown(data: markdown),
              ],
            );
          },
        );
      },
    );
  }

  void _showDreamJournalDetail(String id) async {
    try {
      final detail = await ApiClient().getDreamJournalDetail(id);
      final md = detail['report_markdown']?.toString() ?? '无报告内容';
      _showDreamReportModal(md);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取梦境日记失败: $e')));
    }
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuroraColors.bg,
      appBar: AppBar(
        backgroundColor: AuroraColors.bg,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.psychology_outlined, color: AuroraColors.accent, size: 22),
            SizedBox(width: 8),
            Text(
              '外脑记忆库',
              style: TextStyle(
                color: AuroraColors.fg1,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AuroraColors.accent,
          indicatorWeight: 2.5,
          labelColor: AuroraColors.accent,
          unselectedLabelColor: AuroraColors.fg3,
          labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: '检索与图谱'),
            Tab(text: '长期核心记忆'),
            Tab(text: '做梦与分层'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSearchTab(),
          _buildCoreMemoryTab(),
          _buildDreamingTab(),
        ],
      ),
    );
  }

  // --- View: Tab 1 (Search) ---
  Widget _buildSearchTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AuroraColors.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _doSearch(),
                  style: const TextStyle(color: AuroraColors.fg1, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '搜索过去的研发对话、代码与笔记...',
                    hintStyle: const TextStyle(color: AuroraColors.fg3, fontSize: 13.5),
                    prefixIcon: const Icon(Icons.search, color: AuroraColors.fg3, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: _semantic ? '语义向量检索 (BGE-M3)' : '全文检索 (FTS)',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _semantic = !_semantic),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    _semantic ? Icons.auto_awesome : Icons.text_snippet,
                                    size: 15,
                                    color: _semantic ? AuroraColors.accent : AuroraColors.fg3,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _semantic ? '语义' : '全文',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _semantic ? AuroraColors.accent : AuroraColors.fg3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: AuroraColors.fg3),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _hits.clear());
                            },
                          ),
                      ],
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AuroraColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AuroraColors.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isSearchLoading ? null : _doSearch,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: _isSearchLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('检索'),
              ),
            ],
          ),
        ),
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_searchError!, style: const TextStyle(color: AuroraColors.danger, fontSize: 13)),
          ),
        Expanded(
          child: _hits.isEmpty && !_isSearchLoading
              ? const Center(
                  child: Text(
                    '输入关键词检索跨设备的编程记忆',
                    style: TextStyle(color: AuroraColors.fg3, fontSize: 13.5),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _hits.length,
                  itemBuilder: (context, index) {
                    final hit = _hits[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        onTap: () => _showDocumentDetail(hit.id, hit.title ?? hit.relativePath),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AuroraColors.chip,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    hit.toolId.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: AuroraColors.accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    hit.title ?? hit.relativePath,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: AuroraColors.fg1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              hit.snippet,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AuroraColors.fg2,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- View: Tab 2 (Core Memory / MEMORY.md) ---
  Widget _buildCoreMemoryTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AuroraColors.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip(null, '全部'),
                      _buildCategoryChip('rule', '开发铁律'),
                      _buildCategoryChip('architecture', '架构决策'),
                      _buildCategoryChip('preference', '个人偏好'),
                      _buildCategoryChip('project', '项目知识'),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '预览 MEMORY.md 全文',
                icon: const Icon(Icons.menu_book, color: AuroraColors.accent, size: 20),
                onPressed: _showFullMemoryMarkdown,
              ),
              IconButton(
                tooltip: '手动添加记忆条目',
                icon: const Icon(Icons.add_circle_outline, color: AuroraColors.accent, size: 20),
                onPressed: () => _showAddOrEditMemoryDialog(),
              ),
            ],
          ),
        ),
        if (_coreError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_coreError!, style: const TextStyle(color: AuroraColors.danger, fontSize: 13)),
          ),
        Expanded(
          child: _isCoreLoading
              ? const Center(child: CircularProgressIndicator(color: AuroraColors.accent))
              : _coreMemories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lightbulb_outline, size: 40, color: AuroraColors.fg3),
                          const SizedBox(height: 12),
                          const Text(
                            '当前分类下暂无核心记忆',
                            style: TextStyle(color: AuroraColors.fg3, fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('新增第一条长期记忆'),
                            onPressed: () => _showAddOrEditMemoryDialog(),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadCoreMemories,
                      color: AuroraColors.accent,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _coreMemories.length,
                        itemBuilder: (context, index) {
                          final mem = _coreMemories[index] as Map<String, dynamic>;
                          final cat = mem['category']?.toString() ?? 'general';
                          final key = mem['key']?.toString() ?? '';
                          final content = mem['content']?.toString() ?? '';
                          final confidence = (mem['confidence'] as num?)?.toDouble() ?? 1.0;
                          final source = mem['source']?.toString() ?? 'dreaming';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: GlassCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cat == 'rule'
                                              ? AuroraColors.danger.withValues(alpha: 0.15)
                                              : AuroraColors.accent.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          cat.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: cat == 'rule' ? AuroraColors.danger : AuroraColors.accent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          key,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: AuroraColors.fg1,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AuroraColors.chip,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          source == 'dreaming' ? '🌙 梦境萃取' : '✍️ 手动',
                                          style: const TextStyle(fontSize: 10, color: AuroraColors.fg3),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, size: 18, color: AuroraColors.fg3),
                                        color: AuroraColors.surfaceSolid,
                                        onSelected: (action) {
                                          if (action == 'edit') {
                                            _showAddOrEditMemoryDialog(mem);
                                          } else if (action == 'delete') {
                                            _deleteMemory(mem['id'].toString());
                                          }
                                        },
                                        itemBuilder: (ctx) => const [
                                          PopupMenuItem(value: 'edit', child: Text('编辑')),
                                          PopupMenuItem(value: 'delete', child: Text('遗忘/删除', style: TextStyle(color: AuroraColors.danger))),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    content,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AuroraColors.fg1,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '置信度: ${(confidence * 100).toInt()}%',
                                        style: const TextStyle(fontSize: 11, color: AuroraColors.fg3),
                                      ),
                                      Text(
                                        (mem['updated_at']?.toString() ?? '').split('T').first,
                                        style: const TextStyle(fontSize: 11, color: AuroraColors.fg3),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String? category, String label) {
    final selected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.black : AuroraColors.fg2)),
        selected: selected,
        selectedColor: AuroraColors.accent,
        backgroundColor: AuroraColors.surface,
        onSelected: (val) {
          setState(() {
            _selectedCategory = val ? category : null;
          });
          _loadCoreMemories();
        },
      ),
    );
  }

  // --- View: Tab 3 (Dreaming & Memory Tiers) ---
  Widget _buildDreamingTab() {
    return RefreshIndicator(
      onRefresh: _loadDreamData,
      color: AuroraColors.accent,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Dreaming Control Hero Card
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.nights_stay, color: AuroraColors.accent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '自主做梦机制 (Dreaming Consolidation)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AuroraColors.fg1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '系统每日夜间 (03:00) 或空闲时自动唤醒，模拟生物睡眠三阶段（浅睡去噪 -> REM 联想反思 -> 深睡固化与衰减），将每日海量琐事蒸馏为长期开发铁律。',
                  style: TextStyle(fontSize: 12.5, color: AuroraColors.fg2, height: 1.45),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isDreamingRunning ? null : _triggerDreamingNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AuroraColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _isDreamingRunning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.bedtime_outlined, size: 18),
                    label: Text(_isDreamingRunning ? '正在做梦反思与记忆重组...' : '立即唤醒做梦 (Trigger Dream)'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3-Tier Memory Architecture Overview Cards
          if (_tierStats != null) ...[
            const Text(
              '三层记忆金字塔状态',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AuroraColors.fg1),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildTierCard(
                    'L1 工作记忆',
                    '${_tierStats!['l1_working']?['conversations'] ?? 0}',
                    '实时交互轮次',
                    AuroraColors.chip,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTierCard(
                    'L2 情景记忆',
                    '${_tierStats!['l2_episodic']?['daily_summaries'] ?? 0}',
                    '每日研发小结',
                    AuroraColors.chip,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTierCard(
                    'L3 核心记忆',
                    '${_tierStats!['l3_core']?['core_memories'] ?? 0}',
                    'MEMORY.md 准则',
                    AuroraColors.accent.withValues(alpha: 0.18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          if (_dreamError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(_dreamError!, style: const TextStyle(color: AuroraColors.danger, fontSize: 13)),
            ),

          // Historical Dream Journals
          const Row(
            children: [
              Icon(Icons.auto_stories, size: 16, color: AuroraColors.accent),
              SizedBox(width: 6),
              Text(
                '梦境日记 (Dream Journals)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AuroraColors.fg1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isDreamLoading)
            const Center(child: CircularProgressIndicator(color: AuroraColors.accent))
          else if (_dreamJournals.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无梦境日记。点击上方“立即唤醒做梦”可体验夜间沉淀流程。',
                  style: TextStyle(color: AuroraColors.fg3, fontSize: 13),
                ),
              ),
            )
          else
            ..._dreamJournals.map((j) {
              final journal = j as Map<String, dynamic>;
              final dateStr = journal['dream_date']?.toString() ?? '';
              final metrics = journal['stage_metrics'] as Map<String, dynamic>? ?? {};
              final scanned = metrics['scanned_items'] ?? 0;
              final promoted = metrics['promoted_count'] ?? 0;
              final snippet = journal['summary_snippet']?.toString() ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => _showDreamJournalDetail(journal['id'].toString()),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.dark_mode_outlined, size: 16, color: AuroraColors.accent),
                              const SizedBox(width: 6),
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: AuroraColors.fg1,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '扫描 $scanned 项 · 晋升 $promoted 条',
                            style: const TextStyle(fontSize: 11.5, color: AuroraColors.accent),
                          ),
                        ],
                      ),
                      if (snippet.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AuroraColors.fg2, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTierCard(String title, String count, String subtitle, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AuroraColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: AuroraColors.fg3)),
          const SizedBox(height: 4),
          Text(
            count,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AuroraColors.fg1),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: AuroraColors.fg2)),
        ],
      ),
    );
  }
}
