# HydraBox 2.0 — task ledger

Машиночитаемый журнал исполнения `docs/HYDRABOX2_PLAN.md`. Единственный источник
ответа на вопрос «выполнен ли предшественник». Строку добавляет сам агент — последним
шагом задачи, после коммита. Поля `STATUS` в карточках плана истиной не являются.

Формат: `<TASK ID> | <repo> | <commit> | <RESULT>`

`RESULT`: `DONE`, `BLOCKED(<что ждёт>)`, `CANCELLED(<причина>)`,
`DEFERRED(<причина>)`.

| TASK ID | REPO | COMMIT | RESULT |
|---|---|---|---|
| H2-000 | hydrabox | 0297082c5a48a0be7674122fa9dc93dae1de0102 | DONE |
| H2-001 | HydraBox2 | HEAD | DONE |
