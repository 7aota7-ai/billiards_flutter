// Ball layout editor — single-file implementation (see billiards_app_spec.md §3).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/detected_ball_layout.dart';
import '../models/table_guide_geometry.dart';
import '../services/ball_detection_service.dart';
import '../services/felt_homography.dart';
import '../services/pending_photo_import_store.dart';
import '../theme/apple_theme.dart';

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
    final cue = const BallDefinition(
        id: 0, label: '●', fill: Color(0xFFFFFFFF), stripe: false);
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
    final def = defs
        .cast<BallDefinition?>()
        .firstWhere((d) => d!.id == id, orElse: () => null);
    if (def == null) return null;
    return BallInstance(
      def: def,
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      onTable: true,
    );
  }
}

// --- Table ball scale ---

class BallTableScale {
  BallTableScale._();

  /// Regulation pool ball radius / felt long-side width (≈2.25" Ø on ~100" table).
  static const double regulationRadiusNorm = 0.01125;

  /// Desktop: ~3.2× real (1.8× previous). Phone: touch targets.
  static const double _desktopVisualScale = 1.8 * 1.8;

  static double radiusNorm({required bool phone}) =>
      regulationRadiusNorm *
      (phone ? 0.03 / regulationRadiusNorm : _desktopVisualScale);

  static double radiusPx(Rect felt, {required bool phone}) {
    final r = felt.width * radiusNorm(phone: phone);
    final floor = phone ? 10.5 : 6.0 * 1.8;
    return math.max(r, floor);
  }
}

// --- Trajectory ---

class TrajectoryLine {
  static const int maxCueCushions = 4;

  TrajectoryLine({
    required this.cueBallId,
    required this.objBallId,
    required this.contact,
    this.cueAnchor = Offset.zero,
    this.objAnchor = Offset.zero,
    this.cueStartOverride,
    this.cueEndOverride,
    this.cueBounceEndOverride,
    this.cueBounce2EndOverride,
    this.cueBounce3EndOverride,
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
  Offset? cueBounce2EndOverride;
  Offset? cueBounce3EndOverride;
  Offset? objEndOverride;
  Offset? objBounceEndOverride;

  List<Offset?> get cueBounceOverridesOrdered => [
        cueBounceEndOverride,
        cueBounce2EndOverride,
        cueBounce3EndOverride,
      ];

  void clearCueBounceOverrides() {
    cueBounceEndOverride = null;
    cueBounce2EndOverride = null;
    cueBounce3EndOverride = null;
  }

  void clearCueBounceOverridesFrom(int bounceIndex) {
    if (bounceIndex <= 0) {
      clearCueBounceOverrides();
    } else if (bounceIndex == 1) {
      cueBounce2EndOverride = null;
      cueBounce3EndOverride = null;
    } else if (bounceIndex == 2) {
      cueBounce3EndOverride = null;
    }
  }

  TrajectoryLine copy() => TrajectoryLine(
        cueBallId: cueBallId,
        objBallId: objBallId,
        contact: contact,
        cueAnchor: cueAnchor,
        objAnchor: objAnchor,
        cueStartOverride: cueStartOverride,
        cueEndOverride: cueEndOverride,
        cueBounceEndOverride: cueBounceEndOverride,
        cueBounce2EndOverride: cueBounce2EndOverride,
        cueBounce3EndOverride: cueBounce3EndOverride,
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
          'cueStartOverride': {
            'x': cueStartOverride!.dx,
            'y': cueStartOverride!.dy
          },
        if (cueEndOverride != null)
          'cueEndOverride': {'x': cueEndOverride!.dx, 'y': cueEndOverride!.dy},
        if (cueBounceEndOverride != null)
          'cueBounceEndOverride': {
            'x': cueBounceEndOverride!.dx,
            'y': cueBounceEndOverride!.dy,
          },
        if (cueBounce2EndOverride != null)
          'cueBounce2EndOverride': {
            'x': cueBounce2EndOverride!.dx,
            'y': cueBounce2EndOverride!.dy,
          },
        if (cueBounce3EndOverride != null)
          'cueBounce3EndOverride': {
            'x': cueBounce3EndOverride!.dx,
            'y': cueBounce3EndOverride!.dy,
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
        cueEnd =
            Offset((ce['x'] as num).toDouble(), (ce['y'] as num).toDouble());
      }
      Offset? objEnd;
      final oe = j['objEndOverride'];
      if (oe is Map<String, dynamic>) {
        objEnd =
            Offset((oe['x'] as num).toDouble(), (oe['y'] as num).toDouble());
      }
      Offset? objBounceEnd;
      final obe = j['objBounceEndOverride'];
      if (obe is Map<String, dynamic>) {
        objBounceEnd =
            Offset((obe['x'] as num).toDouble(), (obe['y'] as num).toDouble());
      }
      Offset? cueBounceEnd;
      final cbe = j['cueBounceEndOverride'];
      if (cbe is Map<String, dynamic>) {
        cueBounceEnd =
            Offset((cbe['x'] as num).toDouble(), (cbe['y'] as num).toDouble());
      }
      Offset? cueBounce2;
      final cbe2 = j['cueBounce2EndOverride'];
      if (cbe2 is Map<String, dynamic>) {
        cueBounce2 = Offset(
            (cbe2['x'] as num).toDouble(), (cbe2['y'] as num).toDouble());
      }
      Offset? cueBounce3;
      final cbe3 = j['cueBounce3EndOverride'];
      if (cbe3 is Map<String, dynamic>) {
        cueBounce3 = Offset(
            (cbe3['x'] as num).toDouble(), (cbe3['y'] as num).toDouble());
      }
      return TrajectoryLine(
        cueBallId: j['cueBallId'] as int,
        objBallId: j['objBallId'] as int,
        contact: Offset((c['x'] as num).toDouble(), (c['y'] as num).toDouble()),
        cueAnchor:
            Offset((ca['ox'] as num).toDouble(), (ca['oy'] as num).toDouble()),
        objAnchor:
            Offset((oa['ox'] as num).toDouble(), (oa['oy'] as num).toDouble()),
        cueStartOverride: ov,
        cueEndOverride: cueEnd,
        cueBounceEndOverride: cueBounceEnd,
        cueBounce2EndOverride: cueBounce2,
        cueBounce3EndOverride: cueBounce3,
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
    required this.cueCushionChain,
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
  final List<Offset> cueCushionChain;
  final Offset cueBounceEnd;
  final bool cueHitCushion;
  final Offset objEnd;
  final Offset objBounceEnd;
  final bool objHitCushion;
  final Offset cueControl;
  final Offset objControl;
  final bool skipObjPost;

  static Offset _norm(Offset o, Rect felt) =>
      Offset((o.dx - felt.left) / felt.width, (o.dy - felt.top) / felt.height);

  static Offset _toPx(Offset norm, Rect felt) => Offset(
      felt.left + norm.dx * felt.width, felt.top + norm.dy * felt.height);

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
    required double ballRadiusPx,
    required Offset cueCenterPx,
    required Offset objCenterPx,
    Offset? contactOverrideNorm,
    Offset cueAnchorNorm = Offset.zero,
    Offset objAnchorNorm = Offset.zero,
    Offset? cueStartOverrideNorm,
    Offset? cueEndOverrideNorm,
    Offset? cueBounceEndOverrideNorm,
    Offset? cueBounce2EndOverrideNorm,
    Offset? cueBounce3EndOverrideNorm,
    Offset? objEndOverrideNorm,
    Offset? objBounceEndOverrideNorm,
  }) {
    final feltNorm = _normRect(felt);
    final br = ballRadiusPx;
    final cueN = _norm(cueCenterPx, felt);
    final objN = _norm(objCenterPx, felt);
    final cueStartPx = cueStartOverrideNorm == null
        ? cueCenterPx
        : _toPx(cueStartOverrideNorm, felt);

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
    final toPocketUnit =
        toPocketLen < 1e-9 ? const Offset(0, -1) : toPocketPx / toPocketLen;
    final contactCorrect = objCenterPx - toPocketUnit * (br * 2);
    final contactRawPx = contactOverrideNorm == null
        ? contactCorrect
        : _toPx(contactOverrideNorm, felt);
    final fromObjToContact = contactRawPx - objCenterPx;
    final fromObjLen = fromObjToContact.distance;
    final fromObjUnit =
        fromObjLen < 1e-9 ? -toPocketUnit : fromObjToContact / fromObjLen;
    // 接触点（赤丸）は常に「的球中心から2R」の接触リング上に置く（めり込み防止）。
    final contactUsePx = objCenterPx + fromObjUnit * (br * 2);

    final objDirPx = objCenterPx - contactUsePx;
    final objDirLen = objDirPx.distance;
    final objDirUnit =
        objDirLen < 1e-9 ? const Offset(0, 1) : objDirPx / objDirLen;

    // 物理則: 同質量球の衝突後、手球速度は「法線方向成分を失い、接線方向のみ残る」。
    // これにより手球進行方向と的球進行方向が常に90度になる。
    final incomingPx = contactUsePx - cueStartPx;
    final tangentPx = incomingPx - objDirUnit * incomingPx.dot(objDirUnit);
    final tangentLen = tangentPx.distance;
    final cueDirUnit = tangentLen < 1e-9
        ? Offset(-objDirUnit.dy, objDirUnit.dx)
        : tangentPx / tangentLen;

    final cueToEdgeLen = _rayToFeltEdgePx(contactUsePx, cueDirUnit, felt);
    final cueStraightEndPx = contactUsePx + cueDirUnit * cueToEdgeLen;
    final objLen = _rayToFeltEdgePx(contactUsePx, objDirUnit, felt);
    final objAutoEndPx = contactUsePx + objDirUnit * objLen;

    Offset cueEndPx;
    if (cueEndOverrideNorm != null) {
      cueEndPx = _toPx(cueEndOverrideNorm, felt);
    } else {
      cueEndPx = _autoCueFirstEndPx(
        contactPx: contactUsePx,
        cueDirUnit: cueDirUnit,
        cueAnchorNorm: cueAnchorNorm,
        straightEndPx: cueStraightEndPx,
        felt: felt,
      );
    }

    final midCuePx = (contactUsePx + cueEndPx) / 2;
    var cueControlPx = midCuePx +
        Offset(cueAnchorNorm.dx * felt.width, cueAnchorNorm.dy * felt.height);

    if (cueEndOverrideNorm == null && cueAnchorNorm != Offset.zero) {
      cueEndPx = _autoCueFirstEndPx(
        contactPx: contactUsePx,
        cueDirUnit: cueDirUnit,
        cueAnchorNorm: cueAnchorNorm,
        straightEndPx: cueStraightEndPx,
        felt: felt,
        controlPx: cueControlPx,
      );
      cueControlPx = (contactUsePx + cueEndPx) / 2 +
          Offset(cueAnchorNorm.dx * felt.width, cueAnchorNorm.dy * felt.height);
    }

    final objEndBasePx = objEndOverrideNorm == null
        ? objAutoEndPx
        : _toPx(objEndOverrideNorm, felt);
    // 的球がポケットに入る場合のみポケット以降を省略（クッション反射は描画する）。
    final pocketHitPx =
        _firstPocketHitOnSegment(contactUsePx, objEndBasePx, felt);
    final skipObjPost = pocketHitPx != null;
    final objEndPx = pocketHitPx ?? objEndBasePx;

    final midObjPx = (contactUsePx + objEndPx) / 2;
    final objControlPx = midObjPx +
        Offset(objAnchorNorm.dx * felt.width, objAnchorNorm.dy * felt.height);

    final cueCushionChainNorm = _computeCueCushionChainNorm(
      felt: felt,
      contactPx: contactUsePx,
      controlPx: cueControlPx,
      cueDirUnit: cueDirUnit,
      firstEndPx: cueEndPx,
      bounceOverridesNorm: [
        cueBounceEndOverrideNorm,
        cueBounce2EndOverrideNorm,
        cueBounce3EndOverrideNorm,
      ],
    );
    final cueBounceEndPx = cueCushionChainNorm.isEmpty
        ? cueEndPx
        : _toPx(cueCushionChainNorm.last, felt);

    final objEdgeAtEnd = skipObjPost ? null : _edgeAtPointPx(objEndPx, felt);
    final objHitCushion = !skipObjPost && objEdgeAtEnd != null;
    final objIncoming = _quadBezierTangentAtEnd(
      contactUsePx,
      objControlPx,
      objEndPx,
      fallback: objDirUnit,
    );
    final objBounceDir = objEdgeAtEnd == null
        ? Offset.zero
        : _reflect(objIncoming, objEdgeAtEnd);
    final objBounceLen =
        objHitCushion ? _rayToFeltEdgePx(objEndPx, objBounceDir, felt) : 0.0;
    final objBounceAutoEndPx =
        objHitCushion ? objEndPx + objBounceDir * objBounceLen : objEndPx;
    final objBounceEndPx = objBounceEndOverrideNorm == null
        ? objBounceAutoEndPx
        : _toPx(objBounceEndOverrideNorm, felt);

    return TrajectoryGeometry(
      feltNorm: feltNorm,
      ballRadiusNorm: br / felt.width,
      cueCenter: cueN,
      objCenter: objN,
      contact: _norm(contactUsePx, felt),
      cueDir: cueDirUnit,
      objDir: objDirUnit,
      cueEnd: _norm(cueEndPx, felt),
      cueCushionChain: cueCushionChainNorm,
      cueBounceEnd: _norm(cueBounceEndPx, felt),
      cueHitCushion: cueCushionChainNorm.length >= 2,
      objEnd: _norm(objEndPx, felt),
      objBounceEnd: _norm(objBounceEndPx, felt),
      objHitCushion: objHitCushion,
      cueControl: _norm(cueControlPx, felt),
      objControl: _norm(objControlPx, felt),
      skipObjPost: skipObjPost,
    );
  }

  static Offset _autoCueFirstEndPx({
    required Offset contactPx,
    required Offset cueDirUnit,
    required Offset cueAnchorNorm,
    required Offset straightEndPx,
    required Rect felt,
    Offset? controlPx,
  }) {
    if (cueAnchorNorm == Offset.zero) return straightEndPx;
    final ctrl = controlPx ??
        (contactPx + straightEndPx) / 2 +
            Offset(cueAnchorNorm.dx * felt.width,
                cueAnchorNorm.dy * felt.height);
    final aim = ctrl - contactPx;
    final aimLen = aim.distance;
    final aimUnit = aimLen < 1e-9 ? cueDirUnit : aim / aimLen;
    return contactPx + aimUnit * _rayToFeltEdgePx(contactPx, aimUnit, felt);
  }

  static const double _bouncePreviewFraction = 0.38;

  static List<Offset> _computeCueCushionChainNorm({
    required Rect felt,
    required Offset contactPx,
    required Offset controlPx,
    required Offset cueDirUnit,
    required Offset firstEndPx,
    required List<Offset?> bounceOverridesNorm,
  }) {
    final chainPx = <Offset>[firstEndPx];
    if (_edgeAtPointPx(firstEndPx, felt) == null) {
      return chainPx.map((p) => _norm(p, felt)).toList(growable: false);
    }

    var incoming = _quadBezierTangentAtEnd(
      contactPx,
      controlPx,
      firstEndPx,
      fallback: cueDirUnit,
    );
    var prev = firstEndPx;

    for (var bi = 0; bi < TrajectoryLine.maxCueCushions - 1; bi++) {
      final edge = _edgeAtPointPx(prev, felt);
      if (edge == null) break;
      final bounceDir = _reflect(incoming, edge);
      final fullLen = _rayToFeltEdgePx(prev, bounceDir, felt);
      if (fullLen < 1e-6) break;

      final override =
          bi < bounceOverridesNorm.length ? bounceOverridesNorm[bi] : null;

      if (override == null) {
        // デフォルトは次クッション手前の短いプレビュー1本だけ（4クッション全部は出さない）
        final previewLen = math
            .max(
              fullLen * _bouncePreviewFraction,
              math.min(felt.width, felt.height) * 0.055,
            )
            .clamp(0.0, fullLen);
        chainPx.add(prev + bounceDir * previewLen);
        break;
      }

      final endPx = _toPx(override, felt);
      chainPx.add(endPx);
      if (_edgeAtPointPx(endPx, felt) == null) break;
      prev = endPx;
      incoming = bounceDir;
    }

    return chainPx.map((p) => _norm(p, felt)).toList(growable: false);
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
    return local
        .map((c) => Offset(felt.left + c.dx, felt.top + c.dy))
        .toList(growable: false);
  }

  static _Edge? _edgeAtPointPx(Offset pointPx, Rect felt) {
    final threshold = math.max(2.0, felt.width * 0.004);
    if ((pointPx.dx - felt.left).abs() <= threshold) return _Edge.left;
    if ((pointPx.dx - felt.right).abs() <= threshold) return _Edge.right;
    if ((pointPx.dy - felt.top).abs() <= threshold) return _Edge.top;
    if ((pointPx.dy - felt.bottom).abs() <= threshold) return _Edge.bottom;
    return null;
  }

  /// クッション付近なら辺上へスナップ（編集時の反射判定用）。
  static Offset snapToCushionEdgePx(Offset p, Rect felt) {
    final snapDist = math.max(16.0, felt.width * 0.03);
    final dLeft = (p.dx - felt.left).abs();
    final dRight = (p.dx - felt.right).abs();
    final dTop = (p.dy - felt.top).abs();
    final dBottom = (p.dy - felt.bottom).abs();
    final minD = math.min(math.min(dLeft, dRight), math.min(dTop, dBottom));
    if (minD > snapDist) return p;
    if (minD == dLeft) {
      return Offset(felt.left, p.dy.clamp(felt.top, felt.bottom));
    }
    if (minD == dRight) {
      return Offset(felt.right, p.dy.clamp(felt.top, felt.bottom));
    }
    if (minD == dTop) {
      return Offset(p.dx.clamp(felt.left, felt.right), felt.top);
    }
    return Offset(p.dx.clamp(felt.left, felt.right), felt.bottom);
  }

  static Offset _quadBezierTangentAtEnd(
    Offset start,
    Offset control,
    Offset end, {
    required Offset fallback,
  }) {
    final t = end - control;
    final len = t.distance;
    if (len < 1e-9) {
      final fb = end - start;
      final fl = fb.distance;
      return fl < 1e-9 ? fallback : fb / fl;
    }
    return t / len;
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
    final widthIsLong = w >= h;
    final sideMidA = widthIsLong ? Offset(w / 2, 0) : Offset(0, h / 2);
    final sideMidB = widthIsLong ? Offset(w / 2, h) : Offset(w, h / 2);
    return [
      Offset(0, 0),
      sideMidA,
      Offset(w, 0),
      Offset(0, h),
      sideMidB,
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
    final outer = Rect.fromCenter(
        center: felt.center,
        width: felt.width + frameW * 4,
        height: felt.height + frameW * 4);
    final cushionRect = Rect.fromCenter(
        center: felt.center,
        width: felt.width + frameW * 2,
        height: felt.height + frameW * 2);

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
        text: TextSpan(
            text: label,
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
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
    final widthIsLong = felt.width >= felt.height;
    if (widthIsLong) {
      final cy = felt.center.dy;
      for (final q in [0.25, 0.5, 0.75]) {
        final ox = felt.left + felt.width * q;
        canvas.drawCircle(Offset(ox, cy), 2.5, paint);
      }
    } else {
      final cx = felt.center.dx;
      for (final q in [0.25, 0.5, 0.75]) {
        final oy = felt.top + felt.height * q;
        canvas.drawCircle(Offset(cx, oy), 2.5, paint);
      }
    }
  }

  void _drawPockets(
      Canvas canvas, Rect felt, Rect cushionRect, double chamfer) {
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
    required this.ballRadiusPx,
    required this.lines,
    required this.ballMap,
    this.editMode = false,
    this.draggingContactIndex,
    this.draggingCueAnchorIndex,
    this.draggingObjAnchorIndex,
    this.draggingCueCushionLineIndex,
    this.draggingCueCushionSegIndex,
    this.draggingObjEndIndex,
    this.draggingObjBounceEndIndex,
  });

  final Rect felt;
  final double ballRadiusPx;
  final List<TrajectoryLine> lines;
  final Map<int, BallInstance> ballMap;
  final bool editMode;
  final int? draggingContactIndex;
  final int? draggingCueAnchorIndex;
  final int? draggingObjAnchorIndex;
  final int? draggingCueCushionLineIndex;
  final int? draggingCueCushionSegIndex;
  final int? draggingObjEndIndex;
  final int? draggingObjBounceEndIndex;

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

      final prevCueEnd =
          i > 0 ? _endOfCueShot(lines[i - 1], ballMap, felt) : null;
      final geom = TrajectoryGeometry.compute(
        felt: felt,
        ballRadiusPx: ballRadiusPx,
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
        cueBounce2EndOverrideNorm: line.cueBounce2EndOverride,
        cueBounce3EndOverrideNorm: line.cueBounce3EndOverride,
        objEndOverrideNorm: line.objEndOverride,
        objBounceEndOverrideNorm: line.objBounceEndOverride,
      );

      final cStart = Offset(
        felt.left +
            (line.cueStartOverride?.dx ?? geom.cueCenter.dx) * felt.width,
        felt.top +
            (line.cueStartOverride?.dy ?? geom.cueCenter.dy) * felt.height,
      );
      final contact = Offset(
        felt.left + geom.contact.dx * felt.width,
        felt.top + geom.contact.dy * felt.height,
      );
      final cueEnd = Offset(
        felt.left + geom.cueEnd.dx * felt.width,
        felt.top + geom.cueEnd.dy * felt.height,
      );
      final cueChainPx = geom.cueCushionChain
          .map(
            (n) => Offset(
              felt.left + n.dx * felt.width,
              felt.top + n.dy * felt.height,
            ),
          )
          .toList(growable: false);
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

      final startPx = prevCueEnd != null && line.cueStartOverride == null
          ? prevCueEnd
          : cStart;

      _dashedLine(canvas, startPx, contact,
          const Color.fromRGBO(255, 255, 255, 0.75), 6, 4);
      _quadArrow(
        canvas,
        contact,
        cueCtrl,
        cueEnd,
        const Color.fromRGBO(255, 255, 255, 0.95),
        draggingCueAnchorIndex == i,
      );
      for (var ci = 1; ci < cueChainPx.length; ci++) {
        _dashedLine(
          canvas,
          cueChainPx[ci - 1],
          cueChainPx[ci],
          const Color.fromRGBO(255, 255, 255, 0.9),
          6,
          4,
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

      final handleScale = editMode ? 1.35 : 1.0;
      double r(double base, {required bool dragging}) =>
          (dragging ? base * 1.25 : base) * handleScale;

      final cpPaint = Paint()..color = const Color.fromRGBO(255, 70, 70, 0.95);
      canvas.drawCircle(
        contact,
        r(7, dragging: draggingContactIndex == i),
        cpPaint,
      );

      final cueAn = Paint()..color = const Color.fromRGBO(140, 255, 90, 0.95);
      canvas.drawCircle(
        cueCtrl,
        r(8, dragging: draggingCueAnchorIndex == i),
        cueAn,
      );
      for (var ci = 0; ci < cueChainPx.length; ci++) {
        final pt = cueChainPx[ci];
        final dragging = draggingCueCushionLineIndex == i &&
            draggingCueCushionSegIndex == ci;
        canvas.drawCircle(
          pt,
          r(6, dragging: dragging),
          Paint()..color = const Color.fromRGBO(210, 240, 255, 0.95),
        );
      }

      final objAn = Paint()..color = const Color.fromRGBO(255, 215, 0, 0.98);
      canvas.drawCircle(
        objCtrl,
        r(8, dragging: draggingObjAnchorIndex == i),
        objAn,
      );
      canvas.drawCircle(
        objEnd,
        r(6, dragging: draggingObjEndIndex == i),
        Paint()..color = const Color.fromRGBO(255, 235, 170, 0.95),
      );
      if (geom.objHitCushion) {
        canvas.drawCircle(
          objBounceEnd,
          r(6, dragging: draggingObjBounceEndIndex == i),
          Paint()..color = const Color.fromRGBO(255, 220, 120, 0.95),
        );
      }
    }
    canvas.restore();
  }

  Offset? _endOfCueShot(
      TrajectoryLine line, Map<int, BallInstance> balls, Rect felt) {
    final cue = balls[line.cueBallId];
    final obj = balls[line.objBallId];
    if (cue == null || obj == null) return null;
    final geom = TrajectoryGeometry.compute(
      felt: felt,
      ballRadiusPx: ballRadiusPx,
      cueCenterPx: Offset(
          felt.left + cue.x * felt.width, felt.top + cue.y * felt.height),
      objCenterPx: Offset(
          felt.left + obj.x * felt.width, felt.top + obj.y * felt.height),
      contactOverrideNorm: line.contact,
      cueAnchorNorm: line.cueAnchor,
      objAnchorNorm: line.objAnchor,
      cueStartOverrideNorm: line.cueStartOverride,
      cueEndOverrideNorm: line.cueEndOverride,
      cueBounceEndOverrideNorm: line.cueBounceEndOverride,
      cueBounce2EndOverrideNorm: line.cueBounce2EndOverride,
      cueBounce3EndOverrideNorm: line.cueBounce3EndOverride,
      objEndOverrideNorm: line.objEndOverride,
      objBounceEndOverrideNorm: line.objBounceEndOverride,
    );
    return Offset(
      felt.left + geom.cueBounceEnd.dx * felt.width,
      felt.top + geom.cueBounceEnd.dy * felt.height,
    );
  }

  void _dashedLine(
      Canvas c, Offset a, Offset b, Color col, double dash, double gap) {
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

  void _quadArrow(
      Canvas c, Offset a, Offset ctrl, Offset end, Color col, bool emphasize) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
    final paint = Paint()
      ..color = col
      ..strokeWidth = emphasize ? 3 : 2
      ..style = PaintingStyle.stroke;
    _dashPath(c, path, paint, 5, 4);
    final tan = end - ctrl;
    final ang = math.atan2(tan.dy, tan.dx);
    final arrowLen = 12.0;
    final p1 = end -
        Offset(
            math.cos(ang - 0.45) * arrowLen, math.sin(ang - 0.45) * arrowLen);
    final p2 = end -
        Offset(
            math.cos(ang + 0.45) * arrowLen, math.sin(ang + 0.45) * arrowLen);
    c.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      Paint()..color = col,
    );
  }

  void _dashPath(
      Canvas canvas, Path path, Paint paint, double dash, double gap) {
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
  bool _trajEditMode = false;
  int? _selCueId;
  String _status = 'ドラッグで移動 / 380ms以内に2回タップでトレイへ';

  int? _dragBallId;
  int? _dragContactIdx;
  int? _dragCueAIdx;
  int? _dragObjAIdx;
  int? _dragCueCushionLineIdx;
  int? _dragCueCushionSegIdx;
  int? _dragObjEndIdx;
  int? _dragObjBounceEndIdx;

  final Map<int, DateTime> _lastTap = {};
  int? _spAxisBallId;
  bool _dragAxisX = false;
  bool _dragAxisY = false;
  bool _spBallSetReady = false;

  final TransformationController _phoneZoomCtrl = TransformationController();
  String? _phoneZoomFitKey;
  bool _phoneZoomDidInitialFit = false;

  /// 写真読込から引き継いだ参照写真（配置比較用）。
  Uint8List? _refImageBytes;
  Size? _refImageSize;
  List<List<double>>? _refCornersNorm;
  bool _showRefPhoto = true;
  double _refPhotoFlex = 0.42;

  final GlobalKey _tableStackKey = GlobalKey();
  Rect _felt = Rect.zero;

  bool get _isPhone => MediaQuery.of(context).size.shortestSide < 700;

  void _clearPhoneAxisGuides() {
    _spAxisBallId = null;
    _dragAxisX = false;
    _dragAxisY = false;
  }

  void _setPhoneAxisStatus() {
    if (_spAxisBallId != null) {
      _status = 'ドラッグで移動 / 縦横線で微調整 / 2回タップでトレイへ';
    }
  }

  static const _trajDrawStatus = '軌道モード: 手玉（●）→的球の順にタップ';

  void _resetTrajDrawState({bool keepTrajMode = true}) {
    _selCueId = 0;
    _trajEditMode = false;
    if (keepTrajMode) _trajMode = true;
    _status = _trajDrawStatus;
  }

  void _clearAllTrajectories() {
    setState(() {
      _lines.clear();
      _resetTrajDrawState();
    });
  }

  String get _trajEditStatus => _isPhone
      ? '軌道点編集: ピンチで拡大 → 点をドラッグ（赤=接触 / 緑=手球 / 黄=的球）'
      : '軌道点編集: 赤=接触点 / 緑=手球曲率 / 黄=的球曲率 / 白・黄丸=終点をドラッグ';

  bool _isNearBallCenter(Offset p, BallInstance b, double thresholdPx) {
    final c = Offset(
      _felt.left + b.x * _felt.width,
      _felt.top + b.y * _felt.height,
    );
    return (p - c).distance <= thresholdPx;
  }

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
    final pending = PendingPhotoImportStore.take();
    if (pending != null) {
      _refImageBytes = pending.imageBytes;
      _refImageSize = pending.imageSize;
      _refCornersNorm = pending.cornersNormalized;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyDetectedLayout(pending.layout);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isPhone && !_spBallSetReady) {
      _spBallSetReady = true;
      _upgradeToFifteenBallSet();
    }
  }

  /// SP: トレイは常に15球。既存配置は id で引き継ぐ。
  void _upgradeToFifteenBallSet() {
    final byId = {for (final b in _balls) b.def.id: b};
    final defs = BallDefinition.forMode(GameMode.fifteen);
    setState(() {
      _mode = GameMode.fifteen;
      _balls = defs.map((d) {
        final old = byId[d.id];
        if (old != null) {
          return BallInstance(
              def: d, x: old.x, y: old.y, onTable: old.onTable);
        }
        return BallInstance(def: d, x: 0.5, y: 0.5, onTable: false);
      }).toList();
    });
  }

  @override
  void dispose() {
    _phoneZoomCtrl.dispose();
    _tagCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  /// SP: 台は常に画面幅いっぱい。初回のみ全体表示倍率を適用（以降はユーザーのズームを維持）。
  void _applyPhoneZoomFit(double maxW, double maxH, double aspectRatio) {
    final tableH = maxW / aspectRatio;
    final fitScale = math.min(1.0, maxH / tableH);
    final key =
        '${maxW.toStringAsFixed(1)}x${maxH.toStringAsFixed(1)}@$aspectRatio';
    if (_phoneZoomFitKey == key && _phoneZoomDidInitialFit) return;
    _phoneZoomFitKey = key;
    if (_phoneZoomDidInitialFit) return;
    _phoneZoomDidInitialFit = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _phoneZoomCtrl.value = Matrix4.diagonal3Values(fitScale, fitScale, 1.0);
    });
  }

  double _currentZoomScale() {
    final m = _phoneZoomCtrl.value.storage;
    // Uniform scaling only; use X axis as representative.
    return m[0].abs();
  }

  void _snapZoomBackToFit(double fitScale) {
    final current = _currentZoomScale();
    if (current <= fitScale * 1.03) {
      _phoneZoomCtrl.value = Matrix4.diagonal3Values(fitScale, fitScale, 1.0);
    }
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
            return BallInstance(
                def: d, x: old.x, y: old.y, onTable: old.onTable);
          }
          return BallInstance(def: d, x: 0.5, y: 0.5, onTable: false);
        }).toList();
      }
      if (resetPositions) _lines.clear();
    });
  }

  /// 写真検出結果を台面上に仮配置（id は色ヒントから推定、要ユーザー確認）。
  void _applyDetectedLayout(DetectedBallLayout layout) {
    final usedIds = <int>{};
    final assignments = List<int?>.filled(layout.balls.length, null);

    for (var i = 0; i < layout.balls.length; i++) {
      final detected = layout.balls[i];
      var id = detected.id ?? suggestBallId(detected.color, allowCue: true);
      if (id != null && usedIds.contains(id)) id = null;
      if (id != null) {
        usedIds.add(id);
        assignments[i] = id;
      }
    }

    var nextId = 1;
    for (var i = 0; i < layout.balls.length; i++) {
      if (assignments[i] != null) continue;
      while (nextId <= _mode.totalBalls && usedIds.contains(nextId)) {
        nextId++;
      }
      if (nextId > _mode.totalBalls) break;
      assignments[i] = nextId;
      usedIds.add(nextId);
      nextId++;
    }

    var placed = 0;
    setState(() {
      for (final b in _balls) {
        b.onTable = false;
      }
      for (var i = 0; i < layout.balls.length; i++) {
        final id = assignments[i];
        if (id == null) continue;
        final detected = layout.balls[i];
        final ball = _balls.where((b) => b.def.id == id).firstOrNull;
        if (ball == null) continue;
        ball
          ..x = detected.x.clamp(0.0, 1.0)
          ..y = detected.y.clamp(0.0, 1.0)
          ..onTable = true;
        placed++;
      }
      _lines.clear();
      _trajMode = false;
      _trajEditMode = false;
      _clearPhoneAxisGuides();
      _status = _hasRefPhoto
          ? '写真から $placed 球を配置 — 上の参照写真と比較しながら修正'
          : '写真から $placed 球を配置（色ヒントで仮割当・要確認）';
    });
  }

  double _ballRadiusPx() {
    if (_felt == Rect.zero) return 8;
    return BallTableScale.radiusPx(_felt, phone: _isPhone);
  }

  Offset _snapTrajNormToCushion(Offset norm) {
    final felt = _felt;
    final px = Offset(
      felt.left + norm.dx * felt.width,
      felt.top + norm.dy * felt.height,
    );
    final snapped = TrajectoryGeometry.snapToCushionEdgePx(px, felt);
    return Offset(
      ((snapped.dx - felt.left) / felt.width).clamp(0.0, 1.0),
      ((snapped.dy - felt.top) / felt.height).clamp(0.0, 1.0),
    );
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
      if (_spAxisBallId == b.def.id) {
        _clearPhoneAxisGuides();
      }
      setState(() => _status = 'トレイに戻しました');
      return;
    }
    if (_trajMode) {
      if (_trajEditMode) {
        setState(() => _status = _trajEditStatus);
        return;
      }
      if (b.def.id == 0) {
        setState(() {
          _selCueId = 0;
          _status = '的球をタップして軌道を追加';
        });
      } else if (_selCueId == null && _lines.isNotEmpty) {
        _addTrajectoryLine(0, b.def.id);
        setState(() {
          _status = '連続軌道を追加しました（手玉→的球で続けられます）';
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
    if (_isPhone) {
      _spAxisBallId = b.def.id;
      _dragAxisX = false;
      _dragAxisY = false;
      setState(_setPhoneAxisStatus);
      return;
    }
  }

  void _addTrajectoryLine(int cueId, int objId) {
    final cue = _balls.firstWhere((x) => x.def.id == cueId);
    final obj = _balls.firstWhere((x) => x.def.id == objId);
    final felt = _felt;
    if (felt == Rect.zero) return;
    final br = _ballRadiusPx();
    final geom = TrajectoryGeometry.compute(
      felt: felt,
      ballRadiusPx: br,
      cueCenterPx: Offset(
          felt.left + cue.x * felt.width, felt.top + cue.y * felt.height),
      objCenterPx: Offset(
          felt.left + obj.x * felt.width, felt.top + obj.y * felt.height),
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
        ballRadiusPx: br,
        cueCenterPx: Offset(
          felt.left +
              _balls.firstWhere((e) => e.def.id == last.cueBallId).x *
                  felt.width,
          felt.top +
              _balls.firstWhere((e) => e.def.id == last.cueBallId).y *
                  felt.height,
        ),
        objCenterPx: Offset(
          felt.left +
              _balls.firstWhere((e) => e.def.id == last.objBallId).x *
                  felt.width,
          felt.top +
              _balls.firstWhere((e) => e.def.id == last.objBallId).y *
                  felt.height,
        ),
        contactOverrideNorm: last.contact,
        cueAnchorNorm: last.cueAnchor,
        objAnchorNorm: last.objAnchor,
        cueStartOverrideNorm: last.cueStartOverride,
        cueEndOverrideNorm: last.cueEndOverride,
        cueBounceEndOverrideNorm: last.cueBounceEndOverride,
        cueBounce2EndOverrideNorm: last.cueBounce2EndOverride,
        cueBounce3EndOverrideNorm: last.cueBounce3EndOverride,
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
      final brN = _ballRadiusPx() / _felt.width;
      final contactRadiusN = (brN * 2).clamp(0.012, 0.24);
      final dir =
          surf.distance < 1e-9 ? const Offset(0, -1) : surf / surf.distance;
      line.contact = centerObj + dir * contactRadiusN;
      line.cueAnchor = Offset.zero;
      line.objAnchor = Offset.zero;
      line.cueEndOverride = null;
      line.clearCueBounceOverrides();
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
      line.clearCueBounceOverrides();
      setState(() {});
      return;
    }

    if (_dragObjAIdx != null) {
      final line = _lines[_dragObjAIdx!];
      final ox = (nx - line.contact.dx).clamp(-0.5, 0.5);
      final oy = (ny - line.contact.dy).clamp(-0.5, 0.5);
      line.objAnchor = Offset(ox, oy);
      line.objBounceEndOverride = null;
      setState(() {});
      return;
    }

    if (_dragCueCushionLineIdx != null && _dragCueCushionSegIdx != null) {
      final line = _lines[_dragCueCushionLineIdx!];
      final seg = _dragCueCushionSegIdx!;
      final raw = Offset(nx, ny);
      final norm = _snapTrajNormToCushion(raw);
      switch (seg) {
        case 0:
          line.cueEndOverride = norm;
          line.clearCueBounceOverrides();
        case 1:
          line.cueBounceEndOverride = norm;
          line.clearCueBounceOverridesFrom(1);
        case 2:
          line.cueBounce2EndOverride = norm;
          line.clearCueBounceOverridesFrom(2);
        case 3:
          line.cueBounce3EndOverride = norm;
      }
      setState(() {});
      return;
    }

    if (_dragObjEndIdx != null) {
      final line = _lines[_dragObjEndIdx!];
      line.objEndOverride = _snapTrajNormToCushion(Offset(nx, ny));
      line.objBounceEndOverride = null;
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
    _dragCueCushionLineIdx = null;
    _dragCueCushionSegIdx = null;
    _dragObjEndIdx = null;
    _dragObjBounceEndIdx = null;
    final felt = _felt;
    final br = _ballRadiusPx();
    final phoneTrajEdit = _isPhone && _trajEditMode;
    final hitContact =
        phoneTrajEdit ? 46.0 : (_isPhone ? 32.0 : 14.0);
    final hitAnchor =
        phoneTrajEdit ? 50.0 : (_isPhone ? 36.0 : 16.0);
    final hitEnd = phoneTrajEdit ? 46.0 : (_isPhone ? 32.0 : 14.0);
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final cue = _balls.firstWhere((e) => e.def.id == line.cueBallId);
      final obj = _balls.firstWhere((e) => e.def.id == line.objBallId);
      final geom = TrajectoryGeometry.compute(
        felt: felt,
        ballRadiusPx: br,
        cueCenterPx: Offset(
            felt.left + cue.x * felt.width, felt.top + cue.y * felt.height),
        objCenterPx: Offset(
            felt.left + obj.x * felt.width, felt.top + obj.y * felt.height),
        contactOverrideNorm: line.contact,
        cueAnchorNorm: line.cueAnchor,
        objAnchorNorm: line.objAnchor,
        cueStartOverrideNorm: line.cueStartOverride,
        cueEndOverrideNorm: line.cueEndOverride,
        cueBounceEndOverrideNorm: line.cueBounceEndOverride,
        cueBounce2EndOverrideNorm: line.cueBounce2EndOverride,
        cueBounce3EndOverrideNorm: line.cueBounce3EndOverride,
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
      final cueChainPx = geom.cueCushionChain
          .map(
            (n) => Offset(
              felt.left + n.dx * felt.width,
              felt.top + n.dy * felt.height,
            ),
          )
          .toList(growable: false);
      final oe = Offset(
        felt.left + geom.objEnd.dx * felt.width,
        felt.top + geom.objEnd.dy * felt.height,
      );
      final obe = Offset(
        felt.left + geom.objBounceEnd.dx * felt.width,
        felt.top + geom.objBounceEnd.dy * felt.height,
      );
      if ((local - c).distance < hitContact) {
        setState(() {
          _dragContactIdx = i;
          _status = '接触点（赤丸）を調整中';
        });
        return;
      }
      if ((local - cc).distance < hitAnchor) {
        setState(() {
          _dragCueAIdx = i;
          _status = '手球の曲率（緑丸）を調整中';
        });
        return;
      }
      if ((local - oc).distance < hitAnchor) {
        setState(() {
          _dragObjAIdx = i;
          _status = '的球の曲率（黄丸）を調整中';
        });
        return;
      }
      for (var ci = cueChainPx.length - 1; ci >= 0; ci--) {
        if ((local - cueChainPx[ci]).distance < hitEnd) {
          setState(() {
            _dragCueCushionLineIdx = i;
            _dragCueCushionSegIdx = ci;
            _status = ci == 0
                ? '手球の終点（白丸）を調整中'
                : '手球のクッション後終点（${ci}点目）を調整中';
          });
          return;
        }
      }
      if ((local - oe).distance < hitEnd) {
        setState(() {
          _dragObjEndIdx = i;
          _status = '的球の終点（黄丸）を調整中';
        });
        return;
      }
      if (geom.objHitCushion && (local - obe).distance < hitEnd) {
        setState(() {
          _dragObjBounceEndIdx = i;
          _status = '的球のクッション後終点を調整中';
        });
        return;
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKey) ?? <String>[];
    final id =
        '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存しました')));
    }
  }

  void _undoLastTrajectory() {
    if (_lines.isEmpty) return;
    setState(() {
      _lines.removeLast();
      _selCueId = _lines.isEmpty ? 0 : null;
      _status = _lines.isEmpty
          ? _trajDrawStatus
          : '連続軌道: 的球をタップで追加 / 手玉タップで新規';
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

  Future<void> _openPhotoImport() async {
    await Navigator.of(context).pushNamed<void>('/photo-import');
  }

  Future<void> _openCameraCapture() async {
    await Navigator.of(context).pushNamed<void>('/camera-capture');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isPhone = media.size.shortestSide < 700;
    final usePortraitLayout =
        media.orientation == Orientation.portrait && media.size.width < 700;
    final body = usePortraitLayout
        ? _buildPortraitLayout(context)
        : isPhone
            ? _buildLandscapeLayout(context, phoneOptimized: true)
            : _buildDesktopPortraitLayout(context);
    return Scaffold(
      appBar: buildAppleGlassAppBar(
        context,
        title: '配置登録エディタ',
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppleColors.textOnDark,
          onPressed: () {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/setup', (route) => false);
          },
        ),
        actions: [
          IconButton(
            onPressed: _openSavedList,
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: '保存済み配置',
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  /// PC: portrait table (near-end view) + ball tray in a right column.
  Widget _buildDesktopPortraitLayout(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        _buildTopControls(dense: false),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRect(
                    child: _buildTableArea(
                      aspectRatio: 0.5,
                      phone: false,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildDesktopBallTray(),
              ],
            ),
          ),
        ),
        _buildBottomControls(
          context,
          compactInputs: false,
          showBallTray: false,
        ),
      ],
    );
  }

  Widget _buildDesktopBallTray() {
    const trayRadius = 26.0;
    const itemH = trayRadius * 2 + 10;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: itemH + 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text(
                'ボール',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                children: [
                  for (final b in _balls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Center(
                        child: _trayBall(b, radius: trayRadius),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(BuildContext context,
      {required bool phoneOptimized}) {
    if (phoneOptimized) {
      return Column(
        children: [
          const SizedBox(height: 10),
          _buildTopControls(dense: true, showModeSelector: false),
          const SizedBox(height: 6),
          Expanded(
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: _buildTableArea(
                  aspectRatio: _tableAspectForPhone(),
                  phone: true,
                ),
              ),
            ),
          ),
          _buildBottomControls(context, phoneLayout: true),
        ],
      );
    }
    // Fallback for wide short-side devices in landscape (rare).
    return Column(
      children: [
        const SizedBox(height: 12),
        _buildTopControls(dense: false),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Center(
              child: _buildTableFitted(aspectRatio: 0.5),
            ),
          ),
        ),
        _buildBottomControls(context, compactInputs: false),
      ],
    );
  }

  bool get _hasRefPhoto =>
      _refImageBytes != null &&
      _refImageSize != null &&
      _refCornersNorm != null &&
      _refCornersNorm!.length == 4;

  /// SP: 検出座標と同じ俯瞰 2:1。PC 手前視点は従来どおり 1:2。
  double _tableAspectForPhone() => TableGuideGeometry.playingAspect;

  Widget _buildTableArea({required double aspectRatio, bool phone = false}) {
    if (!_hasRefPhoto || !_showRefPhoto) {
      return phone
          ? _buildPhoneZoomableTable(aspectRatio: aspectRatio)
          : _buildTableFitted(aspectRatio: aspectRatio);
    }
    final portrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    if (phone && !portrait) {
      return _buildRefPhotoSplitHorizontal(aspectRatio);
    }
    return _buildRefPhotoSplitVertical(aspectRatio, phone: phone);
  }

  Widget _buildRefPhotoSplitVertical(double aspectRatio, {required bool phone}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalH = constraints.maxHeight;
        final photoH = (totalH * _refPhotoFlex).clamp(80.0, totalH - 120.0);
        final tableH = totalH - photoH - 6;
        return Column(
          children: [
            SizedBox(height: photoH, child: _buildReferencePhotoPanel()),
            GestureDetector(
              onVerticalDragUpdate: (d) {
                setState(() {
                  _refPhotoFlex = (_refPhotoFlex + d.delta.dy / totalH)
                      .clamp(0.22, 0.68);
                });
              },
              child: Container(
                height: 6,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.drag_handle, size: 14, color: Colors.black38),
                ),
              ),
            ),
            SizedBox(
              height: tableH,
              child: phone
                  ? _buildPhoneZoomableTable(aspectRatio: aspectRatio)
                  : _buildTableFitted(aspectRatio: aspectRatio),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRefPhotoSplitHorizontal(double aspectRatio) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final photoW = (totalW * 0.44).clamp(120.0, totalW - 160.0);
        return Row(
          children: [
            SizedBox(width: photoW, child: _buildReferencePhotoPanel()),
            const VerticalDivider(width: 1),
            Expanded(
              child: _buildPhoneZoomableTable(aspectRatio: aspectRatio),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReferencePhotoPanel() {
    final bytes = _refImageBytes!;
    final imageSize = _refImageSize!;
    final corners = _refCornersNorm!;
    return Material(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.black87,
            child: Text(
              '参照写真（ドラッグで比率変更）',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final maxH = constraints.maxHeight;
                if (maxW <= 0 || maxH <= 0) return const SizedBox.shrink();
                final scale = math.min(
                  maxW / imageSize.width,
                  maxH / imageSize.height,
                );
                final renderW = imageSize.width * scale;
                final renderH = imageSize.height * scale;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: SizedBox(
                        width: renderW,
                        height: renderH,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Image.memory(bytes, fit: BoxFit.fill),
                            CustomPaint(
                              painter: _ReferenceBallOverlayPainter(
                                balls: _balls
                                    .where((b) => b.onTable)
                                    .toList(growable: false),
                                cornersNorm: corners,
                                imageSize: imageSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 4),
        _buildTopControls(dense: true, showModeSelector: false),
        Expanded(
          child: ClipRect(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
              child: _buildTableArea(
                aspectRatio: _tableAspectForPhone(),
                phone: true,
              ),
            ),
          ),
        ),
        _buildBottomControls(context, phoneLayout: true),
      ],
    );
  }

  /// SP: キャンバスは画面幅いっぱい。初期ズームで全容表示、ピンチで幅いっぱいまで拡大。
  Widget _buildPhoneZoomableTable({required double aspectRatio}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        if (maxW <= 0 || maxH <= 0) return const SizedBox.shrink();

        final tableW = maxW;
        final tableH = tableW / aspectRatio;
        final fitScale = math.min(1.0, maxH / tableH);
        _applyPhoneZoomFit(maxW, maxH, aspectRatio);

        final lockPan = _trajEditMode ||
            _spAxisBallId != null ||
            _dragBallId != null ||
            _dragAxisX ||
            _dragAxisY;
        return InteractiveViewer(
          transformationController: _phoneZoomCtrl,
          minScale: fitScale,
          maxScale: 4.5,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(12),
          alignment: Alignment.topCenter,
          panEnabled: !lockPan,
          scaleEnabled: true,
          onInteractionEnd: (_) => _snapZoomBackToFit(fitScale),
          child: SizedBox(
            width: tableW,
            height: tableH,
            child: _buildTableCanvas(Size(tableW, tableH)),
          ),
        );
      },
    );
  }

  Widget _buildTopControls({
    required bool dense,
    bool showModeSelector = true,
  }) {
    final spacing = dense ? 6.0 : 8.0;
    final buttonStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
          if (showModeSelector) ...[
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
          ],
          if (_hasRefPhoto) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: Text(_showRefPhoto ? '参照写真 ON' : '参照写真 OFF'),
                selected: _showRefPhoto,
                onSelected: (v) => setState(() => _showRefPhoto = v),
              ),
            ),
            SizedBox(height: spacing),
          ],
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
                      side:
                          const BorderSide(color: Color(0xFF0A84FF), width: 1),
                    ),
                  ),
                  onPressed: () => setState(() {
                    _trajMode = !_trajMode;
                    _trajEditMode = false;
                    _selCueId = null;
                    _clearPhoneAxisGuides();
                    _status = _trajMode
                        ? _trajDrawStatus
                        : 'ドラッグで移動 / 380ms以内に2回タップでトレイへ';
                  }),
                  child: const Text('軌道描画'),
                ),
                SizedBox(width: spacing),
                OutlinedButton(
                  style: buttonStyle,
                  onPressed: _lines.isEmpty
                      ? null
                      : () => setState(() {
                            _trajMode = true;
                            _trajEditMode = !_trajEditMode;
                            _selCueId = null;
                            _clearPhoneAxisGuides();
                            _status = _trajEditMode
                                ? _trajEditStatus
                                : _trajDrawStatus;
                          }),
                  child: Text(_trajEditMode ? '点編集中' : '軌道点編集'),
                ),
                SizedBox(width: spacing),
                OutlinedButton(
                  style: buttonStyle,
                  onPressed: _clearAllTrajectories,
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
                  onPressed: _openCameraCapture,
                  child: const Text('配置を取る'),
                ),
                SizedBox(width: spacing),
                OutlinedButton(
                  style: buttonStyle,
                  onPressed: _openPhotoImport,
                  child: const Text('写真から読込'),
                ),
                SizedBox(width: spacing),
                OutlinedButton(
                  style: buttonStyle,
                  onPressed: () =>
                      setState(() => _applyMode(_mode, resetPositions: true)),
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

  Future<void> _openTagMemoSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final bottom = MediaQuery.viewInsetsOf(sheetCtx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'タグ・メモ',
                style: Theme.of(sheetCtx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tagCtrl,
                decoration: const InputDecoration(
                  labelText: 'タグ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _memoCtrl,
                decoration: const InputDecoration(
                  labelText: 'メモ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 4,
                minLines: 2,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: const Text('完了'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomControls(
    BuildContext context, {
    bool compactInputs = true,
    bool phoneLayout = false,
    bool showBallTray = true,
  }) {
    final trayHeight = phoneLayout ? 50.0 : 78.0;
    final trayRadius = phoneLayout ? 20.0 : 28.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: phoneLayout ? 4 : 8,
          ),
          child: Text(
            _status,
            maxLines: phoneLayout ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: phoneLayout ? 14 : 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        if (showBallTray)
          SizedBox(
            height: trayHeight,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: phoneLayout ? 6 : 8),
              children:
                  _balls.map((b) => _trayBall(b, radius: trayRadius)).toList(),
            ),
          ),
        if (phoneLayout)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _openTagMemoSheet,
                child: Text(
                  _tagCtrl.text.isNotEmpty || _memoCtrl.text.isNotEmpty
                      ? 'タグ・メモを編集'
                      : 'タグ・メモを入力',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 13,
                        color: AppleColors.appleBlue,
                      ),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: EdgeInsets.fromLTRB(12, phoneLayout ? 4 : 8, 12, phoneLayout ? 6 : 12),
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
              ballRadiusPx: _ballRadiusPx(),
              lines: _lines,
              ballMap: {for (final b in _balls) b.def.id: b},
              editMode: _trajEditMode,
              draggingContactIndex: _dragContactIdx,
              draggingCueAnchorIndex: _dragCueAIdx,
              draggingObjAnchorIndex: _dragObjAIdx,
              draggingCueCushionLineIndex: _dragCueCushionLineIdx,
              draggingCueCushionSegIndex: _dragCueCushionSegIdx,
              draggingObjEndIndex: _dragObjEndIdx,
              draggingObjBounceEndIndex: _dragObjBounceEndIdx,
            ),
          ),
        ),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              if (_isPhone && _spAxisBallId != null && !_trajMode) {
                final p = e.localPosition;
                final hitBall = _balls.any(
                  (b) => b.onTable && _isNearBallCenter(p, b, 28),
                );
                final axisBall = _balls.cast<BallInstance?>().firstWhere(
                      (x) => x?.def.id == _spAxisBallId && x!.onTable,
                      orElse: () => null,
                    );
                final hitAxis = axisBall != null &&
                    ((p.dx - (_felt.left + axisBall.x * _felt.width)).abs() <=
                            22 ||
                        (p.dy - (_felt.top + axisBall.y * _felt.height)).abs() <=
                            22);
                if (!hitBall && !hitAxis) {
                  setState(_clearPhoneAxisGuides);
                }
              }
              if (!_trajMode || !_trajEditMode) return;
              _pickTrajControl(e.localPosition);
            },
            onPointerMove: (e) {
              if (_dragContactIdx != null ||
                  _dragCueAIdx != null ||
                  _dragObjAIdx != null ||
                  _dragCueCushionLineIdx != null ||
                  _dragObjEndIdx != null ||
                  _dragObjBounceEndIdx != null) {
                _onTablePanUpdate(e.localPosition);
              }
            },
            onPointerUp: (_) {
              _dragContactIdx = null;
              _dragCueAIdx = null;
              _dragObjAIdx = null;
              _dragCueCushionLineIdx = null;
              _dragCueCushionSegIdx = null;
              _dragObjEndIdx = null;
              _dragObjBounceEndIdx = null;
              if (_trajEditMode) {
                setState(() => _status = _trajEditStatus);
              }
            },
            onPointerCancel: (_) {
              _dragContactIdx = null;
              _dragCueAIdx = null;
              _dragObjAIdx = null;
              _dragCueCushionLineIdx = null;
              _dragCueCushionSegIdx = null;
              _dragObjEndIdx = null;
              _dragObjBounceEndIdx = null;
              if (_trajEditMode) {
                setState(() => _status = _trajEditStatus);
              }
            },
          ),
        ),
        if (_isPhone && _spAxisBallId != null && !_trajMode)
          _buildPhoneAxisGuides(),
        ..._balls.where((b) => b.onTable).map((b) => _ballPositioned(b)),
      ],
    );
  }

  Widget _buildPhoneAxisGuides() {
    final felt = _felt;
    if (felt == Rect.zero) return const SizedBox.shrink();
    final b = _balls.cast<BallInstance?>().firstWhere(
          (e) => e?.def.id == _spAxisBallId && e!.onTable,
          orElse: () => null,
        );
    if (b == null) return const SizedBox.shrink();

    final cx = felt.left + b.x * felt.width;
    final cy = felt.top + b.y * felt.height;
    const guideHit = 44.0;
    const lineIdle = Color.fromRGBO(255, 255, 255, 0.72);
    const lineActive = Color.fromRGBO(255, 255, 255, 0.98);

    return Stack(
      children: [
        // 縦線をドラッグ → 左右（X）
        Positioned(
          left: cx - (guideHit / 2),
          top: felt.top,
          width: guideHit,
          height: felt.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => setState(() => _dragAxisX = true),
            onPanUpdate: (d) {
              final nextX = (b.x + (d.delta.dx / felt.width)).clamp(0.0, 1.0);
              setState(() {
                b.x = nextX;
                _dragAxisX = true;
              });
            },
            onPanEnd: (_) {
              if (_dragAxisX) setState(() => _dragAxisX = false);
            },
            onPanCancel: () {
              if (_dragAxisX) setState(() => _dragAxisX = false);
            },
            child: CustomPaint(
              painter: _GuideLinePainter(
                isVertical: true,
                color: _dragAxisX ? lineActive : lineIdle,
                active: _dragAxisX,
              ),
            ),
          ),
        ),
        // 横線をドラッグ → 上下（Y）
        Positioned(
          left: felt.left,
          top: cy - (guideHit / 2),
          width: felt.width,
          height: guideHit,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => setState(() => _dragAxisY = true),
            onPanUpdate: (d) {
              final nextY = (b.y + (d.delta.dy / felt.height)).clamp(0.0, 1.0);
              setState(() {
                b.y = nextY;
                _dragAxisY = true;
              });
            },
            onPanEnd: (_) {
              if (_dragAxisY) setState(() => _dragAxisY = false);
            },
            onPanCancel: () {
              if (_dragAxisY) setState(() => _dragAxisY = false);
            },
            child: CustomPaint(
              painter: _GuideLinePainter(
                isVertical: false,
                color: _dragAxisY ? lineActive : lineIdle,
                active: _dragAxisY,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ballPositioned(BallInstance b) {
    final felt = _felt;
    final r = _ballRadiusPx();
    final isDraggingThisBall = !_trajMode && _dragBallId == b.def.id;
    final visualScale = isDraggingThisBall ? 1.45 : 1.0;
    final visualRadius = r * visualScale;
    final hitSize =
        _isPhone ? math.max(visualRadius * 2, 44.0) : visualRadius * 2;
    final left = felt.left + b.x * felt.width - (hitSize / 2);
    final top = felt.top + b.y * felt.height - (hitSize / 2);
    return Positioned(
      left: left,
      top: top,
      width: hitSize,
      height: hitSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) =>
            _handleBallPointerDown(b, d.localPosition, d.localPosition),
        onPanUpdate: (d) {
          if (!_trajMode && _dragBallId == b.def.id) {
            final stackBox =
                _tableStackKey.currentContext?.findRenderObject() as RenderBox?;
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
        child: Center(
          child: AnimatedScale(
            scale: visualScale,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: Container(
              decoration: BoxDecoration(
                boxShadow: isDraggingThisBall
                    ? [
                        BoxShadow(
                          color: AppleColors.appleBlue.withValues(alpha: 0.35),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: r * 2,
                height: r * 2,
                child: CustomPaint(
                  painter: _BallPainter(ball: b, radius: r),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trayBall(BallInstance b, {double radius = 28.0}) {
    final r = radius;
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
      canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: c, radius: radius * 0.92)));
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

class _GuideLinePainter extends CustomPainter {
  _GuideLinePainter({
    required this.isVertical,
    required this.color,
    this.active = false,
  });

  final bool isVertical;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = active ? 2.0 : 1.5;
    if (isVertical) {
      final x = size.width / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      return;
    }
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(covariant _GuideLinePainter oldDelegate) =>
      oldDelegate.isVertical != isVertical ||
      oldDelegate.color != color ||
      oldDelegate.active != active;
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
    final next = raw
        .where((s) => SavedBallLayout.fromJsonString(s)?.id != doc.id)
        .toList();
    await prefs.setStringList(_prefKey, next);
    await _load();
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/setup', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppleGlassAppBar(
        context,
        title: '保存した配置',
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppleColors.textOnDark,
          onPressed: _goBack,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final doc = _items[i];
                return ListTile(
                  title: Text(doc.tag.isEmpty ? '(無題)' : doc.tag),
                  subtitle: Text(
                      '${doc.mode.storageKey}球 · ${doc.createdAt}\n${doc.memo}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(doc),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BallLayoutEditorScreen(initialLayout: doc),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _ReferenceBallOverlayPainter extends CustomPainter {
  _ReferenceBallOverlayPainter({
    required this.balls,
    required this.cornersNorm,
    required this.imageSize,
  });

  final List<BallInstance> balls;
  final List<List<double>> cornersNorm;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    final fill = Paint()..color = const Color(0xAAFF9500);

    for (final ball in balls) {
      final norm = FeltHomography.warpNormToImageNorm(
        Offset(ball.x, ball.y),
        cornersNorm,
        imageSize,
      );
      if (norm == null) continue;
      final cx = norm.dx * size.width;
      final cy = norm.dy * size.height;
      final r = math.min(size.width, size.height) * 0.018;
      canvas.drawCircle(Offset(cx, cy), r, fill);
      canvas.drawCircle(Offset(cx, cy), r, stroke);
      final tp = TextPainter(
        text: TextSpan(
          text: ball.def.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ReferenceBallOverlayPainter old) => true;
}
