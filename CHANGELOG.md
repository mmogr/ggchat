# Changelog

## [0.1.1](https://github.com/mmogr/ggchat/compare/v0.1.0...v0.1.1) (2026-09-07)


### What the app now does

* **core:** a pairing string comes apart into a ticket and a code ([a0bde74](https://github.com/mmogr/ggchat/commit/a0bde748cdbf1aa9843b523fb41d06bcf0349f5d))
* **core:** a six-digit code is redeemed through the pipe for the machine's key ([369e3fd](https://github.com/mmogr/ggchat/commit/369e3fd00317c1f6047ba47ecb6add73405def65))
* **pairing:** a code is redeemed, not a key carried ([a199ca3](https://github.com/mmogr/ggchat/commit/a199ca3635031dcbca38842da077c046637eb39b))
* **ui:** a provider's credentials are edited in place instead of deleted and re-added ([5e5d883](https://github.com/mmogr/ggchat/commit/5e5d883a7ef73fd54619d60535d64abb50ecb370))
* **ui:** the provider form pairs with a code instead of asking for a key ([f9cfc67](https://github.com/mmogr/ggchat/commit/f9cfc67fb93b552c71c80dd7a01ba0d8718a5b29))


### What the app stopped getting wrong

* **app:** a background that cuts a reply short is counted as a mid-reply close ([b39eb59](https://github.com/mmogr/ggchat/commit/b39eb597d0c201f5e07d4286777a9a0f90481485))
* **app:** a dial that lands late hangs itself up instead of installing a pipe nobody holds ([ebf37a0](https://github.com/mmogr/ggchat/commit/ebf37a0d67999d7535948233dbd4dbd355779061))
* **app:** a provider that has left the list is not dialled ([48fe99e](https://github.com/mmogr/ggchat/commit/48fe99e6a5553298c56addc2dadd88efc496ce5b))
* **app:** a removal deletes the durable record before the credentials ([809c170](https://github.com/mmogr/ggchat/commit/809c17017deb27780be4ed7955f6ee21aaacafef))
* **app:** every close the app shows is a close it counts ([6d21586](https://github.com/mmogr/ggchat/commit/6d215860dd8aae6a72d012be00e2df8706b6d048))
* **app:** the app hangs up when it goes away and dials again when it comes back ([0915cc0](https://github.com/mmogr/ggchat/commit/0915cc01add409e6329de90b22be02e42dbc97ef))
* **app:** the app notices when it goes away ([86aa924](https://github.com/mmogr/ggchat/commit/86aa9245f073d5fee25312dc193d15a1aee5c7ab))
* **app:** the sandboxed macOS build may receive the datagrams a pipe depends on ([c6adeec](https://github.com/mmogr/ggchat/commit/c6adeec2bacadeb60039e3314c00258bce7fdf1a))
* **ci:** the badges survive a coverage run that reports no percentage ([#23](https://github.com/mmogr/ggchat/issues/23)) ([979a076](https://github.com/mmogr/ggchat/commit/979a076555574a6e9acc881c1b53d3a0c7261a58))
* **ci:** the marker parser reads a class wherever it is indented ([c3e0c2a](https://github.com/mmogr/ggchat/commit/c3e0c2a49cc03f787f5148952fed8bf33acf3009))
* **ci:** the transparency reading is taken once, not twice ([b369edb](https://github.com/mmogr/ggchat/commit/b369edb7b4f37fade0ba250a6ce885ff02fedefd))
* **core:** the mock pipe is not compiled into a shipped build ([667813d](https://github.com/mmogr/ggchat/commit/667813d21d492ad095995bff88aa3038a0d655c6))
* **core:** tickets and errors say true things ([#27](https://github.com/mmogr/ggchat/issues/27)) ([2d42c41](https://github.com/mmogr/ggchat/commit/2d42c41134c1709f22f0834607a751c1d19bfd2b))
* **ui:** an edit to a provider that has gone says so instead of saving nothing ([401174a](https://github.com/mmogr/ggchat/commit/401174a667b36666ab2e5005a3f1482da2d0891d))
* **ui:** the shipped app stops pretending to have a pipe ([b348515](https://github.com/mmogr/ggchat/commit/b348515d43adf5cf9260cb8e6196d7e68a4faa1c))
* **ui:** the status pill is a way back in every state but a dial in flight ([7c352d9](https://github.com/mmogr/ggchat/commit/7c352d9f58224ab499eb034cadd1ca617fa1cc7b))


### How it looks

* **core:** PipePairing imports nothing it does not use ([0c0c3f2](https://github.com/mmogr/ggchat/commit/0c0c3f2e298c92bcb93ab4bc0e9764a3d34d80d1))


### Documentation

* **adr,seam:** the amendments stop describing code that has since changed ([b1cb2cf](https://github.com/mmogr/ggchat/commit/b1cb2cfc1fac8c6bff88e93f16b1853f29de8d51))
* **adr:** ADR 0003 says what having no access group actually costs ([5814f5f](https://github.com/mmogr/ggchat/commit/5814f5f59d02077e35ad88462c81061984d0098c))
* **adr:** the kill criteria name readings that exist, and say what the code does instead ([a163731](https://github.com/mmogr/ggchat/commit/a16373102914e289e5440f742ae4863e9b8a3d16))
* **app:** the reason for hanging up on the way out cites only what can be sourced ([43fd5db](https://github.com/mmogr/ggchat/commit/43fd5db3969279da12b7e4f06404c5ecf86ebfcb))
* **readme,seam:** the README says a code is redeemed, not a key carried ([293cd30](https://github.com/mmogr/ggchat/commit/293cd30bc822dcf3d99b4d7660c945ac840f11a3))
* **readme:** the mid-reply line stops citing a criterion that was struck ([30d2fe4](https://github.com/mmogr/ggchat/commit/30d2fe46829d9ad747fac7bd64b76ece8a6de00a))
* **readme:** the README stops citing the struck reading as ADR 0001's ([a76cf2a](https://github.com/mmogr/ggchat/commit/a76cf2a11e4da16d0fbe436a63c5fcaf0da85f67))
* **readme:** the Status paragraph names both pipe implementations ([a4a6529](https://github.com/mmogr/ggchat/commit/a4a6529ca232d894e9f1b4bc5cc314ca6dd810fc))
* **seam:** the ffi seam stops pointing an implementer at a struck reading ([4d1d2a9](https://github.com/mmogr/ggchat/commit/4d1d2a971783017e39b99446a3c2b7a0ef936d90))
* **ui:** the Settings footer stops citing a criterion that was struck ([db16d35](https://github.com/mmogr/ggchat/commit/db16d3572d80599679144974accc50733e5cd4fa))

## 0.1.0 (2026-09-06)


### What the app now does

* **app:** the app shell opens with a sidebar and a providers sheet ([35a3982](https://github.com/mmogr/ggchat/commit/35a39825eee0c283d1de0c181d5a6eef78a17343))
* **app:** the app shell opens with a sidebar and a providers sheet ([577f487](https://github.com/mmogr/ggchat/commit/577f4873176b07677bfc36ac7c015a0076203b17))
* **chat:** the transcript streams from the mock with the composer and two pills ([2d17dca](https://github.com/mmogr/ggchat/commit/2d17dcae66df47461beac2208e9696179aee3463))
* **core:** the package builds and tests from the command line ([f392c71](https://github.com/mmogr/ggchat/commit/f392c715a811fd8fbe88780bdece805aac4dbf16))
* **core:** the package builds and tests from the command line ([25bfac7](https://github.com/mmogr/ggchat/commit/25bfac77c400d1295f0e61a6fb79902cae84de55))
* **pipe:** a ticket and token connect to the mock and the status pill walks ([4a41628](https://github.com/mmogr/ggchat/commit/4a41628f61271bbaeee5e139636a0615cba99b53))
* **provider:** a server added by URL lists models and streams ([85daa2a](https://github.com/mmogr/ggchat/commit/85daa2ac895b97d33f37112beab85695934c59e8))


### What the app stopped getting wrong

* **pipe:** a removed provider's session is shut down before it is forgotten ([272f303](https://github.com/mmogr/ggchat/commit/272f3039c15f07a8eb82b3b521fd7e13fd82bfe9))
* **release:** the first release is 0.1.0, as the README says ([e2f1552](https://github.com/mmogr/ggchat/commit/e2f155221b0414bfe7d281dbf4ceaba47fddfb12))
* **release:** the first release is 0.1.0, as the README says ([d77ca39](https://github.com/mmogr/ggchat/commit/d77ca3981b9c0a0cf23e48b57b216282e698c47d))
* **ui-tests:** going back for Settings is confirmed, like every other tap ([ddd136a](https://github.com/mmogr/ggchat/commit/ddd136a9f6ab0438d17ab5dead3663b530aa54aa))
* **ui-tests:** going back for Settings is confirmed, like every other tap ([06d1c4b](https://github.com/mmogr/ggchat/commit/06d1c4b85623de1a6df239944aab9943841bbdaf))
* **ui-tests:** the pipe tests survive a device that has never seen the app ([94c7b74](https://github.com/mmogr/ggchat/commit/94c7b74808be4da7b5f666ec636e5e7d21c5af04))
* **ui-tests:** the pipe tests survive a device that has never seen the app ([43b79d5](https://github.com/mmogr/ggchat/commit/43b79d5470c556f72eb054187514a084e8d96208))
* **ui:** a pipe provider can be added, and a credential that fails says so ([0de27c5](https://github.com/mmogr/ggchat/commit/0de27c580a0b4d4504b7d1d8ef2438f50f3f185b))
* **ui:** the app was run, and the seven things it got wrong are fixed ([faa9d69](https://github.com/mmogr/ggchat/commit/faa9d694c7d2ebfbeef403b9024752cfca1a8390))
* **ui:** the app was run, and the seven things it got wrong are fixed ([8b9f9e5](https://github.com/mmogr/ggchat/commit/8b9f9e5e485d190e4c67062bb790471904f63071))


### How it looks

* **ui:** the glass is the system's and the transcript reads at every type size ([9288c63](https://github.com/mmogr/ggchat/commit/9288c63099cb51e4092e25dee09dbfa5785ecb41))


### Documentation

* **adr:** the ffi seam is written down and the app stops here ([8d5a817](https://github.com/mmogr/ggchat/commit/8d5a817e48311b07c9667c1c143a8e30f628091d))
