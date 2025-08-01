# Security Policy

## Reporting Security Vulnerabilities

We take security seriously at RunAnywhere. If you discover a security vulnerability in our SDKs or related components, please report it responsibly.

### 🚨 Please DO NOT create public GitHub issues for security vulnerabilities

Instead, please email us directly at: **security@runanywhere.ai**

### What to Include

When reporting a security vulnerability, please include:

- **Description** of the vulnerability
- **Steps to reproduce** the issue
- **Potential impact** of the vulnerability
- **Affected versions** (if known)
- **Your contact information** for follow-up

### What to Expect

- **Acknowledgment** within 48 hours of your report
- **Initial assessment** within 5 business days
- **Regular updates** on our progress
- **Credit** in our security advisories (if desired)

## Security Best Practices

When using RunAnywhere SDKs in your applications:

### API Keys
- **Never hardcode** API keys in your source code
- **Use secure storage** mechanisms (Android Keystore, iOS Keychain)
- **Rotate keys** regularly
- **Restrict key permissions** to minimum required scope

### Data Handling
- **Validate input** before processing
- **Sanitize outputs** to prevent injection attacks
- **Use HTTPS** for all network communications
- **Implement proper error handling** without exposing sensitive information

### On-Device Models
- **Verify model integrity** before loading
- **Use secure model storage** to prevent tampering
- **Monitor resource usage** to prevent DoS attacks
- **Implement proper cleanup** of sensitive data in memory

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | ✅ Yes             |
| < 1.0   | ❌ No              |

## Security Features

Our SDKs include several built-in security features:

- **Encrypted communications** with RunAnywhere cloud services
- **Certificate pinning** for API endpoints
- **Secure credential storage** recommendations
- **Input validation** and sanitization
- **Privacy-preserving** on-device processing options

## Responsible Disclosure

We follow responsible disclosure practices:

1. **Investigation** - We investigate all reports thoroughly
2. **Coordination** - We work with reporters to understand and fix issues
3. **Timeline** - We aim to resolve critical issues within 90 days
4. **Disclosure** - We coordinate public disclosure after fixes are available
5. **Recognition** - We acknowledge security researchers (with permission)

Thank you for helping keep RunAnywhere and our users secure! 🔒
