# PI Revision Tracker – Version 2 (current rollback point)

Saved: Monday, October 19, 2026, 12:20 PM Eastern
Live app: https://play.managedapps.cloud.microsoft/apps/b93394f3-be08-447e-bf98-7deb2a754fc3

## What version 2 contains

**App** (published app version a22630459a3276281ea89a004689df720e0376ab, stored with the app)
- Dashboard home page:
  - portfolio by status and database
  - "Waiting to start" queue
  - "In progress" list
  - hours by month
  - Download report (Excel)
- Projects page:
  - project number shown separately, newest first
  - Status filter and dropdown
  - Intake date, Start date, wait to start, last worked and support time
  - Requested by, Intake source and Research output fields
- Overview hides Completed projects unless switched on.
- "Other" added as a database option.
- A copy of the app's source code is in "PI Revision Tracker v2 app source.zip".

**Data at the time of saving** (SharePoint site https://miamiedu.sharepoint.com/sites/pi-revision-tracker-040dea)

| List | Rows | Backup file |
|---|---|---|
| projects-9426df72 | 46 (45 projects + "test") | projects.csv |
| time-log-9426df72 | 238 entries, 1,070.68 hours | time-log.csv |
| notes-9426df72 | 45 intake notes | notes.csv |
| revision rounds, tasks, change items, activity log, agent requests | 0 | (empty, no file) |

Status counts: 22 Completed, 16 Pending, 6 Ongoing, 1 On hold.

The app is now the only project record. "Master project list.csv" and "project_submission_dates.csv" are a frozen archive, and the intake automation no longer updates them.

## How to roll back

- **To version 2:** ask Copilot to "republish PI Revision Tracker version 2 (a22630459a3276281ea89a004689df720e0376ab)".
- **To version 1:** ask for version 1 (1365fc643797e6c932e57ce9367cae7c1efedf56). Note that version 1 doesn't show project numbers, because they are no longer stored in the titles.
- **Data is not affected by rolling the app back.** It lives in the SharePoint lists.
- **One item changed by mistake:** use the item's Version history in the list. Each list keeps the last 50 versions of every item.
- **Item deleted by mistake:** restore it from the site's Recycle bin.
- **Bigger problem:** the CSV files in this folder hold every row as of this date, and Copilot can reload them.

## Intake automation (version 4, as of this backup)

For each new Cognito intake email (notifications@cognitoforms.com, subject containing "Study Intake Form - The Biostatistics Center"), the automation:

1. Assigns the next ProjectNumber from the app.
2. Adds the project to the app (Status Pending, intake date, requested by, intake source) with an intake note.
3. Creates the numbered folder in OneDrive\Projects.
4. Saves "YYYYMMDD intake.docx" in the folder.
5. Creates an R subfolder for IRIS projects.
6. Applies the Outlook category.
7. Sends a Teams self-chat summary.

A revised intake for an existing project only gets a note in the app.
