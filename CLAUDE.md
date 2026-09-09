# CLAUDE.md — BLACKOUT: Last Grid

Інструкція для агента-розробника. Прочитай повністю перед першою дією.

## Проєкт
- 2D beat 'em up (belt-scroll) у дусі Streets of Rage 4, **Godot 4.x (.NET-збірка), C#**, Windows.
- Референс по бою і візуалу — Streets of Rage 4: принципи (belt-scroll, комбо, hit-stop, мальована анімація), а не запозичення ассетів чи персонажів.
- Джерела істини: `GAME_DESIGN.md` (сюжет, рівні, механіки, арт), `TASKS.md` (беклог), `AI_AGENTS_ROADMAP.md` (пайплайн агентів). Якщо код і документ розходяться — правильний документ; якщо документ неоднозначний — спитай, не вигадуй.
- Стиль графіки hand-painted 2D. **Арт-ассети не створювати і не змінювати** — тільки підключати готові з `assets/`. Для тестів використовуй кольорові плейсхолдери (`ColorRect`/`Polygon2D`) з префіксом `PH_`.

## Структура репозиторію
```
project.godot
BlackoutLastGrid.csproj / .sln
scenes/
  player/        Player.tscn
  levels/        Level00_Prologue.tscn, Level01_District.tscn, ...
  ui/            HUD.tscn, WorldMap.tscn
  props/         PowerPanel.tscn, Outlet.tscn, ...
  enemies/       Guard.tscn
scripts/         дзеркалить scenes/: scripts/player/Player.cs, scripts/core/GameState.cs ...
assets/
  art/           (тільки читання) player/, tiles/, props/, backgrounds/
  audio/
docs/            GAME_DESIGN.md, TASKS.md, AI_AGENTS_ROADMAP.md, plans/<slug>/<slug>-plan.md
tests/smoke/     headless smoke-тести (GDScript, extends SceneTree), запускаються tools/smoke.ps1
tools/           допоміжні скрипти (smoke.ps1)
GodotEngine/     локальні бінарники Godot .NET (у .gitignore, має .gdignore; не чіпати)
.claude/         скіли та налаштування агента (див. розділ «Скіли агента»)
```

## Конвенції коду
- C# 12, `nullable` увімкнено, `PascalCase` для класів/методів/публічних полів, `_camelCase` для приватних.
- Один вузол-сцена = один скрипт з тим самим ім'ям (`Player.tscn` ↔ `Player.cs`, клас `partial class Player : CharacterBody2D`).
- Зв'язок між вузлами — через **сигнали** та `[Export]`; жодних `GetNode("../../..")` за межі власної сцени.
- Глобальний стан — тільки в автолоаді `GameState` (`scripts/core/GameState.cs`): енергія, маршрут рівня 2, зібрані щоденники, репутація.
- Константи балансу (швидкість, витрата ліхтаря тощо) — `[Export]`-поля, не магічні числа в коді.
- Інпут — через `InputMap` (дії `move_left`, `move_right`, `move_up`, `move_down`, `jump`, `attack`, `heavy_attack`, `special`, `interact`, `flashlight`), не через сирі клавіші.
- Belt-scroll: персонажі та вороги — `CharacterBody2D` на площині підлоги; глибина = позиція Y; `y_sort_enabled` на батьківському вузлі рівня. Хітбокси/хертбокси — окремі `Area2D` із назвами `Hitbox`/`Hurtbox`, шкода перевіряється з урахуванням різниці по Y (допуск `[Export] DepthTolerance`, за замовчуванням 12 px).
- Бій: hit-stop через `Engine.TimeScale` або локальну паузу анімації на 3–5 кадрів; комбо — стейт-машина (`scripts/core/StateMachine.cs`), не ланцюжок if-ів.

## Перевірка роботи (обов'язково перед завершенням задачі)
```
dotnet build
godot --headless --path . --quit          # сцени/ресурси завантажуються без помилок, жодного рядка ERROR:
powershell -File tools/smoke.ps1          # усі smoke-тести tests/smoke/*.gd (headless GDScript), кожен друкує SMOKE <name> PASS|FAIL
```
`godot` = виконуваний файл Godot .NET, у PATH (обгортка на `GodotEngine/Godot_v4.7.2-stable_mono_win64_console.exe`). Якщо збірка або запуск падає — задача не завершена. Повна процедура і формат звіту — скіл `/verify`.
GdUnit4 не підключено (аддон = зовнішня залежність, потрібне узгодження); до того часу тести = smoke-скрипти в `tests/smoke/` за шаблоном зі скілу `/test-writer`.

## Робочий цикл
1. Візьми **одну** задачу з `TASKS.md` (першу зі статусом `todo`), постав їй `in_progress`.
2. Створи гілку `task/<id>-<коротка-назва>`.
3. Реалізуй, перевір командами вище, вручну відкрий сцену задачі як головну і переконайся, що вона запускається.
4. Постав статус `done`, допиши 1–2 рядки «що зроблено / що не зроблено» у задачу.
5. Коміт: `feat(<область>): <що зроблено> [T-xx]`. Один коміт на задачу, не мішати задачі.
6. Не переходь до наступної задачі без явного дозволу.
7. Пуш, злиття в `main` і PR робить автор після перевірки — агент не пушить.

Весь цикл автоматизовано скілом `/task T-xx`.

## Скіли агента (`.claude/skills/`)
| Скіл | Для чого |
|---|---|
| `/task T-xx` | повний робочий цикл однієї задачі з `TASKS.md` (гілка, реалізація, перевірка, статус, один коміт) |
| `/architect` | план змін у `docs/plans/<slug>/<slug>-plan.md` без коду; для задач, де є вибір дизайну |
| `/scene-design` | контракт сцени: дерево вузлів, `[Export]`, сигнали, шари колізій — до того, як сцену будують |
| `/project-settings` | процедура змін `project.godot` / InputMap / автолоадів / `.csproj` з обов'язковим описом у коміті |
| `/coder` | реалізація плану або задачі за конвенціями цього файлу |
| `/test-writer` | smoke-тести в `tests/smoke/` + чекліст ручного плейтесту |
| `/verify` | єдине визначення «перевірено»: build, headless, smoke, звіт |
| `/reviewer` | рев'ю всієї дельти гілки з Godot/C#-чеклістом; журнал у плані |
| `/orchestrator` | конвеєр coder → verify → test-writer → reviewer → coder → verify → test-writer → передача людині |

## Заборонено
- Змінювати `project.godot`, `.csproj`, `InputMap` без опису змін у коміті.
- Додавати зовнішні залежності (NuGet, аддони) без узгодження.
- Робити «покращення» поза скоупом задачі. Побачив проблему — запиши в `TASKS.md` як нову задачу зі статусом `backlog`.
- Видаляти чи перейменовувати файли в `assets/`.
