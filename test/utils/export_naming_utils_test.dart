import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/export_naming_utils.dart';

void main() {
  group('ExportNamingUtils', () {
    group('sanitizeProjectName', () {
      test('returns Untitled for empty string', () {
        expect(ExportNamingUtils.sanitizeProjectName(''), 'Untitled');
      });

      test('returns Untitled for whitespace-only string', () {
        expect(ExportNamingUtils.sanitizeProjectName('   '), 'Untitled');
      });

      test('replaces filesystem-unsafe characters', () {
        expect(
            ExportNamingUtils.sanitizeProjectName('My/Project'), 'My_Project');
        expect(ExportNamingUtils.sanitizeProjectName('Test:Name'), 'Test_Name');
        expect(ExportNamingUtils.sanitizeProjectName('File*Name'), 'File_Name');
        expect(
            ExportNamingUtils.sanitizeProjectName('Test?Query'), 'Test_Query');
        expect(
            ExportNamingUtils.sanitizeProjectName('Path\\Name'), 'Path_Name');
        expect(
            ExportNamingUtils.sanitizeProjectName('Quote"Name'), 'Quote_Name');
        expect(
            ExportNamingUtils.sanitizeProjectName('Less<More>'), 'Less_More');
        expect(ExportNamingUtils.sanitizeProjectName('Pipe|Name'), 'Pipe_Name');
      });

      test('replaces special characters with underscore', () {
        expect(
          ExportNamingUtils.sanitizeProjectName("John's Birthday"),
          'John_s_Birthday',
        );
        expect(
            ExportNamingUtils.sanitizeProjectName('Test@Email'), 'Test_Email');
        expect(ExportNamingUtils.sanitizeProjectName('Hash#Tag'), 'Hash_Tag');
        expect(
          ExportNamingUtils.sanitizeProjectName('Dollar\$Sign'),
          'Dollar_Sign',
        );
      });

      test('collapses multiple spaces and underscores', () {
        expect(
          ExportNamingUtils.sanitizeProjectName('My   Project'),
          'My_Project',
        );
        expect(
          ExportNamingUtils.sanitizeProjectName('My___Project'),
          'My_Project',
        );
        expect(
          ExportNamingUtils.sanitizeProjectName('My _ _ Project'),
          'My_Project',
        );
      });

      test('trims leading and trailing underscores', () {
        expect(ExportNamingUtils.sanitizeProjectName('_Project_'), 'Project');
        expect(ExportNamingUtils.sanitizeProjectName('___Test___'), 'Test');
      });

      test('preserves hyphens', () {
        expect(
          ExportNamingUtils.sanitizeProjectName('My-Project'),
          'My-Project',
        );
        expect(
          ExportNamingUtils.sanitizeProjectName('Test-Name-Here'),
          'Test-Name-Here',
        );
      });

      test('truncates long names to 50 characters', () {
        final longName = 'A' * 100;
        final result = ExportNamingUtils.sanitizeProjectName(longName);
        expect(result.length, lessThanOrEqualTo(50));
      });

      test('removes trailing underscore after truncation', () {
        final longNameWithUnderscore = '${'A' * 49}_B';
        final result =
            ExportNamingUtils.sanitizeProjectName(longNameWithUnderscore);
        expect(result.endsWith('_'), isFalse);
      });

      test('preserves numbers', () {
        expect(
          ExportNamingUtils.sanitizeProjectName('Project123'),
          'Project123',
        );
        expect(
          ExportNamingUtils.sanitizeProjectName('2024Project'),
          '2024Project',
        );
      });

      test('handles project name with only special characters', () {
        expect(
          ExportNamingUtils.sanitizeProjectName('!@#\$%^&*()'),
          'Untitled',
        );
      });

      test('handles project name with mixed valid/invalid chars', () {
        expect(
          ExportNamingUtils.sanitizeProjectName('My <Cool> Project!'),
          'My_Cool_Project',
        );
      });
    });

    group('formatTimestamp', () {
      test('formats timestamp correctly', () {
        final dt = DateTime(2026, 1, 24, 14, 30, 52);
        expect(ExportNamingUtils.formatTimestamp(dt), '2026-01-24_143052');
      });

      test('pads single-digit values with zeros', () {
        final dt = DateTime(2026, 1, 5, 9, 5, 3);
        expect(ExportNamingUtils.formatTimestamp(dt), '2026-01-05_090503');
      });

      test('handles midnight correctly', () {
        final dt = DateTime(2026, 12, 31, 0, 0, 0);
        expect(ExportNamingUtils.formatTimestamp(dt), '2026-12-31_000000');
      });

      test('handles end of day correctly', () {
        final dt = DateTime(2026, 12, 31, 23, 59, 59);
        expect(ExportNamingUtils.formatTimestamp(dt), '2026-12-31_235959');
      });
    });

    group('generateExportFilename', () {
      test('generates correct format with project name', () {
        final dt = DateTime(2026, 1, 24, 14, 30, 52);
        final result = ExportNamingUtils.generateExportFilename(
          projectName: 'My Project',
          extension: 'mp4',
          timestamp: dt,
        );
        expect(result, 'My_Project_AgeLapse_2026-01-24_143052.mp4');
      });

      test('handles empty project name', () {
        final dt = DateTime(2026, 1, 24, 14, 30, 52);
        final result = ExportNamingUtils.generateExportFilename(
          projectName: '',
          extension: 'zip',
          timestamp: dt,
        );
        expect(result, 'Untitled_AgeLapse_2026-01-24_143052.zip');
      });

      test('handles extension with dot', () {
        final dt = DateTime(2026, 1, 24, 14, 30, 52);
        final result = ExportNamingUtils.generateExportFilename(
          projectName: 'Test',
          extension: '.mp4',
          timestamp: dt,
        );
        expect(result, 'Test_AgeLapse_2026-01-24_143052.mp4');
      });

      test('uses current time when timestamp not provided', () {
        final now = DateTime.now();
        final result = ExportNamingUtils.generateExportFilename(
          projectName: 'Test',
          extension: 'mp4',
        );

        expect(result, contains('AgeLapse'));
        expect(result, endsWith('.mp4'));
        // Verify timestamp contains current year
        expect(result, contains(now.year.toString()));
      });
    });

    group('generateVideoFilename', () {
      test('generates mp4 filename', () {
        final dt = DateTime(2026, 1, 24, 14, 30, 52);
        final result = ExportNamingUtils.generateVideoFilename(
          projectName: 'Wedding',
          timestamp: dt,
        );
        expect(result, 'Wedding_AgeLapse_2026-01-24_143052.mp4');
      });
    });

    group('generateZipFilename', () {
      test('generates zip filename', () {
        final dt = DateTime(2026, 1, 24, 14, 30, 52);
        final result = ExportNamingUtils.generateZipFilename(
          projectName: 'Backup',
          timestamp: dt,
        );
        expect(result, 'Backup_AgeLapse_2026-01-24_143052.zip');
      });
    });

    group('edge cases', () {
      test('handles very long project names', () {
        final dt = DateTime(2026, 1, 24, 14, 30, 52);
        final longProjectName = 'A' * 200;
        final result = ExportNamingUtils.generateExportFilename(
          projectName: longProjectName,
          extension: 'mp4',
          timestamp: dt,
        );

        // Verify total length is reasonable
        expect(result.length, lessThan(100));
        expect(result, endsWith('.mp4'));
        expect(result, contains('AgeLapse'));
      });

      test('handles project name with all types of special characters', () {
        final dt = DateTime(2026, 1, 24, 14, 30, 52);
        final result = ExportNamingUtils.generateExportFilename(
          projectName: 'Test/\\:*?"<>|@#\$%Project',
          extension: 'mp4',
          timestamp: dt,
        );
        expect(result, 'Test_Project_AgeLapse_2026-01-24_143052.mp4');
      });
    });
  });
}
