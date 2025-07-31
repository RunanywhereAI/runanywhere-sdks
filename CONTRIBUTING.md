# Contributing to RunAnywhere SDKs

Thank you for your interest in contributing to RunAnywhere SDKs! We welcome contributions from the community and are grateful for your help in making our SDKs better.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Submitting Changes](#submitting-changes)
- [Code Style](#code-style)
- [Testing](#testing)
- [Reporting Issues](#reporting-issues)

## 🤝 Code of Conduct

By participating in this project, you are expected to uphold our code of conduct. Please be respectful and constructive in all interactions.

## 🚀 Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/your-username/runanywhere-sdks.git
   cd runanywhere-sdks
   ```
3. **Set up the development environment** (see [Development Setup](#development-setup))
4. **Create a new branch** for your feature or bug fix:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## 🛠️ Development Setup

### Prerequisites

**For Android Development:**
- Android Studio Arctic Fox or later
- JDK 11 or later
- Android SDK with API level 24+

**For iOS Development:**
- Xcode 15.0+
- Swift 5.9+
- macOS 10.15+

### Environment Setup

1. **Install pre-commit hooks** (recommended):
   ```bash
   pip install pre-commit
   pre-commit install
   ```

2. **Android SDK Setup:**
   ```bash
   cd sdk/runanywhere-android/
   ./gradlew build
   ```

3. **iOS SDK Setup:**
   ```bash
   cd sdk/runanywhere-swift/
   swift build
   ```

## 🔧 Making Changes

### Branch Naming Convention

- `feature/description` - for new features
- `bugfix/description` - for bug fixes
- `docs/description` - for documentation updates
- `refactor/description` - for code refactoring

### Commit Message Format

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Changes that do not affect the meaning of the code
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `test`: Adding missing tests or correcting existing tests
- `chore`: Changes to the build process or auxiliary tools

**Examples:**
```
feat(android): add cost tracking to generation results
fix(ios): resolve memory leak in model loading
docs: update README with new API examples
```

## 📤 Submitting Changes

1. **Ensure your code follows our style guidelines** (see [Code Style](#code-style))
2. **Add or update tests** for your changes
3. **Run the test suite** to ensure nothing is broken:
   ```bash
   # Android
   cd sdk/runanywhere-android/
   ./gradlew test lint

   # iOS
   cd sdk/runanywhere-swift/
   swift test
   swiftlint
   ```
4. **Commit your changes** with a clear commit message
5. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```
6. **Create a Pull Request** on GitHub with:
   - Clear title and description
   - Reference to any related issues
   - Screenshots or examples if applicable

### Pull Request Guidelines

- **Keep PRs focused** - one feature or bug fix per PR
- **Write clear descriptions** - explain what and why, not just how
- **Update documentation** if your changes affect the public API
- **Add tests** for new functionality
- **Ensure CI passes** - all checks must be green

## 🎨 Code Style

### Android (Kotlin)

- Follow [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html)
- Use 4 spaces for indentation
- Maximum line length: 120 characters
- Run `./gradlew ktlintFormat` to auto-format code

### iOS (Swift)

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use 4 spaces for indentation
- Maximum line length: 120 characters
- Run `swiftlint` to check style compliance

### General Guidelines

- **Use meaningful names** for variables, functions, and classes
- **Write self-documenting code** with clear intent
- **Add comments** for complex logic or business rules
- **Avoid deep nesting** - prefer early returns and guard clauses
- **Keep functions small** and focused on a single responsibility

## 🧪 Testing

### Writing Tests

- **Unit tests** for business logic and utilities
- **Integration tests** for API interactions
- **UI tests** for critical user flows (example apps)

### Running Tests

```bash
# Android SDK tests
cd sdk/runanywhere-android/
./gradlew test

# iOS SDK tests
cd sdk/runanywhere-swift/
swift test

# Android example app tests
cd examples/android/RunAnywhereAI/
./gradlew test

# iOS example app tests
cd examples/ios/RunAnywhereAI/
xcodebuild test -scheme RunAnywhereAI -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test Coverage

We aim for high test coverage, especially for:
- Core SDK functionality
- API interfaces
- Error handling
- Edge cases

## 🐛 Reporting Issues

### Before Reporting

1. **Search existing issues** to avoid duplicates
2. **Try the latest version** to see if the issue is already fixed
3. **Check the documentation** for known limitations

### Creating an Issue

Use our issue templates and provide:

**For Bug Reports:**
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, SDK version, etc.)
- Code samples or logs if applicable

**For Feature Requests:**
- Clear description of the desired functionality
- Use cases and examples
- Potential implementation approach (if you have ideas)

## 📚 Documentation

When contributing:

- **Update relevant README files** for API changes
- **Add inline documentation** for public methods
- **Include code examples** for new features
- **Update CHANGELOG.md** for significant changes

## 🎯 Areas for Contribution

We especially welcome contributions in these areas:

- **Performance optimizations**
- **Additional model format support**
- **Improved error handling**
- **Documentation and examples**
- **Test coverage improvements**
- **CI/CD enhancements**

## ❓ Questions?

- **General questions**: Open a GitHub Discussion
- **Bug reports**: Create an issue using the bug report template
- **Feature requests**: Create an issue using the feature request template
- **Security issues**: Email security@runanywhere.ai (do not create public issues)

## 🙏 Recognition

Contributors will be recognized in our:
- CONTRIBUTORS.md file
- Release notes for significant contributions
- Community spotlights

Thank you for contributing to RunAnywhere SDKs! 🚀
