# InterSystems Package Manager installer

`zpm-0.10.10.xml` is the installer of IPM 0.10.10, the release asset of the same name from
https://github.com/intersystems/ipm/releases/tag/v0.10.10 (published 14 October 2026), unchanged.

SHA-256: `daa2adabd66b488f57187d29712e54b0c25bbe000794fbf2a35a882c458b788a`

`iris.script` loads it during the image build when the base image has no IPM, after checking that SHA-256; a file with
any other digest stops the build. Only when this file is missing does the build download the same asset from GitHub,
under the same check, so the build never depends on the package registry being up.

To move to another release: download its `zpm-<version>.xml` asset, replace this file, and change the file name, the
version and the SHA-256 in `iris.script` and here.
