// Ball layout editor — single-file implementation (see billiards_app_spec.md §3).

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- Game / ball models ---

enum GameMode {
  nine('9', 9),
  ten('10', 10),
  fifteen('15', 15);

  const GameMode(this.storageKey, this.objectBallCount);
  final String storageKey;
  final int objectBallCount;

  int get totalBalls => objectBallCount + 1;
}

class BallDefinition {
  const BallDefinition({
    required this.id,
    required this.label,
    required this.fill,
    required this.stripe,
  });

  final int id;
  final String label;
  final Color fill;
  final bool stripe;

  static List<BallDefinition> forMode(GameMode mode) {
    final cue = const BallDefinition(id: 0, label: '●', fill: Color(0xFFFFFFFF), stripe: false);
    final out = <BallDefinition>[cue];
    for (var i = 1; i <= mode.objectBallCount; i++) {
      out.add(BallDefinition(
        id: i,
        label: '$i',
        fill: _baseColor(i),
        stripe: i >= 9,
      ));
    }
    return out;
  }

  static Color _baseColor(int n) {
    final m = <int, Color>{
      1: const Color(0xFFF5C518),
      2: const Color(0xFF1565C0),
      3: const Color(0xFFC62828),
      4: const Color(0xFF6A1B9A),
      5: const Color(0xFFE65100),
      6: const Color(0xFF1B5E20),
      7: const Color(0xFF6D1A1A),
      8: const Color(0xFF1A1A1A),
    };
    if (n <= 8) {
      return m[n]!;
    }
    // 9〜15 は 1〜7 と同色
    return m[n - 8]!;
  }
}

class BallInstance {
  BallInstance({
    required this.def,
    required this.x,
    required this.y,
    this.onTable = false,
  });

  final BallDefinition def;
  double x;
  double y;
  bool onTable;

  BallInstance copy() => BallInstance(def: def, x: x, y: y, onTable: onTable);

  Map<String, dynamic> toJson() => {
        'id': def.id,
        'n': def.label,
        'x': x,
        'y': y,
      };

  static BallInstance? fromJson(Map<String, dynamic> j, GameMode mode) {
    final id = j['id'] as int?;
    if (id == null) return null;
    final defs = BallDefinition.forMode(mode);
    final def = defs.cast<BallDefinition?>().firstWhere((d) => d!.id == id, orElse: () => null);
    if (def == null) return null;
    return BallInstance(
      def: def,
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      onTable: true,
    );
  }
}

// --- Trajectory ---

class TrajectoryLine {
  TrajectoryLine({
    required this.cueBallId,
    required this.objBallId,
    required this.contact,
    this.cueAnchor = Offset.zero,
    this.objAnchor = Offset.zero,
    this.cueStartOverride,
    this.cueEndOverride,
    this.cueBounceEndOverride,
    this.objEndOverride,
    this.objBounceEndOverride,
  });

  int cueBallId;
  int objBallId;
  Offset contact;
  Offset cueAnchor;
  Offset objAnchor;
  Offset? cueStartOverride;
  Offset? cueEndOverride;
  Offset? cueBounceEndOverride;
  Offset? objEndOverride;
  Offset? objBounceEndOverride;

  TrajectoryLine copy() => TrajectoryLine(
        cueBallId: cueBallId,
        objBallId: objBallId,
        contact: contact,
        cueAnchor: cueAnchor,
        objAnchor: objAnchor,
        cueStartOverride: cueStartOverride,
        cueEndOverride: cueEndOverride,
        cueBounceEndOverride: cueBounceEndOverride,
        objEndOverride: objEndOverride,
        objBounceEndOverride: objBounceEndOverride,
      );

  Map<String, dynamic> toJson() => {
        'cueBallId': cueBallId,
        'objBallId': objBallId,
        'contact': {'x': contact.dx, 'y': contact.dy},
        'cueAnchor': {'ox': cueAnchor.dx, 'oy': cueAnchor.dy},
        'objAnchor': {'ox': objAnchor.dx, 'oy': objAnchor.dy},
        if (cueStartOverride != null)
          'cueStartOverride': {'x': cueStartOverride!.dx, 'y': cueStartOverride!.dy},
        if (cueEndOverride != null)
          'cueEndOverride': {'x': cueEndOverride!.dx, 'y': cueEndOverride!.dy},
        if (cueBounceEndOverride != null)
          'cueBounceEndOverride': {
            'x': cueBounceEndOverride!.dx,
            'y': cueBounceEndOverride!.dy,
          },
        if (objEndOverride != null)
          'objEndOverride': {'x': objEndOverride!.dx, 'y': objEndOverride!.dy},
        if (objBounceEndOverride != null)
          'objBounceEndOverride': {
            'x': objBounceEndOverride!.dx,
            'y': objBounceEndOverride!.dy,
          },
      };

  static TrajectoryLine? fromJson(Map<String, dynamic> j) {
    try {
      final c = j['contact'] as Map<String, dynamic>;
      final ca = j['cueAnchor'] as Map<String, dynamic>;
      final oa = j['objAnchor'] as Map<String, dynamic>;
      Offset? ov;
      final co = j['cueStartOverride'];
      if (co is Map<String, dynamic>) {
        ov = Offset((co['x'] as num).toDouble(), (co['y'] as num).toDouble());
      }
      Offset? cueEnd;
      final ce = j['cueEndOverride'];
      if (ce is Map<String, dynamic>) {
        cueEnd = Offset((ce['x'] as num).toDouble(), (ce['y'] as num).toDouble());
      }
      Offset? objEnd;
      final oe = j['objEndOverride'];
      if (oe is Map<String, dynamic>) {
        objEnd = Offset((oe['x'] as num).toDouble(), (oe['y'] as num).toDouble());
      }
      Offset? objBounceEnd;
      final obe = j['objBounceEndOverride'];
      if (obe is Map<String, dynamic>) {
        objBounceEnd = Offset((obe['x'] as num).toDouble(), (obe['y'] as num).toDouble());
      }
      Offset? cueBounceEnd;
      final cbe = j['cueBounceEndOverride'];
      if (cbe is Map<String, dynamic>) {
        cueBounceEnd = Offset((cbe['x'] as num).toDouble(), (cbe['y'] as num).toDouble());
      }
      return TrajectoryLine(
        cueBallId: j['cueBallId'] as int,
        objBallId: j['objBallId'] as int,
        contact: Offset((c['x'] as num).toDouble(), (c['y'] as num).toDouble()),
        cueAnchor: Offset((ca['ox'] as num).toDouble(), (ca['oy'] as num).toDouble()),
        objAnchor: Offset((oa['ox'] as num).toDouble(), (oa['oy'] as num).toDouble()),
        cueStartOverride: ov,
        cueEndOverride: cueEnd,
        cueBounceEndOverride: cueBounceEnd,
        objEndOverride: objEnd,
        objBounceEndOverride: objBounceEnd,
      );
    } catch (_) {
      return null;
    }
  }
}

class TrajectoryGeometry {
  TrajectoryGeometry({
    required this.feltNorm,
    required this.ballRadiusNorm,
    required this.cueCenter,
    required this.objCenter,
    required this.contact,
    required this.cueDir,
    required this.objDir,
    required this.cueEnd,
    required this.cueBounceEnd,
    required this.cueHitCushion,
    required this.objEnd,
    required this.objBounceEnd,
    required this.objHitCushion,
    required this.cueControl,
    required this.objControl,
    required this.skipObjPost,
  });

  final Rect feltNorm;
  final double ballRadiusNorm;
  final Offset cueCenter;
  final Offset objCenter;
  final Offset contact;
  final Offset cueDir;
  final Offset objDir;
  final Offset cueEnd;
  final Offset cueBounceEnd;
  final bool cueHitCushion;
  final Offset objEnd;
  final Offset objBounceEnd;
  final bool objHitCushion;
  final Offset cueControl;
  final Offset objControl;
  final bool skipObjPost;

  static double _brNorm(Rect felt) => felt.width * 0.015;

  static Offset _norm(Offset o, Rect felt) =>
      Offset((o.dx - felt.left) / felt.width, (o.dy - felt.top) / felt.height);

  static Offset _toPx(Offset norm, Rect felt) =>
      Offset(felt.left + norm.dx * felt.width, felt.top + norm.dy * felt.height);

  /// Returns true if [norm] lies within pocket capture of any pocket (normalized felt coords).
  static bool isNearPocket(Offset norm, Rect feltNorm) {
    final centers = BilliardsTablePainter.pocketCentersForFeltRect(
      Rect.fromLTWH(0, 0, feltNorm.width, feltNorm.height),
    );
    final pr = BilliardsTablePainter.pocketRadiusForFeltRect(
      Rect.fromLTWH(0, 0, feltNorm.width, feltNorm.height),
    );
    for (final c in centers) {
      final pn = Offset(c.dx / feltNorm.width, c.dy / feltNorm.height);
      if ((norm - pn).distance <= pr / feltNorm.width * 1.2) return true;
    }
    return false;
  }

  static TrajectoryGeometry compute({
    required Rect felt,
    required Offset cueCenterPx,
    required Offset objCenterPx,
    Offset? contactOverrideNorm,
    Offset cueAnchorNorm = Offset.zero,
    Offset objAnchorNorm = Offset.zero,
    Offset? cueStartOverrideNorm,
    Offset? cueEndOverrideNorm,
    Offset? cueBounceEndOverrideNorm,
    Offset? objEndOverrideNorm,
    Offset? objBounceEndOverrideNorm,
  }) {
    final feltNorm = _normRect(felt);
    final br = _brNorm(felt);
    final cueN = _norm(cueCenterPx, felt);
    final objN = _norm(objCenterPx, felt);
    final cueStartPx = cueStartOverrideNorm == null ? cueCenterPx : _toPx(cueStartOverrideNorm, felt);

    // 初期接触点は「的球 -> 最寄りポケット」方向を基準に置く。
    // これで、手球→的球タップ直後の赤丸が狙いポケット基準の位置になる。
    final pocketCenters = _pocketCentersPx(felt);
    final cueToObj = objCenterPx - cueCenterPx;
    Offset nearestPocket = Offset(felt.center.dx, felt.top);
    var bestDist = double.infinity;
    var foundFeasiblePocket = false;
    for (final p in pocketCenters) {
      final objToPocket = p - objCenterPx;
      // 物理的に狙える候補のみ: 物体球での入射角が90度以下。
      final feasible = cueToObj.dot(objToPocket) >= 0;
      if (!feasible) continue;
      final d = objToPocket.distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        nearestPocket = p;
        foundFeasiblePocket = true;
      }
    }
    // 90度以内の候補がゼロの場合のみ、従来どおり単純最短へフォールバック。
    if (!foundFeasiblePocket) {
      for (final p in pocketCenters) {
        final d = (p - objCenterPx).distanceSquared;
        if (d < bestDist) {
          bestDist = d;
          nearestPocket = p;
        }
      }
    }
    final toPocketPx = nearestPocket - objCenterPx;
    final toPocketLen = toPocketPx.distance;
    final toPocketUnit = toPocketLen < 1e-9 ? const Offset(0, -1) : toPocketPx / toPocketLen;
    final contactCorrect = objCenterPx - toPocketUnit * (br * 2);
    final contactRawPx =
        contactOverrideNorm == null ? contactCorrect : _toPx(contactOverrideNorm, felt);
    final fromObjToContact = contactRawPx - objCenterPx;
    final fromObjLen = fromObjToContact.distance;
    final fromObjUnit = fromObjLen < 1e-9 ? -toPocketUnit : fromObjToContact / fromObjLen;
    // 接触点（赤丸）は常に「的球中心から2R」の接触リング上に置く（めり込み防止）。
    final contactUsePx = objCenterPx + fromObjUnit * (br * 2);

    final objDirPx = objCenterPx - contactUsePx;
    final objDirLen = objDirPx.distance;
    final objDirUnit = objDirLen < 1e-9 ? const Offset(0, 1) : objDirPx / objDirLen;

    // 物理則: 同質量球の衝突後、手球速度は「法線方向成分を失い、接線方向のみ残る」。
    // これにより手球進行方向と的球進行方向が常に90度になる。
    final incomingPx = contactUsePx - cueStartPx;
    final tangentPx = incomingPx - objDirUnit * incomingPx.dot(objDirUnit);
    final tangentLen = tangentPx.distance;
    final cueDirUnit = tangentLen < 1e-9
        ? Offset(-objDirUnit.dy, objDirUnit.dx)
        : tangentPx / tangentLen;

    final cueLen = _rayToFeltEdgePx(contactUsePx, cueDirUnit, felt);
    final cueAutoEndPx = contactUsePx + cueDirUnit * cueLen;
    final objLen = _rayToFeltEdgePx(contactUsePx, objDirUnit, felt);
    final objAutoEndPx = contactUsePx + objDirUnit * objLen;
    final cueEndPx = cueEndOverrideNorm == null ? cueAutoEndPx : _toPx(cueEndOverrideNorm, felt);
    final objEndBasePx = objEndOverrideNorm == null ? objAutoEndPx : _toPx(objEndOverrideNorm, felt);
    // 的球の進路上でポケット捕捉に入る最初の点を検出し、そこで的球ラインを打ち切る。
    final pocketHitPx = _firstPocketHitOnSegment(contactUsePx, objEndBasePx, felt);
    final skipObjPost =
        pocketHitPx != null || isNearPocketPx(objEndBasePx, felt) || isNearPocketPx(objCenterPx, felt);
    final objEndPx = pocketHitPx ?? objEndBasePx;

    final cueEdge = _edgeAtPointPx(cueEndPx, felt);
    final cueHitCushion = cueEdge != null;
    final cueBounceDir = cueEdge == null ? Offset.zero : _reflect(cueDirUnit, cueEdge);
    final cueBounceLen =
        cueHitCushion ? _rayToFeltEdgePx(cueEndPx, cueBounceDir, felt) : 0.0;
    final cueBounceAutoEndPx = cueEndPx + cueBounceDir * cueBounceLen;
    final cueBounceEndPx =
        cueBounceEndOverrideNorm == null ? cueBounceAutoEndPx : _toPx(cueBounceEndOverrideNorm, felt);
    final objEdge = _edgeAtPointPx(objEndPx, felt);
    final objHitCushion = !skipObjPost && objEdge != null;
    final objBounceDir = objEdge == null ? Offset.zero : _reflect(objDirUnit, objEdge);
    final objBounceLen =
        objHitCushion ? _rayToFeltEdgePx(objEndPx, objBounceDir, felt) : 0.0;
    final objBounceAutoEndPx = objEndPx + objBounceDir * objBounceLen;
    final objBounceEndPx =
        objBounceEndOverrideNorm == null ? objBounceAutoEndPx : _toPx(objBounceEndOverrideNorm, felt);

    final midCuePx = (contactUsePx + cueEndPx) / 2;
    final midObjPx = (contactUsePx + objEndPx) / 2;
    final cueControlPx =
        midCuePx + Offset(cueAnchorNorm.dx * felt.width, cueAnchorNorm.dy * felt.height);
    final objControlPx =
        midObjPx + Offset(objAnchorNorm.dx * felt.width, objAnchorNorm.dy * felt.height);

    return TrajectoryGeometry(
      feltNorm: feltNorm,
      ballRadiusNorm: br / felt.width,
      cueCenter: cueN,
      objCenter: objN,
      contact: _norm(contactUsePx, felt),
      cueDir: cueDirUnit,
      objDir: objDirUnit,
      cueEnd: _norm(cueEndPx, felt),
      cueBounceEnd: _norm(cueBounceEndPx, felt),
      cueHitCushion: cueHitCushion,
      objEnd: _norm(objEndPx, felt),
      objBounceEnd: _norm(objBounceEndPx, felt),
      objHitCushion: objHitCushion,
      cueControl: _norm(cueControlPx, felt),
      objControl: _norm(objControlPx, felt),
      skipObjPost: skipObjPost,
    );
  }

  static Rect _normRect(Rect felt) {
    return Rect.fromLTWH(0, 0, 1, 1);
  }

  static double _rayToFeltEdgePx(Offset p, Offset dir, Rect felt) {
    var tMax = double.infinity;
    void hit(double t) {
      if (t > 1e-9 && t < tMax) tMax = t;
    }

    if (dir.dx.abs() > 1e-9) {
      hit((felt.left - p.dx) / dir.dx);
      hit((felt.right - p.dx) / dir.dx);
    }
    if (dir.dy.abs() > 1e-9) {
      hit((felt.top - p.dy) / dir.dy);
      hit((felt.bottom - p.dy) / dir.dy);
    }
    if (!tMax.isFinite || tMax == double.infinity) return 0;
    return tMax;
  }

  static bool isNearPocketPx(Offset pointPx, Rect felt) {
    final centers = _pocketCentersPx(felt);
    final pr = _pocketCaptureRadiusPx(felt);
    for (final c in centers) {
      if ((pointPx - c).distance <= pr) return true;
    }
    return false;
  }

  static Offset? _firstPocketHitOnSegment(Offset a, Offset b, Rect felt) {
    final d = b - a;
    final len = d.distance;
    if (len < 1e-9) return null;
    final u = d / len;
    final centers = _pocketCentersPx(felt);
    final pr = _pocketCaptureRadiusPx(felt);

    double? bestT;
    Offset? bestPocketCenter;
    for (final c in centers) {
      final rel = c - a;
      final t = rel.dot(u);
      if (t < -pr || t > len + pr) continue;
      final closest = a + u * t.clamp(0.0, len);
      if ((closest - c).distance > pr) continue;
      if (bestT == null || t < bestT) {
        bestT = t;
        bestPocketCenter = c;
      }
    }
    return bestPocketCenter;
  }

  static double _pocketCaptureRadiusPx(Rect felt) =>
      BilliardsTablePainter.pocketRadiusForFeltRect(felt);

  static List<Offset> _pocketCentersPx(Rect felt) {
    final local = BilliardsTablePainter.pocketCentersForFeltRect(
      Rect.fromLTWH(0, 0, felt.width, felt.height),
    );
    return local.map((c) => Offset(felt.left + c.dx, felt.top + c.dy)).toList(growable: false);
  }

  static _Edge? _edgeAtPointPx(Offset pointPx, Rect felt) {
    const threshold = 1.5;
    if ((pointPx.dx - felt.left).abs() <= threshold) return _Edge.left;
    if ((pointPx.dx - felt.right).abs() <= threshold) return _Edge.right;
    if ((pointPx.dy - felt.top).abs() <= threshold) return _Edge.top;
    if ((pointPx.dy - felt.bottom).abs() <= threshold) return _Edge.bottom;
    return null;
  }

  static Offset _reflect(Offset incoming, _Edge edge) {
    switch (edge) {
      case _Edge.left:
      case _Edge.right:
        return Offset(-incoming.dx, incoming.dy);
      case _Edge.top:
      case _Edge.bottom:
        return Offset(incoming.dx, -incoming.dy);
    }
  }
}

enum _Edge { left, right, top, bottom }

extension _OffsetDot on Offset {
  double dot(Offset o) => dx * o.dx + dy * o.dy;
}

// --- Table geometry (static helpers + painter) ---

class BilliardsTablePainter extends CustomPainter {
  BilliardsTablePainter({
    required this.feltRect,
    this.label,
  });

  final Rect feltRect;
  final String? label;

  static const Color frameColor = Color(0xFF7A5C3A);
  static const Color cushionColor = Color(0xFF5A3E1E);
  static const Color feltColor = Color(0xFF0096C7);

  /// Fits felt into [size] while preserving 2:1 table ratio.
  /// Landscape container -> landscape table (2:1), portrait container -> portrait table (1:2).
  static Rect feltRectForSize(Size size) {
    final targetAspect = size.width >= size.height ? 2.0 : 0.5;
    double w = size.width;
    double h = size.height;
    if (w / h > targetAspect) {
      w = h * targetAspect;
    } else {
      h = w / targetAspect;
    }
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    final raw = Rect.fromLTWH(left, top, w, h);

    // paint() 側で外枠/クッションを felt より外に描くため、
    // felt を少し内側に収めてテーブル全体が必ず表示されるようにする。
    final pad = math.min(raw.width, raw.height) * 0.08;
    final safe = raw.deflate(pad);
    if (safe.width <= 0 || safe.height <= 0) {
      return raw;
    }
    return safe;
  }

  static double pocketRadiusForFeltRect(Rect felt) => felt.width * 0.028;

  /// Local coordinates relative to felt's top-left (0,0) — width = felt.width, height = felt.height.
  static List<Offset> pocketCentersForFeltRect(Rect felt) {
    final w = felt.width;
    final h = felt.height;
    return [
      Offset(0, 0),
      Offset(w / 2, 0),
      Offset(w, 0),
      Offset(0, h),
      Offset(w / 2, h),
      Offset(w, h),
    ];
  }

  static Path _chamferedFeltPath(Rect felt, double chamfer) {
    final p = Path();
    final f = felt;
    p.moveTo(f.left + chamfer, f.top);
    p.lineTo(f.right - chamfer, f.top);
    p.lineTo(f.right, f.top + chamfer);
    p.lineTo(f.right, f.bottom - chamfer);
    p.lineTo(f.right - chamfer, f.bottom);
    p.lineTo(f.left + chamfer, f.bottom);
    p.lineTo(f.left, f.bottom - chamfer);
    p.lineTo(f.left, f.top + chamfer);
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final felt = feltRect;
    final frameFrac = 0.038;
    final frameW = math.min(size.width, size.height) * frameFrac;
    final outer = Rect.fromCenter(center: felt.center, width: felt.width + frameW * 4, height: felt.height + frameW * 4);
    final cushionRect = Rect.fromCenter(center: felt.center, width: felt.width + frameW * 2, height: felt.height + frameW * 2);

    final frameR = RRect.fromRectAndRadius(outer, const Radius.circular(6));
    canvas.drawRRect(frameR, Paint()..color = frameColor);

    canvas.drawRRect(
      RRect.fromRectAndRadius(cushionRect, const Radius.circular(4)),
      Paint()..color = cushionColor,
    );

    final chamfer = math.min(felt.width, felt.height) * 0.035;
    final feltPath = _chamferedFeltPath(felt, chamfer);
    canvas.save();
    canvas.clipPath(feltPath);
    canvas.drawPath(feltPath, Paint()..color = feltColor);

    _drawTexture(canvas, felt);
    _drawGrid(canvas, felt);
    _drawSpots(canvas, felt);
    canvas.restore();

    _drawPockets(canvas, felt, cushionRect, chamfer);

    if (label != null) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(felt.left + 4, felt.top + 4));
    }
  }

  void _drawTexture(Canvas canvas, Rect felt) {
    final paint = Paint()
      ..color = const Color.fromRGBO(0, 0, 0, 0.04)
      ..strokeWidth = 1;
    for (double x = felt.left; x < felt.right; x += 3) {
      canvas.drawLine(Offset(x, felt.top), Offset(x, felt.bottom), paint);
    }
  }

  void _drawGrid(Canvas canvas, Rect felt) {
    final paint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.13)
      ..strokeWidth = 1;
    final widthIsLong = felt.width >= felt.height;
    final xDiv = widthIsLong ? 8 : 4;
    final yDiv = widthIsLong ? 4 : 8;
    for (var i = 1; i < xDiv; i++) {
      final x = felt.left + felt.width * i / xDiv;
      canvas.drawLine(Offset(x, felt.top), Offset(x, felt.bottom), paint);
    }
    for (var j = 1; j < yDiv; j++) {
      final y = felt.top + felt.height * j / yDiv;
      canvas.drawLine(Offset(felt.left, y), Offset(felt.right, y), paint);
    }
  }

  void _drawSpots(Canvas canvas, Rect felt) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final cy = felt.center.dy;
    for (final q in [0.25, 0.5, 0.75]) {
      final ox = felt.left + felt.width * q;
      canvas.drawCircle(Offset(ox, cy), 2.5, paint);
    }
  }

  void _drawPockets(Canvas canvas, Rect felt, Rect cushionRect, double chamfer) {
    final pr = pocketRadiusForFeltRect(felt);
    final centersLocal = pocketCentersForFeltRect(
      Rect.fromLTWH(0, 0, felt.width, felt.height),
    );
    canvas.save();
    final bandPath = Path()
      ..addRect(cushionRect)
      ..addPath(_chamferedFeltPath(felt, chamfer), Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.clipPath(bandPath);

    for (final lc in centersLocal) {
      final c = Offset(felt.left + lc.dx, felt.top + lc.dy);
      canvas.drawCircle(
        c.translate(1, 1),
        pr,
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      canvas.drawCircle(c, pr, Paint()..color = const Color(0xFF111111));
      canvas.drawCircle(
        c,
        pr * 0.82,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = pr * 0.12
          ..color = const Color(0xFFD4AF37),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BilliardsTablePainter oldDelegate) =>
      oldDelegate.feltRect != feltRect || oldDelegate.label != label;
}

class TrajectoryPainter extends CustomPainter {
  TrajectoryPainter({
    required this.felt,
    required this.lines,
    required this.ballMap,
    this.draggingContactIndex,
    this.draggingCueAnchorIndex,
    this.draggingObjAnchorIndex,
  });

  final Rect felt;
  final List<TrajectoryLine> lines;
  final Map<int, BallInstance> ballMap;
  final int? draggingContactIndex;
  final int? draggingCueAnchorIndex;
  final int? draggingObjAnchorIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final chamfer = math.min(felt.width, felt.height) * 0.035;
    final feltPath = BilliardsTablePainter._chamferedFeltPath(felt, chamfer);
    final pocketCenters = BilliardsTablePainter.pocketCentersForFeltRect(
      Rect.fromLTWH(0, 0, felt.width, felt.height),
    ).map((c) => Offset(felt.left + c.dx, felt.top + c.dy));
    final pocketInRadius = BilliardsTablePainter.pocketRadiusForFeltRect(felt);
    final clipPath = Path()..addPath(feltPath, Offset.zero);
    for (final c in pocketCenters) {
      clipPath.addOval(Rect.fromCircle(center: c, radius: pocketInRadius));
    }
    canvas.save();
    // フェルト内 + ポケット穴(黒) にのみ軌道を描く。
    canvas.clipRect(felt);
    canvas.clipPath(clipPath);

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final cue = ballMap[line.cueBallId];
      final obj = ballMap[line.objBallId];
      if (cue == null || obj == null || !cue.onTable || !obj.onTable) continue;

      final prevCueEnd = i > 0 ? _endOfCueShot(lines[i - 1], ballMap, felt) : null;
      final geom = TrajectoryGeometry.compute(
        felt: felt,
        cueCenterPx: Offset(
          felt.left + cue.x * felt.width,
          felt.top + cue.y * felt.height,
        ),
        objCenterPx: Offset(
          felt.left + obj.x * felt.width,
          felt.top + obj.y * felt.height,
        ),
        contactOverrideNorm: line.contact,
        cueAnchorNorm: line.cueAnchor,
        objAnchorNorm: line.objAnchor,
        cueStartOverrideNorm: line.cueStartOverride ??
            (prevCueEnd != null
                ? Offset(
                    (prevCueEnd.dx - felt.left) / felt.width,
                    (prevCueEnd.dy - felt.top) / felt.height,
                  )
                : null),
        cueEndOverrideNorm: line.cueEndOverride,
        cueBounceEndOverrideNorm: line.cueBounceEndOverride,
        objEndOverrideNorm: line.objEndOverride,
        objBounceEndOverrideNorm: line.objBounceEndOverride,
      );

      final cStart = Offset(
        felt.left + (line.cueStartOverride?.dx ?? geom.cueCenter.dx) * felt.width,
        felt.top + (line.cueStartOverride?.dy ?? geom.cueCenter.dy) * felt.height,
      );
      final contact = Offset(
        felt.left + geom.contact.dx * felt.width,
        felt.top + geom.contact.dy * felt.height,
      );
      final cueEnd = Offset(
        felt.left + geom.cueEnd.dx * felt.width,
        felt.top + geom.cueEnd.dy * felt.height,
      );
      final cueBounceEnd = Offset(
        felt.left + geom.cueBounceEnd.dx * felt.width,
        felt.top + geom.cueBounceEnd.dy * felt.height,
      );
      final objEnd = Offset(
        felt.left + geom.objEnd.dx * felt.width,
        felt.top + geom.objEnd.dy * felt.height,
      );
      final objBounceEnd = Offset(
        felt.left + geom.objBounceEnd.dx * felt.width,
        felt.top + geom.objBounceEnd.dy * felt.height,
      );

      final cueCtrl = Offset(
        felt.left + geom.cueControl.dx * felt.width,
        felt.top + geom.cueControl.dy * felt.height,
      );
      final objCtrl = Offset(
        felt.left + geom.objControl.dx * felt.width,
        felt.top + geom.objControl.dy * felt.height,
      );

      final startPx = prevCueEnd != null && line.cueStartOverride == null ? prevCueEnd : cStart;

      _dashedLine(canvas, startPx, contact, const Color.fromRGBO(255, 255, 255, 0.75), 6, 4);
      _quadArrow(
        canvas,
        contact,
        cueCtrl,
        cueEnd,
        const Color.fromRGBO(255, 255, 255, 0.95),
        draggingCueAnchorIndex == i,
      );
      if (geom.cueHitCushion) {
        _dashedLine(
          canvas,
          cueEnd,
          cueBounceEnd,
          const Color.fromRGBO(255, 255, 255, 0.9),
          6,
          4,
        );
        canvas.drawCircle(
          cueBounceEnd,
          6,
          Paint()..color = const Color.fromRGBO(210, 240, 255, 0.95),
        );
      }
      _quadArrow(
        canvas,
        contact,
        objCtrl,
        objEnd,
        const Color.fromRGBO(255, 215, 0, 0.98),
        draggingObjAnchorIndex == i,
      );
      if (geom.objHitCushion) {
        _dashedLine(
          canvas,
          objEnd,
          objBounceEnd,
          const Color.fromRGBO(255, 220, 120, 0.95),
          6,
          4,
        );
      }

      final cpPaint = Paint()..color = const Color.fromRGBO(255, 70, 70, 0.95);
      canvas.drawCircle(contact, draggingContactIndex == i ? 9 : 7, cpPaint);

      final cueAn = Paint()..color = const Color.fromRGBO(140, 255, 90, 0.95);
      canvas.drawCircle(cueCtrl, draggingCueAnchorIndex == i ? 10 : 8, cueAn);
      canvas.drawCircle(
        cueEnd,
        6,
        Paint()..color = const Color.fromRGBO(210, 240, 255, 0.95),
      );

      final objAn = Paint()..color = const Color.fromRGBO(255, 215, 0, 0.98);
      canvas.drawCircle(objCtrl, draggingObjAnchorIndex == i ? 10 : 8, objAn);
      canvas.drawCircle(
        objEnd,
        6,
        Paint()..color = const Color.fromRGBO(255, 235, 170, 0.95),
      );
      if (geom.objHitCushion) {
        canvas.drawCircle(
          objBounceEnd,
          6,
          Paint()..color = const Color.fromRGBO(255, 220, 120, 0.95),
        );
      }
    }
    canvas.restore();
  }

  Offset? _endOfCueShot(TrajectoryLine line, Map<int, BallInstance> balls, Rect felt) {
    final cue = balls[line.cueBallId];
    final obj = balls[line.objBallId];
    if (cue == null || obj == null) return null;
    final geom = TrajectoryGeometry.compute(
      felt: felt,
      cueCenterPx: Offset(felt.left + cue.x * felt.width, felt.top + cue.y * felt.height),
      objCenterPx: Offset(felt.left + obj.x * felt.width, felt.top + obj.y * felt.height),
      contactOverrideNorm: line.contact,
      cueAnchorNorm: line.cueAnchor,
      objAnchorNorm: line.objAnchor,
      cueStartOverrideNorm: line.cueStartOverride,
      cueEndOverrideNorm: line.cueEndOverride,
      cueBounceEndOverrideNorm: line.cueBounceEndOverride,
      objEndOverrideNorm: line.objEndOverride,
      objBounceEndOverrideNorm: line.objBounceEndOverride,
    );
    return Offset(
      felt.left + geom.cueBounceEnd.dx * felt.width,
      felt.top + geom.cueBounceEnd.dy * felt.height,
    );
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Color col, double dash, double gap) {
    final paint = Paint()
      ..color = col
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final d = b - a;
    final len = d.distance;
    if (len < 1e-6) return;
    final u = d / len;
    var t = 0.0;
    var draw = true;
    while (t < len) {
      final seg = math.min(draw ? dash : gap, len - t);
      final p0 = a + u * t;
      final p1 = a + u * (t + seg);
      if (draw) c.drawLine(p0, p1, paint);
      t += seg;
      draw = !draw;
    }
  }

  void _quadArrow(Canvas c, Offset a, Offset ctrl, Offset end, Color col, bool emphasize) {
    final path = Path()..moveTo(a.dx, a.dy)..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
    final paint = Paint()
      ..color = col
      ..strokeWidth = emphasize ? 3 : 2
      ..style = PaintingStyle.stroke;
    _dashPath(c, path, paint, 5, 4);
    final tan = end - ctrl;
    final ang = math.atan2(tan.dy, tan.dx);
    final arrowLen = 12.0;
    final p1 = end - Offset(math.cos(ang - 0.45) * arrowLen, math.sin(ang - 0.45) * arrowLen);
    final p2 = end - Offset(math.cos(ang + 0.45) * arrowLen, math.sin(ang + 0.45) * arrowLen);
    c.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      Paint()..color = col,
    );
  }

  void _dashPath(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      var d = 0.0;
      var draw = true;
      while (d < m.length) {
        final len = draw ? dash : gap;
        final e = math.min(d + len, m.length);
        if (draw) {
          final e0 = m.extractPath(d, e);
          canvas.drawPath(e0, paint);
        }
        d = e;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(covariant TrajectoryPainter oldDelegate) => true;
}

// --- Saved layout document ---

class SavedBallLayout {
  SavedBallLayout({
    required this.id,
    required this.createdAt,
    required this.mode,
    required this.tag,
    required this.memo,
    required this.balls,
    required this.lines,
  });

  final String id;
  final String createdAt;
  final GameMode mode;
  final String tag;
  final String memo;
  final List<BallInstance> balls;
  final List<TrajectoryLine> lines;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'mode': mode.storageKey,
        'tag': tag,
        'memo': memo,
        'balls': balls.map((b) => b.toJson()).toList(),
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  static SavedBallLayout? fromJsonString(String s) {
    try {
      return fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static SavedBallLayout? fromJson(Map<String, dynamic> j) {
    try {
      final modeKey = j['mode'] as String;
      final mode = GameMode.values.firstWhere((e) => e.storageKey == modeKey);
      final balls = <BallInstance>[];
      for (final e in j['balls'] as List<dynamic>) {
        final b = BallInstance.fromJson(e as Map<String, dynamic>, mode);
        if (b != null) balls.add(b);
      }
      final lines = <TrajectoryLine>[];
      for (final e in j['lines'] as List<dynamic>) {
        final l = TrajectoryLine.fromJson(e as Map<String, dynamic>);
        if (l != null) lines.add(l);
      }
      return SavedBallLayout(
        id: j['id'] as String,
        createdAt: j['createdAt'] as String,
        mode: mode,
        tag: j['tag'] as String? ?? '',
        memo: j['memo'] as String? ?? '',
        balls: balls,
        lines: lines,
      );
    } catch (_) {
      return null;
    }
  }
}

// --- Screens ---

class BallLayoutEditorScreen extends StatefulWidget {
  const BallLayoutEditorScreen({
    super.key,
    this.initialLayout,
  });

  final SavedBallLayout? initialLayout;

  @override
  State<BallLayoutEditorScreen> createState() => _BallLayoutEditorScreenState();
}

class _BallLayoutEditorScreenState extends State<BallLayoutEditorScreen> {
  static const _prefKey = 'saved_ball_layouts';
  static const _doubleTapMs = 380;

  GameMode _mode = GameMode.nine;
  final _tagCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  /// `_applyMode` が `initState` 内で先に呼ばれるため、`late` だと未初期化参照になる。
  List<BallInstance> _balls = [];
  final List<TrajectoryLine> _lines = [];

  bool _trajMode = false;
  int? _selCueId;
  String _status = 'ドラッグで移動 / 380ms以内に2回タップでトレイへ';

  int? _dragBallId;
  int? _dragContactIdx;
  int? _dragCueAIdx;
  int? _dragObjAIdx;
  int? _dragCueEndIdx;
  int? _dragCueBounceEndIdx;
  int? _dragObjEndIdx;
  int? _dragObjBounceEndIdx;

  final Map<int, DateTime> _lastTap = {};

  final GlobalKey _tableStackKey = GlobalKey();
  Rect _felt = Rect.zero;

  @override
  void initState() {
    super.initState();
    _applyMode(GameMode.nine, resetPositions: false);
    final init = widget.initialLayout;
    if (init != null) {
      _mode = init.mode;
      _tagCtrl.text = init.tag;
      _memoCtrl.text = init.memo;
      _balls = init.balls.map((b) => b.copy()).toList();
      _lines
        ..clear()
        ..addAll(init.lines.map((l) => l.copy()));
    }
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  void _applyMode(GameMode m, {required bool resetPositions}) {
    setState(() {
      _mode = m;
      final defs = BallDefinition.forMode(m);
      if (resetPositions || _balls.isEmpty) {
        _balls = defs.map((d) {
          return BallInstance(def: d, x: 0.5, y: 0.5, onTable: false);
        }).toList();
      } else {
        final byId = {for (final b in _balls) b.def.id: b};
        _balls = defs.map((d) {
          final old = byId[d.id];
          if (old != null) {
            return BallInstance(def: d, x: old.x, y: old.y, onTable: old.onTable);
          }
          return BallInstance(def: d, x: 0.5, y: 0.5, onTable: false);
        }).toList();
      }
      if (resetPositions) _lines.clear();
    });
  }

  double _ballRadiusPx() {
    if (_felt == Rect.zero) return 8;
    return _felt.width * 0.015;
  }

  void _placeBallRandomOnTable(BallInstance b) {
    final r = math.Random();
    b.x = 0.25 + r.nextDouble() * 0.5;
    b.y = 0.25 + r.nextDouble() * 0.5;
    b.onTable = true;
  }

  void _handleBallPointerDown(BallInstance b, Offset local, Offset feltLocal) {
    final now = DateTime.now();
    final prev = _lastTap[b.def.id];
    _lastTap[b.def.id] = now;
    if (prev != null && now.difference(prev).inMilliseconds <= _doubleTapMs) {
      b.onTable = false;
      _lastTap.remove(b.def.id);
      setState(() => _status = 'トレイに戻しました');
      return;
    }
    if (_trajMode) {
      if (b.def.id == 0) {
        setState(() {
          _selCueId = 0;
          _status = '的球をタップ';
        });
      } else if (_selCueId == null && _lines.isNotEmpty) {
        _addTrajectoryLine(0, b.def.id);
        setState(() {
          _status = '連続軌道を追加しました';
        });
      } else if (_selCueId == 0) {
        _addTrajectoryLine(0, b.def.id);
        setState(() {
          _selCueId = null;
          _status = '軌道を追加しました';
        });
      }
      return;
    }
    _dragBallId = b.def.id;
  }

  void _addTrajectoryLine(int cueId, int objId) {
    final cue = _balls.firstWhere((x) => x.def.id == cueId);
    final obj = _balls.firstWhere((x) => x.def.id == objId);
    final felt = _felt;
    if (felt == Rect.zero) return;
    final geom = TrajectoryGeometry.compute(
      felt: felt,
      cueCenterPx: Offset(felt.left + cue.x * felt.width, felt.top + cue.y * felt.height),
      objCenterPx: Offset(felt.left + obj.x * felt.width, felt.top + obj.y * felt.height),
      cueEndOverrideNorm: null,
      cueBounceEndOverrideNorm: null,
      objEndOverrideNorm: null,
        objBounceEndOverrideNorm: null,
    );
    Offset? prevEnd;
    if (_lines.isNotEmpty) {
      final last = _lines.last;
      final gLast = TrajectoryGeometry.compute(
        felt: felt,
        cueCenterPx: Offset(
          felt.left + _balls.firstWhere((e) => e.def.id == last.cueBallId).x * felt.width,
          felt.top + _balls.firstWhere((e) => e.def.id == last.cueBallId).y * felt.height,
        ),
        objCenterPx: Offset(
          felt.left + _balls.firstWhere((e) => e.def.id == last.objBallId).x * felt.width,
          felt.top + _balls.firstWhere((e) => e.def.id == last.objBallId).y * felt.height,
        ),
        contactOverrideNorm: last.contact,
        cueAnchorNorm: last.cueAnchor,
        objAnchorNorm: last.objAnchor,
        cueStartOverrideNorm: last.cueStartOverride,
        cueEndOverrideNorm: last.cueEndOverride,
        cueBounceEndOverrideNorm: last.cueBounceEndOverride,
        objEndOverrideNorm: last.objEndOverride,
        objBounceEndOverrideNorm: last.objBounceEndOverride,
      );
      prevEnd = Offset(
        felt.left + gLast.cueBounceEnd.dx * felt.width,
        felt.top + gLast.cueBounceEnd.dy * felt.height,
      );
    }
    final line = TrajectoryLine(
      cueBallId: cueId,
      objBallId: objId,
      contact: geom.contact,
      cueAnchor: Offset.zero,
      objAnchor: Offset.zero,
      cueStartOverride: prevEnd == null
          ? null
          : Offset(
              (prevEnd.dx - felt.left) / felt.width,
              (prevEnd.dy - felt.top) / felt.height,
            ),
    );
    _lines.add(line);
  }

  void _onTablePanUpdate(Offset local) {
    if (_felt == Rect.zero) return;
    final feltLocal = local;
    final nx = ((feltLocal.dx - _felt.left) / _felt.width).clamp(0.0, 1.0);
    final ny = ((feltLocal.dy - _felt.top) / _felt.height).clamp(0.0, 1.0);

    if (_dragBallId != null) {
      final b = _balls.firstWhere((e) => e.def.id == _dragBallId);
      b.x = nx;
      b.y = ny;
      b.onTable = true;
      setState(() {});
      return;
    }

    if (_dragContactIdx != null) {
      final line = _lines[_dragContactIdx!];
      final obj = _balls.firstWhere((e) => e.def.id == line.objBallId);
      final centerObj = Offset(obj.x, obj.y);
      final surf = Offset(nx, ny) - centerObj;
      final brN = _ballRadiusPx() / math.min(_felt.width, _felt.height);
      final contactRadiusN = (brN * 2).clamp(0.012, 0.24);
      final dir = surf.distance < 1e-9 ? const Offset(0, -1) : surf / surf.distance;
      line.contact = centerObj + dir * contactRadiusN;
      line.cueAnchor = Offset.zero;
      line.objAnchor = Offset.zero;
      line.cueEndOverride = null;
      line.cueBounceEndOverride = null;
      line.objEndOverride = null;
      line.objBounceEndOverride = null;
      setState(() {});
      return;
    }

    if (_dragCueAIdx != null) {
      final line = _lines[_dragCueAIdx!];
      final ox = (nx - line.contact.dx).clamp(-0.5, 0.5);
      final oy = (ny - line.contact.dy).clamp(-0.5, 0.5);
      line.cueAnchor = Offset(ox, oy);
      setState(() {});
      return;
    }

    if (_dragObjAIdx != null) {
      final line = _lines[_dragObjAIdx!];
      final ox = (nx - line.contact.dx).clamp(-0.5, 0.5);
      final oy = (ny - line.contact.dy).clamp(-0.5, 0.5);
      line.objAnchor = Offset(ox, oy);
      setState(() {});
      return;
    }

    if (_dragCueEndIdx != null) {
      final line = _lines[_dragCueEndIdx!];
      line.cueEndOverride = Offset(nx, ny);
      setState(() {});
      return;
    }

    if (_dragCueBounceEndIdx != null) {
      final line = _lines[_dragCueBounceEndIdx!];
      line.cueBounceEndOverride = Offset(nx, ny);
      setState(() {});
      return;
    }

    if (_dragObjEndIdx != null) {
      final line = _lines[_dragObjEndIdx!];
      line.objEndOverride = Offset(nx, ny);
      setState(() {});
      return;
    }

    if (_dragObjBounceEndIdx != null) {
      final line = _lines[_dragObjBounceEndIdx!];
      line.objBounceEndOverride = Offset(nx, ny);
      setState(() {});
      return;
    }
  }

  void _pickTrajControl(Offset local) {
    if (_felt == Rect.zero) return;
    _dragContactIdx = null;
    _dragCueAIdx = null;
    _dragObjAIdx = null;
    _dragCueEndIdx = null;
    _dragCueBounceEndIdx = null;
    _dragObjEndIdx = null;
    _dragObjBounceEndIdx = null;
    final felt = _felt;
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final cue = _balls.firstWhere((e) => e.def.id == line.cueBallId);
      final obj = _balls.firstWhere((e) => e.def.id == line.objBallId);
      final geom = TrajectoryGeometry.compute(
        felt: felt,
        cueCenterPx: Offset(felt.left + cue.x * felt.width, felt.top + cue.y * felt.height),
        objCenterPx: Offset(felt.left + obj.x * felt.width, felt.top + obj.y * felt.height),
        contactOverrideNorm: line.contact,
        cueAnchorNorm: line.cueAnchor,
        objAnchorNorm: line.objAnchor,
        cueStartOverrideNorm: line.cueStartOverride,
        cueEndOverrideNorm: line.cueEndOverride,
        cueBounceEndOverrideNorm: line.cueBounceEndOverride,
        objEndOverrideNorm: line.objEndOverride,
        objBounceEndOverrideNorm: line.objBounceEndOverride,
      );
      final c = Offset(
        felt.left + geom.contact.dx * felt.width,
        felt.top + geom.contact.dy * felt.height,
      );
      final cc = Offset(
        felt.left + geom.cueControl.dx * felt.width,
        felt.top + geom.cueControl.dy * felt.height,
      );
      final oc = Offset(
        felt.left + geom.objControl.dx * felt.width,
        felt.top + geom.objControl.dy * felt.height,
      );
      final ce = Offset(
        felt.left + geom.cueEnd.dx * felt.width,
        felt.top + geom.cueEnd.dy * felt.height,
      );
      final cbe = Offset(
        felt.left + geom.cueBounceEnd.dx * felt.width,
        felt.top + geom.cueBounceEnd.dy * felt.height,
      );
      final oe = Offset(
        felt.left + geom.objEnd.dx * felt.width,
        felt.top + geom.objEnd.dy * felt.height,
      );
      final obe = Offset(
        felt.left + geom.objBounceEnd.dx * felt.width,
        felt.top + geom.objBounceEnd.dy * felt.height,
      );
      if ((local - c).distance < 14) {
        _dragContactIdx = i;
        return;
      }
      if ((local - cc).distance < 16) {
        _dragCueAIdx = i;
        return;
      }
      if ((local - oc).distance < 16) {
        _dragObjAIdx = i;
        return;
      }
      if ((local - ce).distance < 14) {
        _dragCueEndIdx = i;
        return;
      }
      if (geom.cueHitCushion && (local - cbe).distance < 14) {
        _dragCueBounceEndIdx = i;
        return;
      }
      if ((local - oe).distance < 14) {
        _dragObjEndIdx = i;
        return;
      }
      if (geom.objHitCushion && (local - obe).distance < 14) {
        _dragObjBounceEndIdx = i;
        return;
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKey) ?? <String>[];
    final id = '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';
    final created = _formatDateTime(DateTime.now());
    final doc = SavedBallLayout(
      id: id,
      createdAt: created,
      mode: _mode,
      tag: _tagCtrl.text,
      memo: _memoCtrl.text,
      balls: _balls.where((b) => b.onTable).map((b) => b.copy()).toList(),
      lines: _lines.map((l) => l.copy()).toList(),
    );
    list.add(jsonEncode(doc.toJson()));
    await prefs.setStringList(_prefKey, list);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存しました')));
    }
  }

  void _undoLastTrajectory() {
    if (_lines.isEmpty) return;
    setState(() {
      _lines.removeLast();
      _selCueId = null;
      _status = '直前の軌道を1本取り消しました';
    });
  }

  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _openSavedList() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const SavedLayoutsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // SP縦持ちのみ縦レイアウト。横向き時は幅が狭くても横レイアウトを優先する。
    final usePortraitLayout =
        media.orientation == Orientation.portrait && media.size.width < 700;
    return Scaffold(
      appBar: AppBar(
        title: const Text('配置登録エディタ'),
        actions: [
          IconButton(
            onPressed: _openSavedList,
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: '保存済み配置',
          ),
        ],
      ),
      body: SafeArea(
        child: usePortraitLayout
            ? _buildPortraitLayout(context)
            : _buildLandscapeLayout(context),
      ),
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        _buildTopControls(dense: false),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Center(
              child: _buildTableFitted(aspectRatio: 2 / 1),
            ),
          ),
        ),
        _buildBottomControls(context, compactInputs: false),
      ],
    );
  }

  Widget _buildPortraitLayout(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildTopControls(dense: true),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Center(
              child: _buildTableFitted(aspectRatio: 1 / (2 / 1)),
            ),
          ),
        ),
        _buildBottomControls(context, compactInputs: true),
      ],
    );
  }

  Widget _buildTopControls({required bool dense}) {
    final spacing = dense ? 6.0 : 8.0;
    final buttonStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<GameMode>(
            segments: const [
              ButtonSegment(value: GameMode.nine, label: Text('9球')),
              ButtonSegment(value: GameMode.ten, label: Text('10球')),
              ButtonSegment(value: GameMode.fifteen, label: Text('15球')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              _applyMode(s.first, resetPositions: true);
            },
          ),
          SizedBox(height: spacing),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilledButton(
                  style: buttonStyle.merge(
                    FilledButton.styleFrom(
                      backgroundColor:
                          _trajMode ? const Color(0xFF0A84FF) : Colors.white,
                      foregroundColor:
                          _trajMode ? Colors.white : const Color(0xFF0A84FF),
                      side: const BorderSide(color: Color(0xFF0A84FF), width: 1),
                    ),
                  ),
                  onPressed: () => setState(() {
                    _trajMode = !_trajMode;
                    _selCueId = null;
                    _status = _trajMode ? '軌道モード: 手玉→的球の順にタップ' : 'ドラッグで移動';
                  }),
                  child: const Text('軌道描画'),
                ),
                SizedBox(width: spacing),
                OutlinedButton(
                  style: buttonStyle,
                  onPressed: () => setState(_lines.clear),
                  child: const Text('軌道消去'),
                ),
                SizedBox(width: spacing),
                OutlinedButton(
                  style: buttonStyle,
                  onPressed: _lines.isEmpty ? null : _undoLastTrajectory,
                  child: const Text('軌道修正'),
                ),
                SizedBox(width: spacing),
                OutlinedButton(
                  style: buttonStyle,
                  onPressed: () => setState(() => _applyMode(_mode, resetPositions: true)),
                  child: const Text('リセット'),
                ),
                SizedBox(width: spacing),
                FilledButton(
                  style: buttonStyle.merge(
                    FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context, {required bool compactInputs}) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _status,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 78,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: _balls.map((b) => _trayBall(b)).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: compactInputs
              ? Column(
                  children: [
                    TextField(
                      controller: _tagCtrl,
                      decoration: const InputDecoration(
                        labelText: 'タグ入力',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _memoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'メモ入力',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagCtrl,
                        decoration: const InputDecoration(
                          labelText: 'タグ入力',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _memoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'メモ入力',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildTableFitted({required double aspectRatio}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final width = maxWidth;
        final height = width / aspectRatio;

        if (height <= maxHeight) {
          return SizedBox(
            width: width,
            height: height,
            child: _buildTableCanvas(Size(width, height)),
          );
        }

        final fittedHeight = maxHeight;
        final fittedWidth = fittedHeight * aspectRatio;
        return SizedBox(
          width: fittedWidth,
          height: fittedHeight,
          child: _buildTableCanvas(Size(fittedWidth, fittedHeight)),
        );
      },
    );
  }

  Widget _buildTableCanvas(Size sz) {
    _felt = BilliardsTablePainter.feltRectForSize(sz);
    return Stack(
      key: _tableStackKey,
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: BilliardsTablePainter(feltRect: _felt),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: TrajectoryPainter(
              felt: _felt,
              lines: _lines,
              ballMap: {for (final b in _balls) b.def.id: b},
              draggingContactIndex: _dragContactIdx,
              draggingCueAnchorIndex: _dragCueAIdx,
              draggingObjAnchorIndex: _dragObjAIdx,
            ),
          ),
        ),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              if (!_trajMode) return;
              _pickTrajControl(e.localPosition);
            },
            onPointerMove: (e) {
              if (_dragContactIdx != null ||
                  _dragCueAIdx != null ||
                  _dragObjAIdx != null ||
                  _dragCueEndIdx != null ||
                  _dragCueBounceEndIdx != null ||
                  _dragObjEndIdx != null ||
                  _dragObjBounceEndIdx != null) {
                _onTablePanUpdate(e.localPosition);
              }
            },
            onPointerUp: (_) {
              _dragContactIdx = null;
              _dragCueAIdx = null;
              _dragObjAIdx = null;
              _dragCueEndIdx = null;
              _dragCueBounceEndIdx = null;
              _dragObjEndIdx = null;
              _dragObjBounceEndIdx = null;
            },
            onPointerCancel: (_) {
              _dragContactIdx = null;
              _dragCueAIdx = null;
              _dragObjAIdx = null;
              _dragCueEndIdx = null;
              _dragCueBounceEndIdx = null;
              _dragObjEndIdx = null;
              _dragObjBounceEndIdx = null;
            },
          ),
        ),
        ..._balls.where((b) => b.onTable).map((b) => _ballPositioned(b)),
      ],
    );
  }

  Widget _ballPositioned(BallInstance b) {
    final felt = _felt;
    final r = _ballRadiusPx();
    final left = felt.left + b.x * felt.width - r;
    final top = felt.top + b.y * felt.height - r;
    return Positioned(
      left: left,
      top: top,
      width: r * 2,
      height: r * 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => _handleBallPointerDown(b, d.localPosition, d.localPosition),
        onPanUpdate: (d) {
          if (!_trajMode && _dragBallId == b.def.id) {
            final stackBox = _tableStackKey.currentContext?.findRenderObject() as RenderBox?;
            if (stackBox != null) {
              _onTablePanUpdate(stackBox.globalToLocal(d.globalPosition));
            }
          }
        },
        onPanEnd: (_) {
          _dragBallId = null;
        },
        onPanCancel: () {
          _dragBallId = null;
        },
        child: CustomPaint(
          painter: _BallPainter(ball: b, radius: r),
        ),
      ),
    );
  }

  Widget _trayBall(BallInstance b) {
    final r = 28.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Opacity(
        opacity: b.onTable ? 0.45 : 1,
        child: InkWell(
          onTap: () {
            setState(() {
              _placeBallRandomOnTable(b);
              _status = '台上に配置しました';
            });
          },
          child: SizedBox(
            width: r * 2,
            height: r * 2,
            child: CustomPaint(painter: _BallPainter(ball: b, radius: r)),
          ),
        ),
      ),
    );
  }
}

class _BallPainter extends CustomPainter {
  _BallPainter({required this.ball, required this.radius});

  final BallInstance ball;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final fill = ball.def.fill;
    canvas.drawCircle(c, radius, Paint()..color = fill);
    if (ball.def.stripe) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: radius * 0.92)));
      final band = RRect.fromRectAndCorners(
        Rect.fromCenter(center: c, width: radius * 2.2, height: radius * 0.55),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      );
      canvas.drawRRect(band, Paint()..color = Colors.white);
      canvas.drawRRect(
        band,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = fill
          ..strokeWidth = radius * 0.12,
      );
      canvas.restore();
    }
    canvas.drawCircle(
      c.translate(-radius * 0.35, -radius * 0.35),
      radius * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    final labelRadius = radius * 0.46;
    if (ball.def.id != 0) {
      canvas.drawCircle(c, labelRadius, Paint()..color = Colors.white);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: ball.def.label,
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.78,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _BallPainter oldDelegate) =>
      oldDelegate.ball != ball || oldDelegate.radius != radius;
}

class SavedLayoutsScreen extends StatefulWidget {
  const SavedLayoutsScreen({super.key});

  @override
  State<SavedLayoutsScreen> createState() => _SavedLayoutsScreenState();
}

class _SavedLayoutsScreenState extends State<SavedLayoutsScreen> {
  static const _prefKey = 'saved_ball_layouts';
  List<SavedBallLayout> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefKey);
    final out = <SavedBallLayout>[];
    if (raw != null) {
      for (final s in raw) {
        final doc = SavedBallLayout.fromJsonString(s);
        if (doc != null) out.add(doc);
      }
    }
    setState(() {
      _items = out.reversed.toList();
      _loading = false;
    });
  }

  Future<void> _delete(SavedBallLayout doc) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefKey) ?? [];
    final next = raw.where((s) => SavedBallLayout.fromJsonString(s)?.id != doc.id).toList();
    await prefs.setStringList(_prefKey, next);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('保存した配置')),
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final doc = _items[i];
          return ListTile(
            title: Text(doc.tag.isEmpty ? '(無題)' : doc.tag),
            subtitle: Text('${doc.mode.storageKey}球 · ${doc.createdAt}\n${doc.memo}'),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(doc),
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BallLayoutEditorScreen(initialLayout: doc),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
