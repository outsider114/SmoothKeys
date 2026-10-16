# Third-Party Notices

Copyright (c) 2026 SmoothKeys contributors.
SmoothKeys contributions are licensed under [CC BY-NC 4.0](LICENSE).

## Mos

- Project: [Caldis/Mos](https://github.com/Caldis/Mos).
- Copyright (c) 2017-2026 Caldis. All rights reserved. Credit to Caldis and the Mos contributors.
- Reference commit: [`5dfb2363331cf63f529fdafa27962c41f91feff4`](https://github.com/Caldis/Mos/tree/5dfb2363331cf63f529fdafa27962c41f91feff4).
- License: [Creative Commons Attribution-NonCommercial 4.0 International](https://creativecommons.org/licenses/by-nc/4.0/).
- Original license notice: [Resources/Mos-LICENSE.txt](Resources/Mos-LICENSE.txt).
- Full legal terms and warranty disclaimer: [LICENSE](LICENSE), including Section 5.

The scroll-handling portions of `MouseController.swift` and
`MosScrollEngine.swift` are adapted from Mos:
`ScrollCore`, `ScrollEvent`, `ScrollPoster`, `ScrollDispatchContext`,
`ScrollFilter`, `Interpolator`, `ScrollUtils`, and `Interceptor`
at the reference commit.

SmoothKeys adapts these implementations to its settings, removes per-application
profiles and hotkeys, simplifies scroll phases and filtering, retains
original-target PID dispatch, and adds startup fallback, diagnostics and Mos
conflict detection.

The original authors retain their rights. Redistribution must retain the
applicable attribution, source and license links, warranty disclaimer, and
modification notices. Mos does not endorse SmoothKeys.

Respecting the Mos README's distribution request, SmoothKeys is not distributed
through the Mac App Store.
