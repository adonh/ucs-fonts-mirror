---
layout: default
title: UCS fonts mirror
---

# UCS fonts mirror

**Upstream source:** <https://www.cl.cam.ac.uk/~mgk25/ucs-fonts.html>

A preservation mirror of Markus Kuhn's Unicode bitmap fonts and tools for the
X Window System, together with the accompanying text examples.
Downloads are the original files, not converted or repackaged copies.

[Font downloads](#downloads) |
[Full file directory](directory.html) |
[Text examples](directory.html#text-examples)

## About

These packages extend classic X11 fonts to use ISO 10646-1 / Unicode character
encoding. They include the familiar Misc Fixed terminal fonts, supplementary
East Asian fonts, and recoded Adobe and Bigelow & Holmes bitmap fonts.
They are historical BDF font distributions, not modern TrueType or OpenType packages.

Coverage varies by font. A Unicode encoding does not imply coverage of every
Unicode character or support for the shaping required by every writing system.
Read the documentation inside the archives for font repertoires, installation
instructions, conversion tools, and compatibility notes.

## Downloads

- [Misc Fixed fonts](downloads/ucs-fonts.tar.gz): the main bitmap font collection,
  documentation, and tools.
- [CJK supplement](downloads/ucs-fonts-asian.tar.gz): additional Chinese,
  Japanese, and Korean fonts; use alongside the main package.
- [Adobe and B&H fonts](downloads/ucs-fonts-75dpi100dpi.tar.gz):
  Unicode versions of the X11 75/100 dpi bitmap fonts.
- [Original change log](downloads/ucs-fonts.changes).

The [full directory](directory.html) also lists any newly discovered downloads.

## Text examples

The [mirrored examples](directory.html#text-examples) include multilingual
demonstrations, character grids, IPA samples, and UTF-8 decoder test data.
They are preserved as raw files: whitespace matters, and `UTF-8-test.txt`
deliberately contains malformed byte sequences.
Your browser may replace invalid bytes when displaying that file;
download it to use the original test data.

See the [upstream directory](https://www.cl.cam.ac.uk/~mgk25/ucs/examples/)
and [rights information](attribution.html) for original credits and terms.

## Further reading

Markus Kuhn's original
[font page](https://www.cl.cam.ac.uk/~mgk25/ucs-fonts.html),
[Unicode FAQ](https://www.cl.cam.ac.uk/~mgk25/unicode.html), and
[quotation-mark explanation](https://www.cl.cam.ac.uk/~mgk25/ucs/quotes.html)
provide historical background. Those articles are linked rather than reproduced.

## Integrity and rights

[SHA-256 checksums](SHA256SUMS) and a [source inventory](SOURCES.tsv) accompany the files.
Upstream fonts and examples retain their original notices and terms;
the repository's MIT license covers only its original code and presentation.
Read [attribution and rights](attribution.html).
