# PI Revision Tracker – Version 1 (rollback point)

Saved: Monday, October 19, 2026, 10:20 AM Eastern
Live app: https://play.managedapps.cloud.microsoft/apps/b93394f3-be08-447e-bf98-7deb2a754fc3

## What version 1 contains

**App**
- Projects, Overview and Time tracking pages.
- Project Status field (Pending, Ongoing, On hold, Completed), shown as a label in the project list and Overview, with a Status filter and a Status dropdown on each project.
- Completed projects count as finished.
- Published app version: 1365fc643797e6c932e57ce9367cae7c1efedf56. This published version stays stored with the app.
- A copy of the app's source code is in "PI Revision Tracker v1 app source.zip".

**Data at the time of saving** (SharePoint site https://miamiedu.sharepoint.com/sites/pi-revision-tracker-040dea)

| List | Rows | Backup file |
|---|---|---|
| projects-9426df72 | 46 (45 imported + "test") | projects.csv |
| time-log-9426df72 | 238 Teamwork entries, 1,070.68 hours | time-log.csv |
| notes-9426df72 | 45 intake notes | notes.csv |
| revision-rounds, tasks, change-items, activity-log, agent-requests | 0 | (empty, no file) |

Status counts: 22 Completed, 16 Pending, 6 Ongoing, 1 On hold.

## How to roll back

- **App only:** ask Copilot to "republish PI Revision Tracker version 1 (1365fc643797e6c932e57ce9367cae7c1efedf56)". Your data is not affected, because it lives in the SharePoint lists, not in the app.
- **One item changed by mistake:** open the list on the SharePoint site, select the item, choose Version history and restore an earlier version. Each list keeps the last 50 versions of every item.
- **Item deleted by mistake:** restore it from the site's Recycle bin.
- **Bigger problem:** the CSV files in this folder hold every row as of this date. Copilot can reload them into the lists.

## Intake automation (as of this version)

"Biostat intake form → new project setup" fires on Cognito intake emails (notifications@cognitoforms.com, subject containing "Study Intake Form - The Biostatistics Center"). For each new intake it:

1. Assigns the next project number from Master project list.csv.
2. Creates the numbered folder in OneDrive\Projects.
3. Saves "YYYYMMDD intake.docx" in the folder.
4. Creates an R subfolder for IRIS projects.
5. Applies the Outlook category.
6. Adds rows to Master project list.csv and project_submission_dates.csv.
7. Adds the project to the app with Status Pending, plus an intake note.
8. Sends a Teams self-chat summary.

A revised intake for an existing project only gets a note in the master list.
