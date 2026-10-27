# PI Revision Tracker – change log

Every update and fix is recorded here, newest first. Each numbered version is a rollback point with its own backup folder next to this file.

- **Live app:** https://play.managedapps.cloud.microsoft/apps/b93394f3-be08-447e-bf98-7deb2a754fc3
- **Data:** SharePoint site https://miamiedu.sharepoint.com/sites/pi-revision-tracker-040dea
- **Internal summary (Belinda Quinta, view only):** https://miamiedu.sharepoint.com/sites/ehr-workload-supervisor-summary-lomas-persa-6cfd61
- **Public workload page (UM staff, view only):** https://miamiedu.sharepoint.com/sites/ehr-workload-lomas-persad-e9afaa
- **To roll back:** ask Copilot to "republish PI Revision Tracker version X". This changes the app only; the data stays as it is.

---

## Version 2.5 (October 26, 2026) – current rollback point
App version: ed2e55af4ddd8820b40b25959ba32046222db204 · Backup: "v2.5 2026-10-26"

**Fixed**
- **Changes longer than 255 characters didn't save.** In "Log PI email", any requested change longer than 255 characters was rejected, and the form closed anyway, so the unsaved changes were lost. Round v1 on #19 (Yannuzzi lattice degeneration) saved only its first 3 changes because of this.
- **Wrong "Last updated" time on the Sharing page.** It showed UTC as local time, 4 hours late.

**Changed**
- **Full wording is stored for each change,** with no length limit. The short label shown in lists is cut to 255 characters.
- **A preview before saving** ("Will be saved as N changes") shows exactly how the pasted text will be split. It handles bullets, numbering, and lines that wrap when pasted from Outlook.
- **Automatic retries:** each round and change is retried up to 3 times. Every record carries a unique key, so a retry can never create a duplicate.
- **Partial saves stay visible:** if anything still fails, the Log PI email window stays open and shows what saved and what didn't, with **Retry unsaved changes** and **Copy unsaved changes** buttons. It can't be closed while a save is still running.
- **"Add a change" on an existing round** uses the same safe saving.
- **Single-line fields stop at 255 characters** as you type (email subject, time-entry note, delivery note), instead of failing when saved.

**Data structure**
- **Change items:** new Details (full wording) and EntryKey fields.
- **Revision rounds:** new EntryKey field.

**Checks**
- Code checks and the production build passed.
- Six paste formats split correctly.
- A SharePoint test confirmed the cause and the fix: a 615-character change was rejected the old way and saved in full the new way. The test rows were deleted.
- Dashboards:
  - No dashboard code changed apart from the Sharing page time fix.
  - All 88 rows on the two shared pages matched a fresh recalculation from the tracker.
  - All 8 page layouts are intact.

**Follow-up for Lomas:** re-add the missing changes on round v1 of #19 using "Add a change".

---

## Dashboards (October 22–23, 2026) – not a numbered checkpoint
App version: 749ce2d8dfcecc7a4e3223deecf0b9087c7d43c9, published October 23

**Added**
- **Two SharePoint sites:**
  - An internal summary, view only for Belinda Quinta.
  - A public workload page, view only for UM staff, with no titles, investigators or hours.
- **App: Sharing page.** It shows previews of both pages and lets you:
  - edit the message on each page
  - turn the combined monthly hours on or off on the internal summary
  - set where each project appears: both pages, the supervisor page only, or hidden
- **App: automatic updates.** Both pages update when the app opens and shortly after any project or time change.
- **App: Completed date.** It's set automatically when a project is marked Completed, cleared if the project is reopened, and editable in Research setup.
- **Pages (SharePoint only, October 23):**
  - A portfolio status bar and cards per database.
  - Current projects with title and PI on the internal page, and by number only on the public page.
  - Live "days waiting" counts.
  - Definitions, callout-style notices, a trimmed side menu, and comments turned off.

---

## Version 2 (October 19, 2026)
App version: a22630459a3276281ea89a004689df720e0376ab · Backup: "v2 2026-10-19"

- **Dashboard home page** with a Download report button that produces an Excel workbook.
- **New project fields:**
  - Project # in its own field.
  - Intake date, Start date, Requested by, Intake source and Research output.
  - Wait to start and support time on each project.
- **"Other" database option.**
- **Overview hides completed projects by default.**
- **Intake automation (version 4)** adds new intakes to the app. "Master project list.csv" is now a frozen archive.

## Version 1 (October 19, 2026)
App version: 1365fc643797e6c932e57ce9367cae7c1efedf56 · Backup: "v1 2026-10-19"

- **Project Status field:** Pending, Ongoing, On hold, Completed.
- **Teamwork history imported:**
  - 45 projects
  - 238 dated time entries
  - an intake note for each project
