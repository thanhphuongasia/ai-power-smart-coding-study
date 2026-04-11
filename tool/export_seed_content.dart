import 'dart:convert';
import 'dart:io';

import 'package:ai_powerd_mobile_code_assitant/data/sample_curriculum.dart';
import 'package:ai_powerd_mobile_code_assitant/models/learning_serialization.dart';

Future<void> main(List<String> arguments) async {
  final outputPath = arguments.isEmpty
      ? 'strapi/seed/seed_content.json'
      : arguments.first;

  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);

  final payload = <String, Object?>{
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'tracks': SeedData.tracks().map(learningTrackToJson).toList(growable: false),
    'skills': SeedData.skills().map(skillNodeToJson).toList(growable: false),
    'skillMemory': <String, Object?>{
      for (final entry in SeedData.skillMemory().entries)
        entry.key: skillMasteryRecordToJson(entry.value),
    },
  };

  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
  );

  stdout.writeln('Exported seed content to ${outputFile.path}');
}
