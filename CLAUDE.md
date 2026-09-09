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
docs/            GAME_DESIGN.md, TASKS.md, AI_AGENTS_ROADMAP.md
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
godot --headless --path . --quit          # сцени/ресурси завантажуються без помилок
godot --headless --path . --run-tests     # якщо є GdUnit4/gdUnit-тести
```
`godot` = виконуваний файл Godot .NET, у PATH. Якщо збірка або запуск падає — задача не завершена.

## Робочий цикл
1. Візьми **одну** задачу з `TASKS.md` (першу зі статусом `todo`), постав їй `in_progress`.
2. Створи гілку `task/<id>-<коротка-назва>`.
3. Реалізуй, перевір командами вище, вручну відкрий сцену задачі як головну і переконайся, що вона запускається.
4. Постав статус `done`, допиши 1–2 рядки «що зроблено / що не зроблено» у задачу.
5. Коміт: `feat(<область>): <що зроблено> [T-xx]`. Один коміт на задачу, не мішати задачі.
6. Не переходь до наступної задачі без явного дозволу.

## Заборонено
- Змінювати `project.godot`, `.csproj`, `InputMap` без опису змін у коміті.
- Додавати зовнішні залежності (NuGet, аддони) без узгодження.
- Робити «покращення» поза скоупом задачі. Побачив проблему — запиши в `TASKS.md` як нову задачу зі статусом `backlog`.
- Видаляти чи перейменовувати файли в `assets/`.
