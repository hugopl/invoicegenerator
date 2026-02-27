# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.1] - 2026-02-27
### Changed
 - Added few defaults for missing YAML fields.

## [2.0.0] - 2026-02-26
### Changed
 - Rewritten in Crystal. Ruby is no longer required.
 - PDF generation now uses libharu directly instead of PDFKit/wkhtmltopdf. No dependency on X11 or WebKit.
 - Invoice layout is coded directly in Crystal. Custom HTML templates are no longer supported.
 - Money values are formatted in US number format (e.g. 1,000.00).
 - Distributed as a static binary with no runtime dependencies.

### Added
 - `output` YAML field to set the PDF output filename.
 - `--color-accent=#RRGGBB` flag to customise the invoice accent colour.
 - Variable substitution in any YAML field: `$month`, `$past_month`, `$year`.
 - DejaVu Sans font embedded in the binary for broad Unicode support (Latin, Greek, Cyrillic, etc.).

## [1.0.2] - 2020-10-01
### Changed
 - Minimum required ruby version set to 2.5.5.
### Fixed
 - Correct render non-ascii characters on ruby versions > 2.1.
 - Update PKDKit dependency to fix several errors on ruby 2.5.x and 2.7.x.

## [1.0.1] - 2020-01-14
### Fixed
 - Fixed warnings from money gem.
 - Update PKDKit dependency.

## [1.0.0] - 2019-01-24
 - First release.
