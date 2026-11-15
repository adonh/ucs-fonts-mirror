---
layout: default
title: File directory
---

# File directory

Every mirrored download and example is listed here by filename.
This listing updates automatically when files are added or removed upstream.

[Back to the overview](./) | [Checksums](SHA256SUMS) | [Source URLs](SOURCES.tsv)

## Font downloads

{% assign downloads = site.static_files | where_exp: "file", "file.path contains '/downloads/'" | sort: "path" %}
{% for file in downloads %}
- [{{ file.path | remove_first: "/downloads/" }}]({{ file.path | relative_url }})
{% endfor %}

## Text examples

These are raw files, including intentional invalid UTF-8 and significant whitespace.

{% assign examples = site.static_files | where_exp: "file", "file.path contains '/examples/'" | sort: "path" %}
{% for file in examples %}
- [{{ file.path | remove_first: "/examples/" }}]({{ file.path | relative_url }})
{% endfor %}

See [rights information](attribution.html) for original credits and terms.
