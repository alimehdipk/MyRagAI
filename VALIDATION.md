# Validation

## Build 0.1.4

- Release app build completed with Swift 6.1.2 on macOS 15.8.2 (x86_64).
- App bundle metadata and ad-hoc code signature validated.
- ICNS icon decoded successfully using macOS iconutil; standard and Retina sizes are included.
- New app artwork visually confirmed in the running application.
- Light and dark appearance, cited-answer view, source excerpt panel, knowledge library, and connections screen visually inspected.
- Add knowledge popover verified to expose document and folder import actions.
- Four screenshots captured from the running app using a separate in-memory documentation workspace.

## Core checks

The 10 core checks previously passed with zero failures. Subsequent changes were limited to presentation, app resources, documentation, and the isolated screenshot preview; core retrieval and provider code is unchanged.

Run `./scripts/test.sh` to check Unicode chunking, bounded excerpts, source filtering, prompt citations, endpoint validation, provider request/response formats, persistence, corrupt-file handling, folder rescanning, and PDF page extraction.

## Limits of verification

The screenshot conversation is prewritten sample content, not a live model response. Live provider generation, provider model discovery, and Keychain behavior need verification with a real local server or provider account. The app is ad-hoc signed, not notarized for distribution.
