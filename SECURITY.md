# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |

_Legend_:
  - ✅ Currently supported, receives all security and other updates
  - 🔙 Legacy support, receives backported security updates only
  - ❌ Unsupported

## Reporting a Vulnerability

Please report known and suspected vulnerabilities privately and responsibly disclosed by [filling out a vulnerability report](https://github.com/lovetodream/oracle-nio/security/advisories/new) on Github[^1]. Vulnerabilities may also be privately and responsibly disclosed by emailing all pertinent information to [security@timozacherl.com](mailto:security@timozacherl.com).

[^1]: See [Github's official documentation of the vulnerability report feature](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) for additional privacy and safety details.

**⚠️ Please do _not_ file a public issue! ⚠️**

### When to report a vulnerability

* You think you have discovered a potential security vulnerability in Oracle NIO.
* You are unsure how a vulnerability affects Oracle NIO.

### What happens next?

* I will acknowledge receipt of the report within 3 working days. This may include a request for additional information about reproducing the vulnerability.
* I will privately inform the Swift Server Work Group ([SSWG](https://github.com/swift-server/sswg)) of the vulnerability within 10 days of the report as per their [security guidelines](https://www.swift.org/sswg/security/).
* Once I have identified a fix I may ask you to validate it. I aim to do this within 30 days. In some cases this may not be possible, for example when the vulnerability exists at the protocol level and the industry must coordinate on the disclosure process.
* If a CVE number is required, one will be requested through the [GitHub security advisory process](https://docs.github.com/en/code-security/security-advisories), providing you with full credit for the discovery.
* I will decide on a planned release date and let you know when it is.
* Prior to release, I will inform major dependents that a security-related patch is impending.
* Once the fix has been released I will publish a security advisory on GitHub and in the Server → Security Updates category on the [Swift forums](https://forums.swift.org/c/server/security-updates/).
