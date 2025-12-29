---
description: FAANG-style version control and release management standards
---

# Version Control & Release Standards

## Semantic Versioning (SemVer)
Use `MAJOR.MINOR.PATCH` format:
- **MAJOR** (1.x.x → 2.0.0): Breaking changes
- **MINOR** (1.0.x → 1.1.0): New features (backward compatible)
- **PATCH** (1.1.0 → 1.1.1): Bug fixes only

## Commit Message Format (Conventional Commits)
```
<type>(<scope>): <description>

[optional body]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructuring
- `test`: Tests
- `ci`: CI/CD changes
- `chore`: Maintenance

Examples:
- `feat(v1.2.0): Add reset countdown timers`
- `fix: Resolve cookie parsing issue`
- `docs: Update README with new features`

## CHANGELOG Format
Follow [Keep a Changelog](https://keepachangelog.com/):

```markdown
## [1.2.0] - 2024-12-29

### Added
- New feature description

### Changed
- Modified behavior

### Fixed
- Bug fix description

### Security
- Security improvement
```

## GitHub Release Notes
Each release must include:
1. **What's New** section with feature highlights
2. **Improvements** section
3. **Provider Status** table (for UsageBar)
4. **Download** instructions
5. Link to full CHANGELOG

## Release Checklist
// turbo-all
1. Bump version in `package.json`
2. Update `CHANGELOG.md` with new entry
3. Update `README.md` download link
4. Run `npm run build`
5. Copy dist to win-unpacked: `robocopy dist "release\win-unpacked\resources\app\dist" /E /IS /IT`
6. Create ZIP: `Compress-Archive -Path "release\win-unpacked\*" -DestinationPath "release\UsageBar-v<VERSION>-Portable.zip" -Force`
7. Git commit: `git add -A; git commit -m "feat(v<VERSION>): <description>"`
8. Git push: `git push origin main`
9. Create release: `gh release create v<VERSION> "release\UsageBar-v<VERSION>-Portable.zip" --title "UsageBar v<VERSION>" --notes "<release notes>"`
