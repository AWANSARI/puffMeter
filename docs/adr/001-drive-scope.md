# ADR 001: Google Drive access uses the `drive.file` scope

**Status:** Accepted · 2026-10-08

## Context
PuffyMeter saves one JPEG and one JSON file per daily scan to a Google Drive folder the user chooses.
The design promises "One folder. Nothing else." Google classifies `drive` and `drive.readonly` as
*restricted* scopes (annual third-party security assessment) and `drive.metadata.readonly` as *sensitive*
(verification required). `drive.file` is *non-sensitive*: an app can only see files and folders it created
or that the user explicitly opened with it (for example through the Google Picker).

## Decision
Request only `openid email profile https://www.googleapis.com/auth/drive.file`, incrementally on the
"Connect Google Drive" screen.

- The primary path creates a new folder ("PuffyMeter Daily") at the My Drive root.
- The in-app folder list shows folders PuffyMeter can see (ones it created or was granted).
- Choosing an arbitrary existing folder is done with the Google Picker (web, `setSelectFolderEnabled(true)`),
  which grants `drive.file` access to that folder so the app can write into it. (Picker hosting is a
  follow-up task; the protocol `DriveService.listFolders` keeps this swappable.)
- Every file carries `appProperties.puffymeter = "1"` so "Restore history from Drive" can find it.

## Consequences
- No restricted-scope security assessment; the privacy promise is literally true.
- The folder picker cannot list the user's existing folders without the Picker. If that becomes a
  requirement, a `drive.metadata.readonly` implementation of `DriveService` can be swapped in (needs
  Google verification and a privacy review).
