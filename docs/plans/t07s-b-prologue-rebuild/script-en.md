# Script (EN) — Prologue «Shift» / Рівень 0

Англомовний сценарій прологу: кат-сцени (текстовий оверлей) і репліки Дана (бульбашки).
Джерело: [`docs/GAME_DESIGN.md`](../../GAME_DESIGN.md) §1 (два контури), §2 (Рей, подвійна
мотивація, повербанк Дана), §3 «Рівень 0 — Пролог» (сім сегментів, escape-головоломка),
§5 (персонажі), §6 (арт рівня 0). Механіки і сигнали:
[`../t07s-a-escape-mechanics/t07s-a-escape-mechanics-plan.md`](../t07s-a-escape-mechanics/t07s-a-escape-mechanics-plan.md).

Коментарі й інструкції — українською (вони для автора й виконавця). **Усе, що бачить гравець, —
англійською**, як вимагає §3 «Мова». Нічого, крім тексту, цей документ не визначає: сцени, тригери
й розстановка — задача T-07s-b.

---

## 0. Технічні рамки тексту (прочитати перед правками)

**Кат-сцена — `scenes/ui/Cutscene.tscn` + `scripts/ui/Cutscene.cs`.**
- Один елемент масиву `Lines` = **один екран**. Гравець гортає їх на `interact` (або `attack`),
  гра стоїть на паузі, знизу підказка `E — next` / на останньому рядку `E — continue`.
- Label: 1280×280 px, `font_size = 32`, `autowrap_mode = 3`, вирівнювання по центру.
  Практично це **~78 символів на візуальний рядок** і **до 6 рядків** у висоту.
- **Робоче правило: один екран ≤ 120 символів** (два візуальні рядки). Жорстка межа — 160.
  Нижче в дужках вказано довжину кожного екрана в символах.
- **Розмір кат-сцени: 2–8 екранів.** Довша — гравець починає гортати, не читаючи. Вступ (6–7) і
  смерть Дана (8) — найдовші в пролозі; решта коротші навмисно.
- Атрибуція репліки — префіксом (`DAN:`, `RAY:`, `FOREMAN:`, `GUARD:`). Екрани без префікса —
  ремарка/опис, не чийсь голос.

**Бульбашка Дана — `Companion.Say(string)`.**
- `BubbleSeconds = 2.6` с, гру **не** ставить на паузу, читається на ходу.
- **Робоче правило: ≤ 40 символів (≈7 слів).** Жорстка межа — 56.
- **Виняток — окрик про газ.** `GasZone.WarningSeconds = 0.8` с: у гравця менше секунди на
  реакцію, тож ця репліка мусить впізнаватись **периферійним зором**: ≤ 12 символів, великими,
  без підрядного речення.
- Нова `Say()` **затирає** попередню. Між двома репліками Дана має бути **≥ 3 с**; якщо дві події
  спрацьовують разом, виграє та, що має менший пріоритет у таблиці «подія → репліка».
- Під час кат-сцени Дан **мовчить**: бульбашка й оверлей одночасно = каша. Перед `Cutscene.Play()`
  викликати `SetBubbleSuppressed(true)`, після `Finished` — `false`.

**Імена.** `Ray` (Рей), `Dan` (Дан), `the foreman` (бригадир, імені не має і не отримає),
`the sealing crew` (герметизаційна бригада). Написання `Ray` / `Rey` — за автором; у цьому файлі
скрізь `Ray`, заміна одним пошуком.

**Голоси.**
- **Дан** — молодший, балакучий, міряє світ змінами, картками і нормою. Вірить, що система
  рахує його роботу. Говорить короткими ствердженнями, часто про побут, майже ніколи про
  «справедливість». Його оптимізм — не наївність, а звичка.
- **Рей** — технік, старший, мовчазний. **Його головна репліка — та, якої немає.** У всьому
  пролозі Рей вимовляє близько семи реплік, і жодна з них не пояснює, що він думає.
  Коли Рей мав би заперечити — він погоджується або мовчить. Це і є характер.
- **Бригадир** — не лиходій, а процедура з голосом. Говорить формулюваннями з журналу.

---

## Сегмент 0 — Coalface, before the blast

Штатне світло, гуркіт, туторіал руху і стрибка. Дан поруч і балакає. Тут гравець мусить
встигнути полюбити Дана — тому реплік тут **більше, ніж деінде**, і всі вони ні про що.

### Кат-сцена `Intro` (7 екранів)

```
1. Lower horizon. Fourth hour of the shift. The lamps hold. The air does not move.          (81)
2. DAN: Sixty carts today. Sixty. Two weeks over quota now, and they count it, Ray.
   They have to count it.                                                                  (105)
3. DAN: You work, they give you more. That's the whole thing. That's all it is.              (78)
4. RAY: Sure.                                                                                (10)
5. Ray taps the methane head on the rib with two fingers. The needle does not move.
   It has not moved in eight days.                                                          (114)
6. DAN: You wrote them about that one. Week back. They wrote you back, yeah?                 (75)
7. RAY: They wrote back.                                                                     (22)
```

> **Де текст мовчить.** Екран 7 — весь пролог у двох словах. Рей не бреше: рапорт справді
> прийняли. Він просто не каже другої половини. Якщо потрібно скоротити вступ до 5 екранів —
> **різати екран 3**, а не 6–7: без 6–7 провина Рея не посіяна і фінал не має ґрунту.
>
> **Альтернатива до екранів 6–7** (жорсткіша, якщо автор хоче, щоб Рей збрехав прямо):
> `DAN: So it's handled?` / `RAY: It's handled.`

### Репліки Дана — сегмент 0

| Подія | Репліка | Симв. |
|---|---|---|
| `TutorialPrompt.Shown` (рух) | `Come on. Cart won't fill itself.` | 32 |
| `TutorialPrompt.Shown` (стрибок) | `Over the sleepers. Don't trip.` | 30 |
| ambient, раз, через ~8 с простою | `Two more carts and we're up top.` | 32 |
| ambient, раз (альтернатива до попередньої) | `You hear that motor? It's cooking.` | 34 |

> Остання — єдина технічна деталь, яку Дан кидає мимохідь: двигун конвеєра гріється. Через
> хвилину він дасть іскру. Дан цього не знає; гравець згадає.

---

## Сегмент 1 — The blast and the dark

Вибух, завал відрізає шлях назад, штатне світло гасне. Рей знаходить Дана. Туторіал ліхтаря і
розеток. Перший `heavy_attack` — по завалу з кріпильного лісу.

### Кат-сцена `Blast` (2 екрани)

```
1. A spark off the conveyor motor. The air takes it.                                        (51)
2. The horizon folds. The lamp string goes out from the far end, one bulb at a time.        (82)
```

> **Де текст мовчить.** Вибух — не місце для слів. Два екрани, ніяких вигуків, ніякого «Dan!».
> Далі — чорний екран і тільки звук, доки гравець не ввімкне ліхтар. Якщо стане питання
> «чи додати третій екран» — ні. Порожнеча тут працює краще за будь-який рядок.
>
> **Альтернатива (1 екран, ще сухіше):** `A spark off the conveyor motor. Then the horizon folds.`

### Репліки Дана — сегмент 1

| Подія | Репліка | Симв. |
|---|---|---|
| зустріч після вибуху (скриптова точка, `Companion.Arrived`) | `Ray! Here! I'm all right.` | 25 |
| через 3 с після зустрічі | `Nothing's broken. Nothing's broken.` | 35 |
| `TutorialPrompt.Shown` (ліхтар) | `Lamp on. I can't see my hands.` | 30 |
| `Outlet.Charged` (перша розетка) | `That's your light. Don't waste it.` | 34 |
| `DebrisPile.Resisted` (важкий удар не пройшов) | `Hit the prop, not the middle.` | 29 |
| `DebrisPile.Cleared` | `There. Go.` | 10 |
| `CaveIn.Collapsed` (перший обвал) | `That's the way back gone.` | 25 |

> `Nothing's broken. Nothing's broken.` — повтор навмисний: він переконує себе, а не Рея.
> Рей на це не відповідає нічого — і не відповість жодного разу за весь рівень.

---

## Сегмент 2 — Flooded drift → the pump (перша відмова контуру)

Перший урок контуру: щоб запустити насос, треба зняти живлення з робочого освітлення. Далі
гравець іде в темряві — і сам це вибрав. **Правило контуру озвучує Дан, не туторіальний текст.**

### Кат-сцен немає

> Кат-сцени тут бути не повинно: урок мусить статись у руках гравця, а не на екрані з текстом.
> Панель уже сама називає винного (`No power: the pump is running`); Дан додає людський бік.

### Репліки Дана — сегмент 2

| Подія | Репліка | Симв. |
|---|---|---|
| підхід до затопленого штреку | `Waist deep. Not walking through that.` | 37 |
| `PowerPanel.ActivationRefused` (**перша відмова**) | `Won't take both. Kill the lights.` | 33 |
| `PowerPanel.ActivationRefused` (друга і далі) | `Same story. One at a time.` | 26 |
| `PowerPanel.Deactivated` (гравець зняв освітлення) | `Same as up top. Give here, take there.` | 38 |
| `PoweredMachine.PowerChanged(true)` — насос пішов | `Dark it is, then.` | 17 |

> `Same as up top. Give here, take there.` — центральна репліка прологу і єдине місце, де тема
> гри промовляється вголос. Вона працює тільки тому, що сказана **про насос**, а не про місто:
> «up top» Дан каже про поверхню шахти, гравець дочує решту сам. **Цю репліку не розширювати.**
>
> **Альтернатива:** `Always the same. Light here, dark there.` (38) — ритмічніша, але ближча
> до гасла; перший варіант безпечніший.

---

## Сегмент 3 — Gas pocket → the extractor, or the dark. Перший стелс

Головна пастка: у газі не можна світити. Аварійний вихід глушить герметизаційна бригада.
Дан пригинається і замовкає **сам**, без підказки гравцеві.

### Кат-сцен немає

> Герметизаційна бригада не отримує кат-сцени і не отримує реплік. Вони не мають облич і не
> мають голосів — вони інструмент і маска. Те, що вони роблять, гравець читає з дії: заварюють.

### Репліки Дана — сегмент 3

| Подія | Репліка | Симв. |
|---|---|---|
| підхід до кишені (`Area2D` перед зоною) | `Air's gone yellow. Don't light it.` | 34 |
| **`GasZone.WarningStarted`** | **`LAMP OFF!`** | **9** |
| `GasZone.WarningStarted` (повторно, якщо гравець тут уже гинув) | `OFF! NOW!` | 9 |
| `GasZone.Cleared` (витяжка відпрацювала) | `Breathe. It's moving now.` | 25 |
| вихід із кишені в темряві (без витяжки) | `Told you. Straight line, no light.` | 34 |
| початок стелсу (бригаду видно) | `Down.` | 5 |
| **весь стелс-сегмент** | **— (жодної репліки)** | — |
| стелс пройдено | `They're not digging. They're sealing it.` | 40 |

> **Окрик про газ.** Вікно — 0.8 с, тобто репліка мусить впізнаватись **формою**, а не читатись.
> `LAMP OFF!` — дві короткі одиниці, великі літери, знак оклику. Альтернативи в порядку
> прийнятності: `LAMP!` (5), `KILL IT!` (8), `NO LIGHT!` (9). **Не використовувати**
> `Turn your lamp off!` (19) — за 0.8 с не читається і вб'є сегмент.
>
> **Де текст мовчить.** Стелс — єдине місце в рівні, де Дан не говорить **жодного** слова, і
> це найпомітніша тиша прологу. Він сідає навпочіпки на кадр раніше за гравця; підказку про
> стелс гравець отримує з його тіла, а не з бульбашки. Якщо додати сюди хоч одну репліку —
> зникне контраст із сегментом 4, де він знову розбалакується, і смерть втратить половину ваги.
>
> `They're not digging. They're sealing it.` — тут Дан уперше каже щось про систему, і каже це
> як факт про роботу, а не як звинувачення. Рей не коментує.
> **Альтернатива (сильніша, якщо автор хоче, щоб Дан навіть не здивувався):** репліки немає
> взагалі — Дан не питає, що робить бригада, бо і так знає. Тоді сегмент закінчується в тиші.

---

## Сегмент 4 — Upper horizon. Уперше видно кліть

Ціль стає видимою, і Дан це вимовляє вголос. **Тонально найважче місце рівня:** він щиро
вірить, що вони вибрались, і гравець разом із ним. Через кілька хвилин він загине.

### Кат-сцен немає

> Кат-сцена тут прибила б темп і повторила б те, що вже сказала камера. Цей сегмент тримається
> на одному: Дан радіє, Рей мовчить.

### Репліки Дана — сегмент 4

| Подія | Репліка | Симв. |
|---|---|---|
| кліть уперше в кадрі (`Area2D` на порозі сегмента) | `That's the cage. Ray, that's the cage.` | 38 |
| через 4 с | `Cage has power up top. It'll lift.` | 34 |
| середина дороги до кліті | `They'll have to pay the shift for this.` | 39 |
| ближче до кліті | `Two days off. Minimum.` | 22 |
| останні кроки перед сегментом 5 | `Mum'll be at the gate. She always is.` | 37 |

> **Це і є те, за що гравцеві буде боляче.** Жодна з цих реплік не про порятунок — усі про те,
> що буде **після**. Дан рахує вихідні й компенсацію зміні; за кілька хвилин бригадир
> випише цій самій зміні штраф, а картку Дана вріже посмертно. Порядок реплік зберегти: від
> факту (`cage has power`) до майбутнього (`two days off`, `Mum`) — він піднімається рівно
> перед падінням.
>
> **Альтернатива до `They'll have to pay the shift for this.`:** `Hazard pay for this. Has to be.`
> (31) — ще точніше б'ється об штраф у сегменті 7.
>
> **Рей за весь сегмент не каже нічого.** Це навмисно: він єдиний, хто знає про рапорт,
> і єдиний, хто розуміє, що «заплатять» не буде. Якщо десь і додавати репліку Рея — то не тут.

---

## Сегмент 5 — The cage: one switch-off

Кліть перед очима, поруч працює остання машина, усе в межах одного екрана.

### Репліки Дана — сегмент 5

| Подія | Репліка | Симв. |
|---|---|---|
| `PowerPanel.ActivationRefused` на кліті | `It wants the lot. Shut that one down.` | 37 |
| `Hoist` отримав живлення (`PowerChanged(true)`) | `Get in. Get in, Ray.` | 20 |

> Дві репліки, і обидві — команди. Дан уперше за рівень квапить Рея, а не навпаки.

---

## Сегмент 6 — The last fall (смерть Дана)

Скриптова сцена. Не провал гравця, не escort-fail, врятувати не можна.

### Кат-сцена `DanDeath` — **ВАРІАНТ A (рекомендований)** (8 екранів)

```
1. The roof comes down between them and the cage. When the dust drops there is one gap
   left, at the top, the width of a man's shoulders.                                       (134)
2. DAN: Up you go.                                                                          (15)
3. RAY: Both of us. Give me your arm —                                                      (36)
4. DAN: It's one. You can see it's one.                                                     (36)
5. Dan gets a shoulder under him and pushes him into the gap. Then he pulls the powerbank
   off his own belt and presses it into Ray's hand.                                        (137)
6. DAN: Take it. Yours is down to eleven. You'll make it.                                   (55)
7. RAY: Dan —                                                                               (11)
8. The rest of the roof comes down behind him.                                              (44)
```

> **Чому так.** Дан не прощається і не каже нічого про себе. Він робить дві речі — виштовхує
> і віддає повербанк — і обидві обґрунтовує **технічно**: щілина одна, у Рея одинадцять
> відсотків. Це його спосіб не сказати того, що всі троє (він, Рей, гравець) уже знають.
> Екран 7 — уся репліка Рея за цю сцену: одне слово, обірване. Він так і не скаже нічого.
> Екран 1 навмисно довгий: це остання пауза перед тим, як усе піде швидко.
>
> **Де текст мовчить.** Після екрана 8 — **нічого**. Ні рядка про те, що Рей кричав, стукав
> чи кликав. Порожній екран, звук, потім сегмент 7. Будь-який дев'ятий екран тут перетворює
> смерть на опис смерті.

### Кат-сцена `DanDeath` — ВАРІАНТ B (коротший, 5 екранів; Дан не встигає нічого пояснити)

```
1. The roof comes down between them and the cage. One gap left at the top, and it is
   the width of one man.                                                                   (105)
2. DAN: Go.                                                                                  (9)
3. Ray does not move. Dan puts a shoulder under him, lifts, and pushes him through.
   Something small and heavy goes into Ray's hand on the way.                              (144)
4. DAN: You'll make it.                                                                     (21)
5. Then the rest of it comes down.                                                          (32)
```

> Тут повербанк гравець упізнає **не одразу** — «something small and heavy». Розуміння приходить
> у сегменті 7, коли охоронець на нього претендує. Ризик: частина гравців не зрозуміє, що це
> був за предмет.

### Кат-сцена `DanDeath` — ВАРІАНТ C (Дан бреше, і обидва це знають; 7 екранів)

```
1. The roof comes down between them and the cage. One gap at the top, and it is not
   wide enough for two.                                                                    (104)
2. DAN: Get through. I'll come round by the pump drift.                                     (53)
3. RAY: The pump drift is sealed.                                                           (31)
4. DAN: Then I'll wait for the crew. They've got a cutter, you saw it.                      (68)
5. He says it, and the whole time he says it his hand is on Ray's back, pushing.
   The powerbank goes into Ray's palm.                                                     (115)
6. DAN: Take it. Don't argue for once.                                                      (35)
7. The roof takes the rest.                                                                 (25)
```

> Найжорсткіший варіант: Дан називає рятунком саме ту бригаду, яка їх заварює (сегмент 3).
> Працює лише за умови, що гравець пройшов стелс і бачив, чим вони займаються. Якщо стелс
> можна пропустити — брати A.

---

## Сегмент 7 — Up top

Бригадир, штраф, зниклий рапорт. Єдиний справжній бій прологу — коли охоронець намагається
забрати повербанк Дана.

### Кат-сцена `Foreman` (7 екранів)

```
1. Lamp room. The shift hands in its tags. The foreman counts them twice and writes
   one line.                                                                                (92)
2. FOREMAN: Cause of loss: breach of safety procedure by the crew. Fine on the shift.
   Twenty percent, fourteen days.                                                          (114)
3. RAY: He was on the bottom horizon because the ventilation was off.                        (67)
4. FOREMAN: Fine's on the shift. That includes his card.                                     (54)
5. RAY: He's dead.                                                                           (16)
6. FOREMAN: Card's active to the end of the month. Next.                                     (54)
7. Ray asks for the log. Week before last, lower horizon: methane heads, extraction.
   The page is there. His report is not.                                                   (120)
```

> Бригадир не жорстокий і не зловтішається — він **зачитує рядок**. Уся сила екрана 6 у слові
> `Next.`: черга рухається далі, і це найточніше, що можна сказати про цей світ.
> Екран 7 замикає вступ: гравець чув, як Рей казав `They wrote back` — тепер сторінки немає.
>
> **Опційний екран 8** (якщо автор захоче, щоб бригадир договорив): `FOREMAN: Nothing was
> filed. You're holding up the line.` (55) — я б не додавав: після «The page is there. His
> report is not.» будь-яке слово слабше.

### Кат-сцена `Guard` (3 екрани, одразу перед боєм)

```
1. GUARD: Two banks, one card. Hand the other one in.                                       (52)
2. Ray does not hand it in. He does not say anything either.                                 (58)
3. GUARD: Have it your way.                                                                  (26)
```

> **Де текст мовчить.** Екран 2 — кульмінація характеру Рея: весь рівень він мовчав, бо не
> сперечався; тут він мовчить, бо вирішив. Одна й та сама тиша означає протилежне, і гравець
> це відчує без жодного пояснення.

### Кат-сцена `Ending` — **ВАРІАНТ A (рекомендований)** (7 екранів)

```
1. Morning. The wind off the spoil tip is cold and full of coal.                            (63)
2. Behind him the district plant stands with its stacks cold. This coal fed that plant.     (86)
3. The street lamps are dead the whole way down the hill. They have been for years.         (82)
4. On the horizon the centre is lit. All of it. Every floor.                                (58)
5. Ray's own bank reads eleven percent. Dan's is full.                                      (52)
6. He puts Dan's in the inside pocket, where it does not touch anything.                    (70)
7. Then he starts walking down the hill.                                                    (38)
```

> **Чому так.** Мораль ніде не вимовлена — її робить географія кадру: мертва ТЕЦ позаду, повністю
> освітлений центр попереду, між ними людина з одинадцятьма відсотками. Обидві мети Рея (§2)
> стоять у кадрі одночасно й жодна не названа. Екрани 5–6 — про повербанк, який він
> **не витратить усю гру**; це поставлено як жест, а не як обіцянка.
>
> **Де текст мовчить.** Немає рядка про помсту, немає рядка про те, що він щось зрозумів, немає
> згадки про матір (вона — сцена рівня 1, і забирати її в рівня 1 не можна). Останній екран —
> дія, не думка.

### Кат-сцена `Ending` — ВАРІАНТ B (5 екранів, закінчується на повербанку)

```
1. Morning. Cold wind off the spoil tip, and it tastes of coal.                             (62)
2. The plant that this mine fed stands behind him with its stacks cold.                     (70)
3. Down the hill, not one street lamp. On the horizon, the centre, lit to the top floor.    (87)
4. Dan's bank is in his inside pocket. It is full. It stays full.                           (64)
5. Ray starts walking.                                                                      (21)
```

> Компактніший і жорсткіший. `It stays full.` — єдине місце в усьому пролозі, де текст дозволяє
> собі натяк на майбутнє; якщо автор вважає це підказкою — лишити `It is full.` і крапка.

### Кат-сцена `Ending` — ВАРІАНТ C (4 екрани, закінчується на рядку з журналу)

```
1. Morning. Behind him the district plant, stacks cold. Ahead, down the hill, no lamps
   at all.                                                                                  (93)
2. On the horizon the centre is lit. Every floor of it.                                     (54)
3. The line the foreman wrote goes in the ledger tonight: breach of safety procedure,
   fine on the shift, fourteen days.                                                       (117)
4. Ray walks down towards the dark part.                                                    (39)
```

> Найхолодніший варіант: фінал належить не Рею, а рядку в журналі. Сильно, але ризиковано —
> повторює те, що гравець щойно бачив у сцені з бригадиром, і послаблює повербанк як предмет.

---

## Зведена таблиця «подія → репліка» (для виконавця)

Кат-сцени — через `Cutscene.Play(Lines)`, гра на паузі. Репліки Дана — `Companion.Say(text)`,
2.6 с, без паузи. Пріоритет: менше число виграє, якщо дві події збіглись в одному кадрі.

| # | Сегм. | Подія / сигнал | Тип | Текст | Симв. | Пріор. |
|---|---|---|---|---|---|---|
| 1 | 0 | старт рівня | cutscene | `Intro` (7 екранів) | — | 1 |
| 2 | 0 | `TutorialPrompt.Shown` (рух) | bubble | `Come on. Cart won't fill itself.` | 32 | 5 |
| 3 | 0 | `TutorialPrompt.Shown` (стрибок) | bubble | `Over the sleepers. Don't trip.` | 30 | 5 |
| 4 | 0 | ambient, раз, ~8 с простою | bubble | `You hear that motor? It's cooking.` | 34 | 9 |
| 5 | 1 | скриптовий вибух | cutscene | `Blast` (2 екрани) | — | 1 |
| 6 | 1 | `Companion.Arrived` (зустріч) | bubble | `Ray! Here! I'm all right.` | 25 | 2 |
| 7 | 1 | +3 с після №6 | bubble | `Nothing's broken. Nothing's broken.` | 35 | 6 |
| 8 | 1 | `TutorialPrompt.Shown` (ліхтар) | bubble | `Lamp on. I can't see my hands.` | 30 | 4 |
| 9 | 1 | `Outlet.Charged` (перша) | bubble | `That's your light. Don't waste it.` | 34 | 6 |
| 10 | 1 | `DebrisPile.Resisted` | bubble | `Hit the prop, not the middle.` | 29 | 4 |
| 11 | 1 | `DebrisPile.Cleared` | bubble | `There. Go.` | 10 | 7 |
| 12 | 1 | `CaveIn.Collapsed` (перший) | bubble | `That's the way back gone.` | 25 | 3 |
| 13 | 2 | вхід у зону затопленого штреку | bubble | `Waist deep. Not walking through that.` | 37 | 5 |
| 14 | 2 | `PowerPanel.ActivationRefused` (1-ша) | bubble | `Won't take both. Kill the lights.` | 33 | 2 |
| 15 | 2 | `PowerPanel.ActivationRefused` (2+) | bubble | `Same story. One at a time.` | 26 | 6 |
| 16 | 2 | `PowerPanel.Deactivated` (освітлення) | bubble | `Same as up top. Give here, take there.` | 38 | 2 |
| 17 | 2 | `PoweredMachine.PowerChanged(true)` — насос | bubble | `Dark it is, then.` | 17 | 5 |
| 18 | 3 | вхід у зону перед газовою кишенею | bubble | `Air's gone yellow. Don't light it.` | 34 | 3 |
| 19 | 3 | **`GasZone.WarningStarted`** | bubble | **`LAMP OFF!`** | 9 | **0** |
| 20 | 3 | `GasZone.WarningStarted` після смерті тут | bubble | `OFF! NOW!` | 9 | 0 |
| 21 | 3 | `GasZone.Cleared` | bubble | `Breathe. It's moving now.` | 25 | 5 |
| 22 | 3 | вихід із кишені без витяжки | bubble | `Told you. Straight line, no light.` | 34 | 6 |
| 23 | 3 | бригаду видно (початок стелсу) | bubble | `Down.` | 5 | 2 |
| 24 | 3 | **весь стелс** | — | **тиша, навмисно** | — | — |
| 25 | 3 | стелс пройдено | bubble | `They're not digging. They're sealing it.` | 40 | 4 |
| 26 | 4 | кліть уперше в кадрі | bubble | `That's the cage. Ray, that's the cage.` | 38 | 2 |
| 27 | 4 | +4 с після №26 | bubble | `Cage has power up top. It'll lift.` | 34 | 5 |
| 28 | 4 | середина дороги до кліті | bubble | `They'll have to pay the shift for this.` | 39 | 3 |
| 29 | 4 | далі по дорозі | bubble | `Two days off. Minimum.` | 22 | 5 |
| 30 | 4 | останні кроки сегмента | bubble | `Mum'll be at the gate. She always is.` | 37 | 3 |
| 31 | 5 | `PowerPanel.ActivationRefused` на кліті | bubble | `It wants the lot. Shut that one down.` | 37 | 2 |
| 32 | 5 | `Hoist.PowerChanged(true)` | bubble | `Get in. Get in, Ray.` | 20 | 2 |
| 33 | 6 | скриптовий останній завал | cutscene | `DanDeath` — варіант A (8 екранів) | — | 1 |
| 34 | 6 | після кат-сцени | — | **тиша: Дан більше не говорить ніколи** | — | — |
| 35 | 7 | `Hoist.Departed` / прибуття кліті | cutscene | `Foreman` (7 екранів) | — | 1 |
| 36 | 7 | перед боєм за повербанк | cutscene | `Guard` (3 екрани) | — | 1 |
| 37 | 7 | хвиля зачищена | cutscene | `Ending` — варіант A (7 екранів) | — | 1 |

**Підсумок обсягу:** 6 кат-сцен (34 екрани в рекомендованих варіантах), 28 реплік Дана.
Найдовший екран — 137 символів (`DanDeath` A, екран 5), найдовша бульбашка — 40 символів
(№25), найкоротша — 5 (№23).

---

## Де текст навмисно мовчить (зведено)

| Місце | Чого там немає | Навіщо |
|---|---|---|
| Вибух (сегм. 1) | ні крику, ні імені | подія сильніша за реакцію на неї; два екрани й темрява |
| Весь стелс (сегм. 3) | жодної репліки Дана | єдина повна тиша рівня; вона готує контраст із балакучим сегментом 4 |
| Сегмент 4 | Рей не каже нічого | він єдиний знає, що «заплатять» не буде; мовчання = знання |
| Після екрана 8 `DanDeath` | ні рядка про горе | опис горя скасовує горе |
| Сегмент 7, `Guard`, екран 2 | Рей мовчки не віддає | те саме мовчання, що весь рівень, але вперше як рішення |
| Фінал | ні слова про помсту чи про мережу | обидві мети стоять у кадрі як географія, не як текст |

---

## Відкриті питання до автора

1. **`Ray` чи `Rey`.** У файлі скрізь `Ray`.
2. **`Mum` (№30, брит.) чи `Mom` (амер.).** Решта тексту нейтральна; це єдине слово, що
   видає регіон.
3. **Варіант смерті Дана: A / B / C.** Рекомендую A; C сильніший, але вимагає, щоб стелс у
   сегменті 3 не можна було пропустити.
4. **Варіант фіналу: A / B / C.** Рекомендую A.
5. **Скільки Рей говорить у кат-сценах.** Зараз у нього 7 реплік на весь пролог
   (`Sure.`, `They wrote back.`, `Both of us…`, `Dan —`, і три в сцені з бригадиром). Менше —
   можна; більше — характер розмивається.
