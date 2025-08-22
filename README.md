# dyld-shared-cache-extractor

A CLI tool to extract dylib from dyld_shared_cache

 Re-implementation of the tool [dsc_extractor](https://github.com/apple-oss-distributions/dyld/blob/93bd81f9d7fcf004fcebcb66ec78983882b41e71/other-tools/dsc_extractor.cpp), which exists in [apple-oss-distributions/dyld](https://github.com/apple-oss-distributions/dyld), in Swift using [MachOKit](https://github.com/p-x9/MachOKit).

<!-- # Badges -->

[![Github issues](https://img.shields.io/github/issues/swiftbin/dyld-shared-cache-extractor)](https://github.com/swiftbin/dyld-shared-cache-extractor/issues)
[![Github forks](https://img.shields.io/github/forks/swiftbin/dyld-shared-cache-extractor)](https://github.com/swiftbin/dyld-shared-cache-extractor/network/members)
[![Github stars](https://img.shields.io/github/stars/swiftbin/dyld-shared-cache-extractor)](https://github.com/swiftbin/dyld-shared-cache-extractor/stargazers)
[![Github top language](https://img.shields.io/github/languages/top/swiftbin/dyld-shared-cache-extractor)](https://github.com/swiftbin/dyld-shared-cache-extractor/)

## Usage

```sh
OVERVIEW: Extract dylib from dyld shared cache

USAGE: dyld-shared-cache-extractor <input-path> [--output <output>] [--dylib <dylib>] [--all]

ARGUMENTS:
  <input-path>            Path to the input main dyld shared cache file.

OPTIONS:
  -o, --output <output>   Path to the output directory for exacted dyld file
                          (default: ./)
  -d, --dylib <dylib>     Name of dylib to be extracted.
  --all                   Extract all dylibs.
  --version               Show the version.
  -h, --help              Show help information.
```

## License

dyld-shared-cache-extractor is released under the MIT License. See [LICENSE](./LICENSE)
