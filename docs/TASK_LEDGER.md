# Task ledger

Машиночитаемый журнал исполнения плана. Единственный источник ответа на вопрос
«выполнен ли предшественник». Строку добавляет сам агент — последним шагом задачи,
после коммита.

Формат: `<TASK ID> | <repo> | <commit> | <RESULT>`

`repo`: `hydrabox` = `D:\dev\HydraBox\hydrabox`, `hydracore` = `D:\dev\hydracore\hydracore`.
`RESULT`: `DONE` либо `BLOCKED(<что ждёт>)`.

| TASK ID | REPO | COMMIT | RESULT |
|---|---|---|---|
| HB-RW-001 | hydrabox | ce91815 | DONE |
| HB-RW-002 | hydrabox | f83ffeb | DONE |
| HB-RW-040 | hydrabox | 38d4f83 | DONE |
| HB-RW-041+042 | hydrabox | 2f49ba5 | DONE (карточки слиты решением тимлида, C17) |
| HB-RW-003 | hydrabox | 305c139 | DONE (+ 97caf72 фикс фейка config coordinator) |
| HB-RW-004 | hydrabox | 491eacf | DONE |
| HB-RW-006 | hydrabox | 3832fab | DONE |
| HC-RW-001 | hydracore | 2951d7d3 | DONE (ветка debug; дубль df03fa02 в submodule отброшен) |
| HC-RW-002 | hydracore | 6b0b122d | DONE |
| HC-RW-003 | hydracore | 34da49ed | DONE |
| HC-RW-004 | hydracore | be30c53c | DONE (включает HC-RW-006) |
| HC-RW-005 | hydracore | 2e868e16 | DONE |
| HB-BUNDLE-001 | hydrabox | 4c00f16 | DONE |
| HB-RW-023 | hydrabox | 2e2706f | DONE |
| HB-RW-019 | hydrabox | 267f320 | DONE |
| HB-RW-016 | hydrabox | df78787 | DONE (+ одна строка в MainActivity по решению тимлида) |
| HB-RW-012 | hydrabox | 7df8463 | DONE |
| HB-RW-005 | hydrabox | — | BLOCKED(HB-EXP-E11 — нужен девайс) |
| HB-RW-015 | hydrabox | 6b80169 | DONE |
| HB-RW-015-FIX | hydrabox | — | DONE |
| HB-RW-014 | hydrabox | d3339ae | DONE |
| HB-RW-013 | hydrabox | c3b3922 | DONE (_queuedRestartSuppressed оставлен — дефект плана, см. §8.3) |
| HB-RW-002-FIX | hydrabox | b663a02 | DONE |
| HB-RW-001-FIX | hydrabox | 7082e08 | DONE |
