import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Win32 file-time helpers (NTFS creation/"birth" time) implemented with
/// `dart:ffi`, replacing a per-photo `powershell.exe` spawn.
///
/// Dart's `File` API can set the modified time (`setLastModified`) but not the
/// Windows creation time, so the import/capture pipeline previously launched one
/// `powershell.exe` process per saved photo just to copy that single timestamp.
/// A cold PowerShell launch costs ~200-600ms and ran *inside* the save mutex,
/// serializing every parallel import worker behind it. Calling
/// `CreateFileW` / `GetFileTime` / `SetFileTime` over FFI does the exact same
/// work in a few microseconds and produces a byte-identical creation timestamp
/// (FILETIME is 100ns resolution, matching the .NET DateTime PowerShell used).
///
/// The `dart:ffi` / `package:ffi` imports are platform-agnostic; kernel32.dll is
/// only opened when one of these functions actually runs, and every function is
/// guarded by `Platform.isWindows`. On every other platform they are no-ops.

// --- Win32 constants --------------------------------------------------------

const int _genericRead = 0x80000000;
const int _fileWriteAttributes = 0x100;
// FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE
const int _fileShareAll = 0x07;
const int _openExisting = 3;
const int _fileFlagBackupSemantics = 0x02000000;
const int _invalidHandleValue = -1;

// --- Win32 signatures -------------------------------------------------------

typedef _CreateFileWNative = IntPtr Function(
  Pointer<Utf16> lpFileName,
  Uint32 dwDesiredAccess,
  Uint32 dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  Uint32 dwCreationDisposition,
  Uint32 dwFlagsAndAttributes,
  IntPtr hTemplateFile,
);
typedef _CreateFileWDart = int Function(
  Pointer<Utf16> lpFileName,
  int dwDesiredAccess,
  int dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  int dwCreationDisposition,
  int dwFlagsAndAttributes,
  int hTemplateFile,
);

// GetFileTime / SetFileTime share the same shape (handle + 3 FILETIME ptrs).
typedef _FileTimeNative = Int32 Function(
  IntPtr hFile,
  Pointer<Uint8> lpCreationTime,
  Pointer<Uint8> lpLastAccessTime,
  Pointer<Uint8> lpLastWriteTime,
);
typedef _FileTimeDart = int Function(
  int hFile,
  Pointer<Uint8> lpCreationTime,
  Pointer<Uint8> lpLastAccessTime,
  Pointer<Uint8> lpLastWriteTime,
);

typedef _CloseHandleNative = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

class _Kernel32 {
  _Kernel32(DynamicLibrary lib)
      : createFile = lib.lookupFunction<_CreateFileWNative, _CreateFileWDart>(
          'CreateFileW',
        ),
        getFileTime = lib.lookupFunction<_FileTimeNative, _FileTimeDart>(
          'GetFileTime',
        ),
        setFileTime = lib.lookupFunction<_FileTimeNative, _FileTimeDart>(
          'SetFileTime',
        ),
        closeHandle = lib.lookupFunction<_CloseHandleNative, _CloseHandleDart>(
          'CloseHandle',
        );

  final _CreateFileWDart createFile;
  final _FileTimeDart getFileTime;
  final _FileTimeDart setFileTime;
  final _CloseHandleDart closeHandle;
}

// Lazily initialized so kernel32.dll is never loaded off-Windows.
_Kernel32? _kernel32;

_Kernel32? _tryLoadKernel32() {
  try {
    return _kernel32 ??= _Kernel32(DynamicLibrary.open('kernel32.dll'));
  } catch (_) {
    return null;
  }
}

/// Copies the NTFS creation time from [sourcePath] onto [targetPath].
///
/// Windows-only; a no-op on every other platform. Never throws — on any
/// failure (missing/locked file, permission error) it silently leaves the
/// target's timestamps unchanged, matching the previous PowerShell behavior.
/// Only the creation time is touched; the modified/access times set earlier by
/// `setLastModified` are preserved (nullptr is passed for those).
void copyWindowsCreationTime(String sourcePath, String targetPath) {
  if (!Platform.isWindows) return;
  final lib = _tryLoadKernel32();
  if (lib == null) return;

  final srcPtr = sourcePath.toNativeUtf16();
  final dstPtr = targetPath.toNativeUtf16();
  // FILETIME == two DWORDs == 8 bytes.
  final creationTime = malloc<Uint8>(8);
  var srcHandle = _invalidHandleValue;
  var dstHandle = _invalidHandleValue;
  try {
    srcHandle = lib.createFile(
      srcPtr,
      _genericRead,
      _fileShareAll,
      nullptr,
      _openExisting,
      _fileFlagBackupSemantics,
      0,
    );
    if (srcHandle == _invalidHandleValue) return;
    if (lib.getFileTime(srcHandle, creationTime, nullptr, nullptr) == 0) {
      return;
    }

    dstHandle = lib.createFile(
      dstPtr,
      _fileWriteAttributes,
      _fileShareAll,
      nullptr,
      _openExisting,
      _fileFlagBackupSemantics,
      0,
    );
    if (dstHandle == _invalidHandleValue) return;

    lib.setFileTime(dstHandle, creationTime, nullptr, nullptr);
  } catch (_) {
    // Swallow: preserving creation time is best-effort cosmetic metadata.
  } finally {
    if (srcHandle != _invalidHandleValue) lib.closeHandle(srcHandle);
    if (dstHandle != _invalidHandleValue) lib.closeHandle(dstHandle);
    malloc.free(creationTime);
    malloc.free(srcPtr);
    malloc.free(dstPtr);
  }
}

/// Reads [filePath]'s NTFS creation time as a raw 64-bit FILETIME value
/// (100-nanosecond ticks since 1601-01-01 UTC), or null on any failure or
/// non-Windows platform. Comparing two of these ints is a byte-for-byte
/// comparison of the underlying FILETIME — used to verify a copy was exact.
int? readWindowsCreationTimeRaw(String filePath) {
  if (!Platform.isWindows) return null;
  final lib = _tryLoadKernel32();
  if (lib == null) return null;

  final pathPtr = filePath.toNativeUtf16();
  final creationTime = malloc<Uint8>(8);
  var handle = _invalidHandleValue;
  try {
    handle = lib.createFile(
      pathPtr,
      _genericRead,
      _fileShareAll,
      nullptr,
      _openExisting,
      _fileFlagBackupSemantics,
      0,
    );
    if (handle == _invalidHandleValue) return null;
    if (lib.getFileTime(handle, creationTime, nullptr, nullptr) == 0) {
      return null;
    }
    final words = creationTime.cast<Uint32>();
    final low = words[0];
    final high = words[1];
    return (high << 32) | low;
  } catch (_) {
    return null;
  } finally {
    if (handle != _invalidHandleValue) lib.closeHandle(handle);
    malloc.free(creationTime);
    malloc.free(pathPtr);
  }
}

/// Sets [filePath]'s NTFS creation time to the raw 64-bit FILETIME [fileTime].
///
/// Returns true on success. Windows-only; a no-op returning false elsewhere.
/// Exists mainly so tests can stamp a known creation time before exercising
/// [copyWindowsCreationTime], making the before/after comparison deterministic.
bool setWindowsCreationTimeRaw(String filePath, int fileTime) {
  if (!Platform.isWindows) return false;
  final lib = _tryLoadKernel32();
  if (lib == null) return false;

  final pathPtr = filePath.toNativeUtf16();
  final buffer = malloc<Uint8>(8);
  var handle = _invalidHandleValue;
  try {
    final words = buffer.cast<Uint32>();
    words[0] = fileTime & 0xFFFFFFFF;
    words[1] = (fileTime >> 32) & 0xFFFFFFFF;

    handle = lib.createFile(
      pathPtr,
      _fileWriteAttributes,
      _fileShareAll,
      nullptr,
      _openExisting,
      _fileFlagBackupSemantics,
      0,
    );
    if (handle == _invalidHandleValue) return false;
    return lib.setFileTime(handle, buffer, nullptr, nullptr) != 0;
  } catch (_) {
    return false;
  } finally {
    if (handle != _invalidHandleValue) lib.closeHandle(handle);
    malloc.free(buffer);
    malloc.free(pathPtr);
  }
}
