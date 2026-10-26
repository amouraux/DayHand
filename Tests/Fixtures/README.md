# Todoist CSV fixture

`todoist-official-template.csv` is the unmodified template linked by Todoist’s
[CSV export guide](https://www.todoist.com/help/account-and-billing/security/import-or-export-a-project-as-a-csv-file-in-todoist-YC8YvN),
downloaded on 25 October 2026 from
[the official attachment](https://get.todoist.help/hc/article_attachments/21672045045916).

It intentionally contains relative and recurring date text. Tests verify that
such expressions require review instead of guessing a date from the test clock.
