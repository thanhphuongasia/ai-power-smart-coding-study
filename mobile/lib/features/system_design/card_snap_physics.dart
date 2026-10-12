/// Physics cho màn đọc System Design: một cú vuốt (fling) chỉ đi tới card kế
/// tiếp thay vì trôi xa theo quán tính.
///
/// INV-02: đích của một cú vuốt không bao giờ cách vị trí hiện tại quá
/// [kSdSnapMaxViewportFraction] chiều cao viewport, nên nội dung chưa từng hiện
/// ra không bị bỏ qua (card cao hơn màn hình được đọc bằng nhiều lần vuốt).
/// INV-04: bảng mốc do màn đọc cung cấp, cùng bảng với menu nhảy section.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Vận tốc (px/s) tối thiểu để coi là fling; thấp hơn → cuộn tự do như cũ.
const double kSdSnapMinFlingVelocity = 300;

/// Một cú vuốt đi tối đa phần này của chiều cao viewport.
const double kSdSnapMaxViewportFraction = 0.9;

/// Sai số (px) khi coi vị trí hiện tại "đang ở" một mốc.
const double _kAnchorEpsilon = 1;

class SdCardSnapPhysics extends ScrollPhysics {
  /// [anchors] trả về offset cuộn tại đó đỉnh card chạm đỉnh viewport, sắp tăng
  /// dần. Gọi lại mỗi lần người dùng thả tay nên luôn theo layout hiện tại.
  /// Truyền một hàm ổn định (tearoff) để physics so sánh bằng nhau giữa các lần
  /// build.
  const SdCardSnapPhysics({super.parent, required this.anchors});

  final List<double> Function() anchors;

  @override
  SdCardSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      SdCardSnapPhysics(parent: buildParent(ancestor), anchors: anchors);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Đang kéo quá biên (iOS) hoặc vận tốc nhỏ: để physics mặc định lo.
    if (position.outOfRange || velocity.abs() < kSdSnapMinFlingVelocity) {
      return super.createBallisticSimulation(position, velocity);
    }
    final target = snapTarget(
      pixels: position.pixels,
      velocity: velocity,
      viewport: position.viewportDimension,
      minExtent: position.minScrollExtent,
      maxExtent: position.maxScrollExtent,
      anchors: anchors(),
    );
    if ((target - position.pixels).abs() < _kAnchorEpsilon) return null;
    return _SnapSimulation(position.pixels, target, position.viewportDimension);
  }

  /// Đích của cú vuốt: mốc kế tiếp theo chiều vuốt, bị chặn bởi 0,9 viewport
  /// và kẹp trong [minExtent, maxExtent]. Tách riêng để test được.
  static double snapTarget({
    required double pixels,
    required double velocity,
    required double viewport,
    required double minExtent,
    required double maxExtent,
    required List<double> anchors,
  }) {
    final reach = viewport * kSdSnapMaxViewportFraction;
    double target;
    if (velocity > 0) {
      // Hết mốc → đi tới cuối nội dung (vẫn bị chặn bởi reach).
      target = maxExtent;
      for (final a in anchors) {
        if (a > pixels + _kAnchorEpsilon) {
          target = a;
          break;
        }
      }
      target = math.min(target, pixels + reach);
    } else {
      target = minExtent;
      for (var i = anchors.length - 1; i >= 0; i--) {
        if (anchors[i] < pixels - _kAnchorEpsilon) {
          target = anchors[i];
          break;
        }
      }
      target = math.max(target, pixels - reach);
    }
    return target.clamp(minExtent, maxExtent);
  }
}

/// Chạy từ [from] tới đúng [to] bằng đường ease-out ngắn, không vượt đích.
class _SnapSimulation extends Simulation {
  _SnapSimulation(this.from, this.to, double viewport)
    : _seconds =
          (0.2 + 0.2 * ((to - from).abs() / math.max(viewport, 1)).clamp(0, 1))
              .toDouble();

  final double from;
  final double to;
  final double _seconds;

  // ease-out cubic: s(u) = 1 - (1-u)^3
  @override
  double x(double time) {
    final u = (time / _seconds).clamp(0.0, 1.0);
    final r = 1 - u;
    return from + (to - from) * (1 - r * r * r);
  }

  @override
  double dx(double time) {
    final u = (time / _seconds).clamp(0.0, 1.0);
    final r = 1 - u;
    return (to - from) * 3 * r * r / _seconds;
  }

  @override
  bool isDone(double time) => time >= _seconds;
}
