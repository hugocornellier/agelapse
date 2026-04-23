class TransformCacheEntry {
  final int? id;
  final String cacheKey;
  final int projectId;
  final String fingerprint;
  final String projectType;
  final String modelVersion;
  final String transformAlgorithmVersion;
  final String settingsHash;
  final String scope;
  final String sourceOrientation;
  final int? selectedFaceIndex;
  final int? faceCount;
  final int? sourceWidth;
  final int? sourceHeight;
  final int canvasWidth;
  final int canvasHeight;
  final double translateX;
  final double translateY;
  final double rotationDegrees;
  final double scaleFactor;
  final double? finalScore;
  final double? finalEyeDeltaY;
  final double? finalEyeDistance;
  final double? goalEyeDistance;
  final double? preScore;
  final double? rotationPassScore;
  final double? scalePassScore;
  final double? translationPassScore;
  final bool isEstimated;
  final String? exampleTimestamp;
  final int createdAt;
  final int updatedAt;
  final int hitCount;

  const TransformCacheEntry({
    this.id,
    required this.cacheKey,
    required this.projectId,
    required this.fingerprint,
    required this.projectType,
    required this.modelVersion,
    required this.transformAlgorithmVersion,
    required this.settingsHash,
    required this.scope,
    required this.sourceOrientation,
    this.selectedFaceIndex,
    this.faceCount,
    this.sourceWidth,
    this.sourceHeight,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.translateX,
    required this.translateY,
    required this.rotationDegrees,
    required this.scaleFactor,
    this.finalScore,
    this.finalEyeDeltaY,
    this.finalEyeDistance,
    this.goalEyeDistance,
    this.preScore,
    this.rotationPassScore,
    this.scalePassScore,
    this.translationPassScore,
    this.isEstimated = false,
    this.exampleTimestamp,
    required this.createdAt,
    required this.updatedAt,
    this.hitCount = 0,
  });

  Map<String, Object?> toMap({bool includeId = false}) {
    return {
      if (includeId && id != null) 'id': id,
      'cacheKey': cacheKey,
      'projectID': projectId,
      'fingerprint': fingerprint,
      'projectType': projectType,
      'modelVersion': modelVersion,
      'transformAlgorithmVersion': transformAlgorithmVersion,
      'settingsHash': settingsHash,
      'scope': scope,
      'sourceOrientation': sourceOrientation,
      'selectedFaceIndex': selectedFaceIndex,
      'faceCount': faceCount,
      'sourceWidth': sourceWidth,
      'sourceHeight': sourceHeight,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
      'translateX': translateX,
      'translateY': translateY,
      'rotationDegrees': rotationDegrees,
      'scaleFactor': scaleFactor,
      'finalScore': finalScore,
      'finalEyeDeltaY': finalEyeDeltaY,
      'finalEyeDistance': finalEyeDistance,
      'goalEyeDistance': goalEyeDistance,
      'preScore': preScore,
      'rotationPassScore': rotationPassScore,
      'scalePassScore': scalePassScore,
      'translationPassScore': translationPassScore,
      'isEstimated': isEstimated ? 1 : 0,
      'exampleTimestamp': exampleTimestamp,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'hitCount': hitCount,
    };
  }

  factory TransformCacheEntry.fromMap(Map<String, Object?> map) {
    return TransformCacheEntry(
      id: map['id'] as int?,
      cacheKey: map['cacheKey'] as String,
      projectId: map['projectID'] as int,
      fingerprint: map['fingerprint'] as String,
      projectType: map['projectType'] as String,
      modelVersion: map['modelVersion'] as String,
      transformAlgorithmVersion: map['transformAlgorithmVersion'] as String,
      settingsHash: map['settingsHash'] as String,
      scope: map['scope'] as String,
      sourceOrientation: map['sourceOrientation'] as String,
      selectedFaceIndex: map['selectedFaceIndex'] as int?,
      faceCount: map['faceCount'] as int?,
      sourceWidth: map['sourceWidth'] as int?,
      sourceHeight: map['sourceHeight'] as int?,
      canvasWidth: map['canvasWidth'] as int,
      canvasHeight: map['canvasHeight'] as int,
      translateX: (map['translateX'] as num).toDouble(),
      translateY: (map['translateY'] as num).toDouble(),
      rotationDegrees: (map['rotationDegrees'] as num).toDouble(),
      scaleFactor: (map['scaleFactor'] as num).toDouble(),
      finalScore: (map['finalScore'] as num?)?.toDouble(),
      finalEyeDeltaY: (map['finalEyeDeltaY'] as num?)?.toDouble(),
      finalEyeDistance: (map['finalEyeDistance'] as num?)?.toDouble(),
      goalEyeDistance: (map['goalEyeDistance'] as num?)?.toDouble(),
      preScore: (map['preScore'] as num?)?.toDouble(),
      rotationPassScore: (map['rotationPassScore'] as num?)?.toDouble(),
      scalePassScore: (map['scalePassScore'] as num?)?.toDouble(),
      translationPassScore: (map['translationPassScore'] as num?)?.toDouble(),
      isEstimated: map['isEstimated'] == 1,
      exampleTimestamp: map['exampleTimestamp'] as String?,
      createdAt: map['createdAt'] as int,
      updatedAt: map['updatedAt'] as int,
      hitCount: map['hitCount'] as int,
    );
  }

  TransformCacheEntry copyWith({
    int? id,
    String? cacheKey,
    int? projectId,
    String? fingerprint,
    String? projectType,
    String? modelVersion,
    String? transformAlgorithmVersion,
    String? settingsHash,
    String? scope,
    String? sourceOrientation,
    int? selectedFaceIndex,
    int? faceCount,
    int? sourceWidth,
    int? sourceHeight,
    int? canvasWidth,
    int? canvasHeight,
    double? translateX,
    double? translateY,
    double? rotationDegrees,
    double? scaleFactor,
    double? finalScore,
    double? finalEyeDeltaY,
    double? finalEyeDistance,
    double? goalEyeDistance,
    double? preScore,
    double? rotationPassScore,
    double? scalePassScore,
    double? translationPassScore,
    bool? isEstimated,
    String? exampleTimestamp,
    int? createdAt,
    int? updatedAt,
    int? hitCount,
  }) {
    return TransformCacheEntry(
      id: id ?? this.id,
      cacheKey: cacheKey ?? this.cacheKey,
      projectId: projectId ?? this.projectId,
      fingerprint: fingerprint ?? this.fingerprint,
      projectType: projectType ?? this.projectType,
      modelVersion: modelVersion ?? this.modelVersion,
      transformAlgorithmVersion:
          transformAlgorithmVersion ?? this.transformAlgorithmVersion,
      settingsHash: settingsHash ?? this.settingsHash,
      scope: scope ?? this.scope,
      sourceOrientation: sourceOrientation ?? this.sourceOrientation,
      selectedFaceIndex: selectedFaceIndex ?? this.selectedFaceIndex,
      faceCount: faceCount ?? this.faceCount,
      sourceWidth: sourceWidth ?? this.sourceWidth,
      sourceHeight: sourceHeight ?? this.sourceHeight,
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
      translateX: translateX ?? this.translateX,
      translateY: translateY ?? this.translateY,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      scaleFactor: scaleFactor ?? this.scaleFactor,
      finalScore: finalScore ?? this.finalScore,
      finalEyeDeltaY: finalEyeDeltaY ?? this.finalEyeDeltaY,
      finalEyeDistance: finalEyeDistance ?? this.finalEyeDistance,
      goalEyeDistance: goalEyeDistance ?? this.goalEyeDistance,
      preScore: preScore ?? this.preScore,
      rotationPassScore: rotationPassScore ?? this.rotationPassScore,
      scalePassScore: scalePassScore ?? this.scalePassScore,
      translationPassScore: translationPassScore ?? this.translationPassScore,
      isEstimated: isEstimated ?? this.isEstimated,
      exampleTimestamp: exampleTimestamp ?? this.exampleTimestamp,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hitCount: hitCount ?? this.hitCount,
    );
  }
}
