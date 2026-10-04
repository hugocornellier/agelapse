/*
    This file is originally from gocv project
    Licensed: Apache 2.0 license. Copyright (c) 2017-2021 The Hybrid Group.

    Modified by Rainyl.
    Licensed: Apache 2.0 license. Copyright (c) 2024 Rainyl.
*/
#ifndef _OPENCV3_ARUCO_H_
#define _OPENCV3_ARUCO_H_

#ifdef __cplusplus
#include <opencv2/aruco.hpp>
#include <opencv2/objdetect/aruco_board.hpp>
#include <opencv2/objdetect/charuco_detector.hpp>
extern "C" {
#endif

#include "dartcv/core/types.h"

#ifdef __cplusplus
CVD_TYPEDEF(cv::aruco::Dictionary, ArucoDictionary);
CVD_TYPEDEF(cv::aruco::DetectorParameters, ArucoDetectorParams);
CVD_TYPEDEF(cv::aruco::RefineParameters, ArucoRefineParams);
CVD_TYPEDEF(cv::aruco::ArucoDetector, ArucoDetector);
CVD_TYPEDEF(cv::aruco::CharucoBoard, CharucoBoard);
CVD_TYPEDEF(cv::aruco::CharucoParameters, CharucoDetectorParams);
CVD_TYPEDEF(cv::aruco::CharucoDetector, CharucoDetector);
#else
CVD_TYPEDEF(void, ArucoDictionary);
CVD_TYPEDEF(void, ArucoDetectorParams);
CVD_TYPEDEF(void, ArucoRefineParams);
CVD_TYPEDEF(void, ArucoDetector);
CVD_TYPEDEF(void, CharucoBoard);
CVD_TYPEDEF(void, CharucoDetectorParams);
CVD_TYPEDEF(void, CharucoDetector);
#endif

CvStatus* cv_aruco_detectorParameters_create(ArucoDetectorParams* rval);
void cv_aruco_detectorParameters_close(ArucoDetectorParamsPtr ap);
void cv_aruco_detectorParameters_set_adaptiveThreshWinSizeMin(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_adaptiveThreshWinSizeMin(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_adaptiveThreshWinSizeMax(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_adaptiveThreshWinSizeMax(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_adaptiveThreshWinSizeStep(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_adaptiveThreshWinSizeStep(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_adaptiveThreshConstant(ArucoDetectorParams self, double value);
double cv_aruco_detectorParameters_get_adaptiveThreshConstant(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_minMarkerPerimeterRate(ArucoDetectorParams self, double value);
double cv_aruco_detectorParameters_get_minMarkerPerimeterRate(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_maxMarkerPerimeterRate(ArucoDetectorParams self, double value);
double cv_aruco_detectorParameters_get_maxMarkerPerimeterRate(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_polygonalApproxAccuracyRate(
    ArucoDetectorParams self, double value
);
double cv_aruco_detectorParameters_get_polygonalApproxAccuracyRate(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_minCornerDistanceRate(ArucoDetectorParams self, double value);
double cv_aruco_detectorParameters_get_minCornerDistanceRate(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_minDistanceToBorder(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_minDistanceToBorder(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_minMarkerDistanceRate(ArucoDetectorParams self, double value);
double cv_aruco_detectorParameters_get_minMarkerDistanceRate(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_cornerRefinementMethod(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_cornerRefinementMethod(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_cornerRefinementWinSize(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_cornerRefinementWinSize(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_cornerRefinementMaxIterations(
    ArucoDetectorParams self, int value
);
int cv_aruco_detectorParameters_get_cornerRefinementMaxIterations(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_cornerRefinementMinAccuracy(
    ArucoDetectorParams self, double value
);
double cv_aruco_detectorParameters_get_cornerRefinementMinAccuracy(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_markerBorderBits(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_markerBorderBits(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_perspectiveRemovePixelPerCell(
    ArucoDetectorParams self, int value
);
int cv_aruco_detectorParameters_get_perspectiveRemovePixelPerCell(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_perspectiveRemoveIgnoredMarginPerCell(
    ArucoDetectorParams self, double value
);
double cv_aruco_detectorParameters_get_perspectiveRemoveIgnoredMarginPerCell(
    ArucoDetectorParams self
);
void cv_aruco_detectorParameters_set_maxErroneousBitsInBorderRate(
    ArucoDetectorParams self, double value
);
double cv_aruco_detectorParameters_get_maxErroneousBitsInBorderRate(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_minOtsuStdDev(ArucoDetectorParams self, double value);
double cv_aruco_detectorParameters_get_minOtsuStdDev(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_errorCorrectionRate(ArucoDetectorParams self, double value);
double cv_aruco_detectorParameters_get_errorCorrectionRate(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_aprilTagQuadDecimate(ArucoDetectorParams self, float value);
float cv_aruco_detectorParameters_get_aprilTagQuadDecimate(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_aprilTagQuadSigma(ArucoDetectorParams self, float value);
float cv_aruco_detectorParameters_get_aprilTagQuadSigma(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_aprilTagMinClusterPixels(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_aprilTagMinClusterPixels(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_aprilTagMaxNmaxima(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_aprilTagMaxNmaxima(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_aprilTagCriticalRad(ArucoDetectorParams self, float value);
float cv_aruco_detectorParameters_get_aprilTagCriticalRad(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_aprilTagMaxLineFitMse(ArucoDetectorParams self, float value);
float cv_aruco_detectorParameters_get_aprilTagMaxLineFitMse(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_aprilTagMinWhiteBlackDiff(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_aprilTagMinWhiteBlackDiff(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_aprilTagDeglitch(ArucoDetectorParams self, int value);
int cv_aruco_detectorParameters_get_aprilTagDeglitch(ArucoDetectorParams self);
void cv_aruco_detectorParameters_set_detectInvertedMarker(ArucoDetectorParams self, bool value);
bool cv_aruco_detectorParameters_get_detectInvertedMarker(ArucoDetectorParams self);

CvStatus* cv_aruco_refineParameters_create(ArucoRefineParams* rval);
CvStatus* cv_aruco_refineParameters_create_1(
    float minRepDistance,
    float errorCorrectionRate,
    bool checkAllOrders,
    ArucoRefineParams* rval
);
void cv_aruco_refineParameters_close(ArucoRefineParamsPtr self);
float cv_aruco_refineParameters_get_minRepDistance(ArucoRefineParams self);
void cv_aruco_refineParameters_set_minRepDistance(ArucoRefineParams self, float value);
float cv_aruco_refineParameters_get_errorCorrectionRate(ArucoRefineParams self);
void cv_aruco_refineParameters_set_errorCorrectionRate(ArucoRefineParams self, float value);
bool cv_aruco_refineParameters_get_checkAllOrders(ArucoRefineParams self);
void cv_aruco_refineParameters_set_checkAllOrders(ArucoRefineParams self, bool value);

CvStatus* cv_aruco_getPredefinedDictionary(int dictionaryId, ArucoDictionary* rval);
CvStatus* cv_aruco_Dictionary_create(ArucoDictionary* rval);
CvStatus* cv_aruco_Dictionary_create_1(
    Mat bytesList, int markerSize, int maxCorr, ArucoDictionary* rval
);
CvStatus* cv_aruco_Dictionary_generateImageMarker(
    ArucoDictionary self, int id, int sidePixels, Mat _img, int borderBits
);
int cv_aruco_Dictionary_getDistanceToId(ArucoDictionary self, Mat bits, int id, bool allRotations);
bool cv_aruco_Dictionary_identify(
    ArucoDictionary self, Mat onlyBits, int* idx, int* rotation, double maxCorrectionRate
);
CvStatus* cv_aruco_Dictionary_get_bytesList(ArucoDictionary self, Mat* rval);
int cv_aruco_Dictionary_get_markerSize(ArucoDictionary self);
int cv_aruco_Dictionary_get_maxCorrectionBits(ArucoDictionary self);
CvStatus* cv_aruco_Dictionary_set_bytesList(ArucoDictionary self, Mat value);
void cv_aruco_Dictionary_set_markerSize(ArucoDictionary self, int value);
void cv_aruco_Dictionary_set_maxCorrectionBits(ArucoDictionary self, int value);
void cv_aruco_Dictionary_close(ArucoDictionaryPtr self);

CvStatus* cv_aruco_arucoDetector_create(ArucoDetector* rval);
CvStatus* cv_aruco_arucoDetector_create_1(
    ArucoDictionary dictionary,
    ArucoDetectorParams params,
    ArucoDetector* rval
);
void cv_aruco_arucoDetector_close(ArucoDetectorPtr self);
CvStatus* cv_aruco_arucoDetector_detectMarkers(
    ArucoDetector self,
    Mat inputArr,
    VecVecPoint2f* out_markerCorners,
    VecI32* out_markerIds,
    VecVecPoint2f* out_rejectedCandidates,
    CvCallback_0 callback
);

CvStatus* cv_aruco_drawDetectedMarkers(
    Mat image,
    VecVecPoint2f markerCorners,
    VecI32 markerIds,
    Scalar borderColor,
    CvCallback_0 callback
);
CvStatus* cv_aruco_generateImageMarker(
    int dictionaryId, int id, int sidePixels, int borderBits, Mat dst, CvCallback_0 callback
);

CvStatus* cv_aruco_charucoBoard_create(CharucoBoard* rval);
CvStatus* cv_aruco_charucoBoard_create_1(
    CvSize size,
    float squareLength,
    float markerLength,
    ArucoDictionary dictionary,
    CharucoBoard* rval
);
CvStatus* cv_aruco_charucoBoard_create_2(
    CvSize size,
    float squareLength,
    float markerLength,
    ArucoDictionary dictionary,
    VecI32 ids,
    CharucoBoard* rval
);
void cv_aruco_charucoBoard_close(CharucoBoardPtr self);
bool cv_aruco_charucoBoard_checkCharucoCornersCollinear(CharucoBoard self, VecI32 charucoIds);
CvStatus* cv_aruco_charucoBoard_generateImage(
    CharucoBoard self,
    CvSize outSize,
    Mat img,
    int marginSize,
    int borderBits,
    CvCallback_0 callback
);
CvStatus* cv_aruco_charucoBoard_getChessboardCorners(CharucoBoard self, VecPoint3f* rval);
CvSize cv_aruco_charucoBoard_getChessboardSize(CharucoBoard self);
float cv_aruco_charucoBoard_getMarkerLength(CharucoBoard self);
float cv_aruco_charucoBoard_getSquareLength(CharucoBoard self);
bool cv_aruco_charucoBoard_getLegacyPattern(CharucoBoard self);
void cv_aruco_charucoBoard_setLegacyPattern(CharucoBoard self, bool value);
CvStatus* cv_aruco_charucoBoard_getIds(CharucoBoard self, VecI32* rval);
CvStatus* cv_aruco_charucoBoard_getObjPoints(CharucoBoard self, VecVecPoint3f* rval);
CvStatus* cv_aruco_charucoBoard_matchImagePoints(
    CharucoBoard self,
    VecPoint2f detectedCharuco,
    VecI32 detectedIds,
    Mat objPoints,
    Mat imgPoints,
    CvCallback_0 callback
);

CvStatus* cv_aruco_charucoDetectorParameters_create(CharucoDetectorParams* rval);
void cv_aruco_charucoDetectorParameters_close(CharucoDetectorParamsPtr self);
CvStatus* cv_aruco_charucoDetectorParameters_get_cameraMatrix(CharucoDetectorParams self, Mat* rval);
CvStatus* cv_aruco_charucoDetectorParameters_set_cameraMatrix(CharucoDetectorParams self, Mat value);
CvStatus* cv_aruco_charucoDetectorParameters_get_distCoeffs(CharucoDetectorParams self, Mat* rval);
CvStatus* cv_aruco_charucoDetectorParameters_set_distCoeffs(CharucoDetectorParams self, Mat value);
int cv_aruco_charucoDetectorParameters_get_minMarkers(CharucoDetectorParams self);
void cv_aruco_charucoDetectorParameters_set_minMarkers(CharucoDetectorParams self, int value);
bool cv_aruco_charucoDetectorParameters_get_tryRefineMarkers(CharucoDetectorParams self);
void cv_aruco_charucoDetectorParameters_set_tryRefineMarkers(CharucoDetectorParams self, bool value);
bool cv_aruco_charucoDetectorParameters_get_checkMarkers(CharucoDetectorParams self);
void cv_aruco_charucoDetectorParameters_set_checkMarkers(CharucoDetectorParams self, bool value);

CvStatus* cv_aruco_charucoDetector_create_1(
    CharucoBoard board,
    CharucoDetector* rval
);
CvStatus* cv_aruco_charucoDetector_create_2(
    CharucoBoard board,
    CharucoDetectorParams charucoParams,
    CharucoDetector* rval
);
CvStatus* cv_aruco_charucoDetector_create_3(
    CharucoBoard board,
    CharucoDetectorParams charucoParams,
    ArucoDetectorParams detectorParams,
    CharucoDetector* rval
);
CvStatus* cv_aruco_charucoDetector_create_4(
    CharucoBoard board,
    CharucoDetectorParams charucoParams,
    ArucoDetectorParams detectorParams,
    ArucoRefineParams refineParams,
    CharucoDetector* rval
);
void cv_aruco_charucoDetector_close(CharucoDetectorPtr self);
CvStatus* cv_aruco_charucoDetector_detectBoard(
    CharucoDetector self,
    Mat image,
    VecPoint2f* out_charucoCorners,
    VecI32* out_charucoIds,
    VecVecPoint2f* inout_markerCorners,
    VecI32* inout_markerIds,
    CvCallback_0 callback
);
CvStatus* cv_aruco_charucoDetector_detectDiamonds(
    CharucoDetector self,
    Mat image,
    VecVecPoint2f* out_diamondCorners,
    VecVec4i* out_diamondIds,
    VecVecPoint2f* inout_markerCorners,
    VecI32* inout_markerIds,
    CvCallback_0 callback
);
CvStatus* cv_aruco_charucoDetector_getBoard(CharucoDetector self, CharucoBoard* rval);
void cv_aruco_charucoDetector_setBoard(CharucoDetector self, CharucoBoard board);
CvStatus* cv_aruco_charucoDetector_getCharucoParameters(
    CharucoDetector self,
    CharucoDetectorParams* rval
);
void cv_aruco_charucoDetector_setCharucoParameters(
    CharucoDetector self,
    CharucoDetectorParams params
);
CvStatus* cv_aruco_charucoDetector_getDetectorParameters(
    CharucoDetector self,
    ArucoDetectorParams* rval
);
void cv_aruco_charucoDetector_setDetectorParameters(
    CharucoDetector self,
    ArucoDetectorParams params
);
CvStatus* cv_aruco_charucoDetector_getRefineParameters(
    CharucoDetector self,
    ArucoRefineParams* rval
);
void cv_aruco_charucoDetector_setRefineParameters(
    CharucoDetector self,
    ArucoRefineParams params
);

CvStatus* cv_aruco_drawDetectedCornersCharuco(
    Mat image,
    VecPoint2f charucoCorners,
    VecI32 charucoIds,
    Scalar cornerColor,
    CvCallback_0 callback
);
CvStatus* cv_aruco_estimatePoseCharucoBoard(
    VecPoint2f charucoCorners,
    VecI32 charucoIds,
    CharucoBoard board,
    Mat cameraMatrix,
    Mat distCoeffs,
    Mat rvec,
    Mat tvec,
    bool useExtrinsicGuess,
    bool* rval,
    CvCallback_0 callback
);

#ifdef __cplusplus
}
#endif

#endif  //_OPENCV3_ARUCO_H_
