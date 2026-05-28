import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// 经 [SemanticsAction] 在已解析节点上驱动交互 —— 与 OS 无障碍系统同一条路径。
/// v1 不含合成 pointer 兜底:节点未暴露对应 action 时返回 false。
class SemanticsActions {
  SemanticsActions._();

  static bool tap(SemanticsNode node) => _perform(node, SemanticsAction.tap);

  static bool longPress(SemanticsNode node) =>
      _perform(node, SemanticsAction.longPress);

  static bool scroll(SemanticsNode node, String dir) {
    final SemanticsAction? action = switch (dir) {
      'up' => SemanticsAction.scrollUp,
      'down' => SemanticsAction.scrollDown,
      'left' => SemanticsAction.scrollLeft,
      'right' => SemanticsAction.scrollRight,
      _ => null,
    };
    if (action == null) return false;
    return _perform(node, action);
  }

  /// 把文本注入 [node] 对应的输入框。
  ///
  /// Flutter 3.44 的 TextField/EditableText 语义节点并不暴露
  /// [SemanticsAction.setText](actions 位掩码仅 tap+focus),因此走无障碍
  /// 路径不可行。改用「几何匹配」:把 [node] 的全局矩形与页面上所有
  /// [EditableTextState] 的全局矩形比对,命中后直接调用
  /// [EditableTextState.userUpdateTextEditingValue] 注入文本 —— 该方法会同步
  /// 更新 controller 并触发 onChanged,对 Unicode/中文安全。
  /// 节点不是输入框(如按钮、纯文本)时返回 false。
  static bool setText(SemanticsNode node, String text) {
    final EditableTextState? editable = _findEditable(node);
    if (editable == null) return false;
    editable.widget.focusNode.requestFocus();
    editable.userUpdateTextEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
      SelectionChangedCause.keyboard,
    );
    return true;
  }

  /// 用全局矩形重叠面积把语义 [node] 映射回对应的 [EditableTextState]。
  /// 遍历整棵元素树收集所有可见的 EditableText,选与 node 重叠面积最大者;
  /// 无重叠则返回 null(非输入节点)。
  static EditableTextState? _findEditable(SemanticsNode node) {
    final Element? root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    final Rect target = _globalRect(node);
    EditableTextState? best;
    double bestArea = 0;
    void visit(Element element) {
      final State? state = element is StatefulElement ? element.state : null;
      if (state is EditableTextState) {
        final Rect? rect = _renderGlobalRect(state.context.findRenderObject());
        if (rect != null) {
          final double area = _overlapArea(rect, target);
          if (area > bestArea) {
            bestArea = area;
            best = state;
          }
        }
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    return bestArea > 0 ? best : null;
  }

  /// 把语义 [node] 的局部矩形沿 parent 链累乘各级 transform 得到**物理像素**全局
  /// 矩形,再除以 devicePixelRatio 归一到**逻辑像素**。
  ///
  /// 语义树根节点的 transform 含 DPR 缩放(逻辑→物理),而 [RenderBox.localToGlobal]
  /// 返回的是逻辑像素;不归一会导致两套坐标系错位、几何匹配命中错误输入框。
  /// DPR 各向同性,对最终矩形整体相除即可。
  static Rect _globalRect(SemanticsNode node) {
    Matrix4 transform = Matrix4.identity();
    SemanticsNode? current = node;
    while (current != null) {
      final Matrix4? local = current.transform;
      if (local != null) {
        transform = Matrix4.copy(local)..multiply(transform);
      }
      current = current.parent;
    }
    final Rect physical = MatrixUtils.transformRect(transform, node.rect);
    final double dpr = WidgetsBinding
            .instance.platformDispatcher.implicitView?.devicePixelRatio ??
        1.0;
    if (dpr == 1.0) return physical;
    return Rect.fromLTRB(physical.left / dpr, physical.top / dpr,
        physical.right / dpr, physical.bottom / dpr);
  }

  /// 取 [RenderBox] 的全局矩形;非 RenderBox 或未布局时返回 null。
  static Rect? _renderGlobalRect(RenderObject? renderObject) {
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final Offset origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  /// 两个全局矩形的重叠面积(无重叠为 0)。
  static double _overlapArea(Rect a, Rect b) {
    final Rect i = a.intersect(b);
    if (i.isEmpty || i.width <= 0 || i.height <= 0) return 0;
    return i.width * i.height;
  }

  static bool _perform(SemanticsNode node, SemanticsAction action) {
    final SemanticsOwner? owner = node.owner;
    if (owner == null) return false;
    if (!node.getSemanticsData().hasAction(action)) return false;
    owner.performAction(node.id, action);
    return true;
  }
}
