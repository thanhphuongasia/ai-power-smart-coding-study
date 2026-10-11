/// Sơ đồ class UML gọn cho điện thoại: lớp của bài + quan hệ, tô sáng phần
/// thuộc phạm vi bài (attribute method đụng tới, chính method đó).
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/class_scope.dart';
import '../../domain/models.dart';

class ClassDiagramView extends StatelessWidget {
  const ClassDiagramView({
    super.key,
    required this.diagram,
    required this.scope,
  });

  final ClassDiagram diagram;
  final ClassScope scope;

  @override
  Widget build(BuildContext context) {
    final cls = diagram.classNamed(scope.className);
    if (cls == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MainClassBox(cls: cls, scope: scope),
        for (final r in diagram.relationsOf(cls.name))
          _RelationRow(relation: r, self: cls.name),
      ],
    );
  }
}

BoxDecoration _boxDeco(AppPalette p) => BoxDecoration(
  color: p.surface,
  border: Border.all(color: p.outline.withValues(alpha: 0.6)),
  borderRadius: BorderRadius.circular(AppRadius.sm),
);

class _Header extends StatelessWidget {
  const _Header({required this.name, this.file});

  final String name;
  final String? file;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s2),
      color: p.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'class $name',
            style: AppText.code.copyWith(
              color: p.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (file != null)
            Text(
              file!,
              style: AppText.caption.copyWith(color: p.inkMuted),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _Member extends StatelessWidget {
  const _Member({required this.text, this.hlKey, this.highlight = false});

  final String text;
  final Key? hlKey;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: highlight ? hlKey : null,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: 2),
      color: highlight ? p.accent.withValues(alpha: 0.22) : null,
      child: Text(
        text,
        style: AppText.code.copyWith(
          color: p.ink,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpace.s2, AppSpace.s1, 0, 0),
    child: Text(
      text,
      style: AppText.caption.copyWith(color: context.palette.inkMuted),
    ),
  );
}

class _MainClassBox extends StatelessWidget {
  const _MainClassBox({required this.cls, required this.scope});

  final DiagramClass cls;
  final ClassScope scope;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final core = [
      for (final a in cls.attributes)
        if (a.group == 'core') a,
    ];
    final support = [
      for (final a in cls.attributes)
        if (a.group != 'core') a,
    ];
    Widget attr(DiagramAttribute a) => _Member(
      text: '${a.name}: ${a.type}',
      hlKey: Key('diagram-hl-${cls.name}-${a.name}'),
      highlight: scope.attributes.contains(a.name),
    );
    return Container(
      key: Key('diagram-class-${cls.name}'),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: _boxDeco(
        p,
      ).copyWith(border: Border.all(color: p.primary, width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(name: cls.name, file: cls.file),
          if (core.isNotEmpty) ...[
            const _SubLabel('core'),
            for (final a in core) attr(a),
          ],
          if (support.isNotEmpty) ...[
            const _SubLabel('support'),
            for (final a in support) attr(a),
          ],
          if (cls.methods.isNotEmpty) ...[
            Divider(height: AppSpace.s2, color: p.outline),
            for (final m in cls.methods)
              _Member(
                text: '$m()',
                hlKey: Key('diagram-hl-${cls.name}-$m'),
                highlight: m == scope.method,
              ),
            const SizedBox(height: AppSpace.s1),
          ],
        ],
      ),
    );
  }
}

String _glyph(String kind) => switch (kind) {
  'aggregation' => '◇',
  'composition' => '◆',
  'dependency' => '⇢',
  _ => '→',
};

String _kindName(String kind) => switch (kind) {
  'aggregation' => 'chứa (aggregation)',
  'composition' => 'sở hữu (composition)',
  'dependency' => 'phụ thuộc (dependency)',
  _ => 'liên kết (association)',
};

class _RelationRow extends StatelessWidget {
  const _RelationRow({required this.relation, required this.self});

  final DiagramRelation relation;
  final String self;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = relation;
    final otherIsFrom = r.to == self;
    final other = otherIsFrom ? r.from : r.to;
    return Padding(
      key: Key('diagram-rel-${r.from}-${r.to}'),
      padding: const EdgeInsets.only(top: AppSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _glyph(r.kind),
                style: AppText.title.copyWith(color: p.primary),
              ),
              const SizedBox(width: AppSpace.s2),
              Expanded(
                child: Text(
                  '${_kindName(r.kind)} · ${r.label}',
                  style: AppText.caption.copyWith(color: p.inkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.s1),
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: _boxDeco(p),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(name: other),
                if (otherIsFrom)
                  for (final m in r.via)
                    Padding(
                      key: Key('diagram-via-$other-$m'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.s2,
                        vertical: 2,
                      ),
                      child: Text(
                        '$m()',
                        style: AppText.code.copyWith(color: p.ink),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
