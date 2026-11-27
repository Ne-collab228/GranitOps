# Версия 2.0 — прогресс (остановлено 25.11.2026 из-за лимита)

Задача пользователя (всё в ОДНУ версию 2.0, % писать в каждом сообщении, время — реальное, без завышения):
1) детализировать здания; 2) Долину расширить «намного больше»; 3) машины (случайные модели, игрок и боты ездят), ботов больше;
4) графика сильно лучше; 5) ещё 2–3 БОЛЬШИЕ карты; 6) (новое) номера целей над объектами + список задач слева + мини-карта и полная карта с игроком.
Поиск по коду — ТОЛЬКО агентами на Haiku (требование пользователя). Бэкап 1.8: C:\Users\user\GranitOps_backup_1.8.
Общий прогресс ≈ 35%.

## Готово
- **Движок больших карт** (scripts/level.gd = база, карты — наследники; Level.MAPS, Level.create(id), `-- --map=N`):
  рельеф кусками с 2 LOD (far_step), кэш TerrainData (scripts/terrain_data.gd, assets/maps/<key>_terrain.res, ключ terrain_key()),
  дальние горы (outer_half), выравнивание дорог (_flatten_roads), сетка расстояний до дорог, невидимая граница (_build_bounds, слой забора),
  навигация кусками (assets/nav/<key>/<i>.res), random_spawn по краю play_half, bench_views() для `-- --bench --viewshot`.
  Печь: `G --headless --path . -- --bake --map=N` (Долина ~45 с).
- **Долина 1,26 км** (scripts/map_valley.gd): база, блокпост, РЛС, + деревня Каменка (восток), колхоз-элеватор (ЮЗ), карьер со складом
  взрывчатки (цель depot, север), высота (ЮВ), сухое русло, дороги, LZ в СВ углу, ~65 врагов. Дома — заглушка `_house` (заменить на Bld).
  BENCH (высокое): среднее 162 draw.
- **Здания** (агент Opus, готово): scripts/bld.gd (класс Bld: house, house2, block, shop, cafe, warehouse, garages, shed, booth, hq, ruin;
  `Bld.<тип>(g, rng, pos, yaw, out, opt)`, вход в +Z, out.cover/fire/doors/inside/roof; строить район в ОДИН Geo). Новые материалы в mats.gd
  (stucco_blue/yellow, slate, roof_red, glass, grime). Превью: scenes/bld_preview.tscn. Грязь на стенах слишком густая — приглушить.
- **Растительность** (агент Opus, готово): scripts/veg.gd (Veg.tree/shrub/grass/multimesh/inst_color, set_wind, set_normals), veg_data.gd,
  атласы assets/veg (19 МБ), превью scenes/veg_preview.tscn. Трава кусками 20–25 м, дальность 45 м. В карты ЕЩЁ НЕ ВСТРОЕНА.
  Добавить scenes/veg_preview.tscn и scenes/bld_preview.tscn, scenes/vehicle_probe.tscn, assets/vehicles/src/* в exclude_filter export_presets.cfg.
- **Машины** (проверены автотестом `--vehtest` на обеих картах; аргументы `--vehai` (без езды игрока), `--vehquick`, `--vehdraw`; в VehicleBody3D положительная engine_force тянет к +Z, поэтому в vehicle.gd она отрицательная): scripts/veh_defs.gd (7 моделей: uaz469, uaz452, pickup, suv, sedan, hatch, van + остов wreck_uaz452),
  scripts/vehicle_model.gd, tools/flatten_vehicles.gd (`G --headless --path . --script res://tools/flatten_vehicles.gd` → assets/vehicles/*.res),
  scripts/vehicle.gd (VehicleBody3D: игрок/ИИ, урон, взрыв, кинематика вдали, высадка экипажа), встроено в player.gd (enter/exit_vehicle,
  камера 3-го лица), mission.gd (подсказка «Сесть»), touch.gd (в машине только «interact»=выйти и пауза), hud.gd, ballistics.gd, fx.gd, enemy.gd,
  main.gd (spawn_enemy, level.spawn_vehicles), level.gd (vehicle_spots/vehicle_patrols/spawn_vehicles/_place_vehicle), map_valley._define_vehicles.
  Модели в игре: uaz469 и uaz452 реалистичные, rgs-набор простой.

## Аэродром (агент остановлен на ~55%)
scripts/map_airfield.gd написан (~1500 строк), рельеф и навигация запечены (assets/maps/airfield_terrain.res, assets/nav/airfield/).
Осталось: скриншоты/BENCH `-- --bench --viewshot --map=1`, урезать ели (9914 шт.), soak-тест, здания на Bld.

## Дальше (по порядку)
1. ~~Автотест машин~~ — готов (`-- --vehtest --map=N`).
2. HUD: номера целей над объектами (проекция, у края — стрелка), список задач слева с номерами и расстоянием, мини-карта (верх-лево, 150 px,
   север вверху) + полная карта по тапу/клавише M; картинка карты печётся при --bake из рельефа/дорог/коробок коллизий → assets/maps/<key>_map.res.
   Антенну (мачта связи на базе) сделать целью в Долине.
3. Встроить Bld в Долину (вместо _house) и в аэродром; встроить Veg (деревья рощами, трава) в базовый _build_nature.
4. Графика: terrain.gdshader (слой травы, палитра), небо/свет, полотно дорог.
5. Ещё 2 карты: «Перевал» (горы, серпантин, деревня, ельник) и «Порт» (город, краны, причалы, вода).
6. Меню выбора карты; CLAUDE.md обновить; ревью агентом Sonnet; поднять версию до 2.0 (versionCode 10); сборка APK.
