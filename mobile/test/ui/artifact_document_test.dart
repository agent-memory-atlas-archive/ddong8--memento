import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/models/agent_artifact.dart';
import 'package:memento_mobile/ui/widgets/artifact_document_view.dart';

AgentArtifact _artifact(String path, ArtifactType type) =>
    AgentArtifact(id: 'a', title: 'a', type: type, rawPath: path);

void main() {
  test('text formats render in place, office and pdf files open outside', () {
    expect(artifactIsText(_artifact('/tmp/report.md', ArtifactType.markdown)), isTrue);
    expect(artifactIsText(_artifact('/tmp/page.html', ArtifactType.html)), isTrue);
    expect(artifactIsText(_artifact('/tmp/run.log', ArtifactType.document)), isTrue);
    expect(artifactIsText(_artifact('/tmp/deck.pdf', ArtifactType.document)), isFalse);
    expect(artifactIsText(_artifact('/tmp/sheet.xlsx', ArtifactType.document)), isFalse);
  });

  test('plain text and logs are picked up as documents', () {
    final found = AgentArtifact.extractArtifacts('日志在 `/var/tmp/build.log`，说明见 [README](/srv/app/notes.txt)');
    expect(found.map((a) => a.type), [ArtifactType.document, ArtifactType.document]);
  });

  group('loading a file on this machine', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('artifact_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads it whole', () async {
      final f = File('${dir.path}/report.md')..writeAsStringSync('# 周报\n\n- 修复登录 500');
      final r = await loadArtifactText(_artifact(f.path, ArtifactType.markdown), 'http://unused');
      expect(r.text, '# 周报\n\n- 修复登录 500');
      expect(r.truncated, isFalse);
    });

    test('stops at the size limit', () async {
      final f = File('${dir.path}/big.log')..writeAsBytesSync(List.filled(artifactTextLimit + 10, 0x61));
      final r = await loadArtifactText(_artifact('file://${f.path}', ArtifactType.document), 'http://unused');
      expect(r.text.length, artifactTextLimit);
      expect(r.truncated, isTrue);
    });
  });
}
