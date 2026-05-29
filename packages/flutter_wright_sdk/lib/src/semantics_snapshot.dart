// ignore_for_file: deprecated_member_use
//
// `SemanticsData.hasFlag` 在 Flutter 3.32 后被 @Deprecated,但其替代
// (`flagsCollection` / `SemanticsFlags`)在 Flutter 3.24 不存在 —— 本包声明
// `flutter: >=3.24.0`。`hasFlag` 在 3.24–3.44 均可用;此 ignore 让较新 SDK 上
// `flutter analyze` 保持干净,同时不破坏 3.24 兼容。
import 'package:flutter/rendering.dart';

/// 把活的 Flutter Semantics(无障碍)树序列化成 Playwright 风格 YAML,并把
/// `ref` 解析回节点。`ref` = `s<SemanticsNode.id>`;**临时**:只有最近一次
/// [serialize] 发出过的 ref 才能 [resolve](与 Playwright 行为一致)。
class SemanticsSnapshot {
  SemanticsSnapshot._();

  static final Set<int> _liveRefs = <int>{};

  static String serialize() {
    _liveRefs.clear();
    final StringBuffer buffer = StringBuffer();
    for (final RenderView view in RendererBinding.instance.renderViews) {
      final SemanticsNode? root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root == null) continue;
      _writeNode(root, buffer, 0);
    }
    final String out = buffer.toString();
    return out.isEmpty ? '# (no semantics — is the app mounted?)' : out;
  }

  static SemanticsNode? resolve(String ref) {
    final int? id = _parseRef(ref);
    if (id == null || !_liveRefs.contains(id)) return null;
    for (final RenderView view in RendererBinding.instance.renderViews) {
      final SemanticsNode? root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root == null) continue;
      final SemanticsNode? found = _findById(root, id);
      if (found != null) return found;
    }
    return null;
  }

  static bool containsText(String needle) {
    for (final RenderView view in RendererBinding.instance.renderViews) {
      final SemanticsNode? root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null && _containsText(root, needle)) return true;
    }
    return false;
  }

  static int? _parseRef(String ref) =>
      ref.startsWith('s') ? int.tryParse(ref.substring(1)) : null;

  static void _writeNode(SemanticsNode node, StringBuffer buffer, int depth) {
    final SemanticsData data = node.getSemanticsData();
    final String? role = _roleOf(data);
    final String label = _escape(data.label);
    final String value = _escape(data.value);
    final bool actionable = _isActionable(data);

    int childDepth = depth;
    if (role != null || label.isNotEmpty || actionable) {
      final StringBuffer line =
          StringBuffer('${'  ' * depth}- ${role ?? 'node'}');
      if (label.isNotEmpty) line.write(' "$label"');
      if (value.isNotEmpty) line.write(' value="$value"');
      if (actionable) {
        _liveRefs.add(node.id);
        line.write(' [ref=s${node.id}]');
      }
      buffer.writeln(line.toString());
      childDepth = depth + 1;
    }
    node.visitChildren((SemanticsNode child) {
      _writeNode(child, buffer, childDepth);
      return true;
    });
  }

  static String? _roleOf(SemanticsData d) {
    if (d.hasFlag(SemanticsFlag.isTextField)) return 'textfield';
    if (d.hasFlag(SemanticsFlag.isButton)) return 'button';
    if (d.hasFlag(SemanticsFlag.isHeader)) return 'header';
    if (d.hasFlag(SemanticsFlag.isImage)) return 'image';
    if (d.hasFlag(SemanticsFlag.isLink)) return 'link';
    if (d.hasFlag(SemanticsFlag.hasCheckedState)) return 'checkbox';
    return null;
  }

  static bool _isActionable(SemanticsData d) =>
      d.hasAction(SemanticsAction.tap) ||
      d.hasAction(SemanticsAction.longPress) ||
      d.hasAction(SemanticsAction.scrollUp) ||
      d.hasAction(SemanticsAction.scrollDown) ||
      d.hasAction(SemanticsAction.scrollLeft) ||
      d.hasAction(SemanticsAction.scrollRight) ||
      d.hasAction(SemanticsAction.setText);

  static String _escape(String s) =>
      s.replaceAll('\n', ' ').replaceAll('"', r'\"').trim();

  static SemanticsNode? _findById(SemanticsNode node, int id) {
    if (node.id == id) return node;
    SemanticsNode? result;
    node.visitChildren((SemanticsNode child) {
      result ??= _findById(child, id);
      return result == null;
    });
    return result;
  }

  static bool _containsText(SemanticsNode node, String needle) {
    final SemanticsData d = node.getSemanticsData();
    if (d.label.contains(needle) || d.value.contains(needle)) return true;
    bool found = false;
    node.visitChildren((SemanticsNode child) {
      if (_containsText(child, needle)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }
}
