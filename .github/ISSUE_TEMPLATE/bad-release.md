---
name: Bad release
about: Internal — a customer or CI reports a broken wheel
title: "[bad-release] v<version> on <platform>"
labels: ["bad-release"]
---

## Version

<!-- e.g. v0.5.1 -->

## Platform

<!-- macOS arm64 / macOS x86_64 / Linux x86_64 / Linux aarch64 -->

## Symptom

<!-- What did the customer / CI see? Paste the error verbatim. -->

## Reproduction

<!-- Steps to reproduce locally if known -->

## Checksum check

```
$ shasum -a 256 ~/Downloads/catchai-*.whl
<paste output>

$ cat catchai-dist/checksums/v<version>.txt
<paste relevant line>
```

- [ ] Checksums match → build issue, rebuild needed
- [ ] Checksums don't match → transit / tamper, ask customer to re-download
- [ ] Couldn't verify → fill in below

## Resolution

<!-- For triage notes -->
