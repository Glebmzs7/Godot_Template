---
type: сцена
status: тест
path: res://Scenes/UIScenes/Home/Home.tscn
extends: Control
depends: []
checked: 2026-09-27
journal: "[[Журнал Сцена Home]]"
---
# Сцена Home

## Назначение
Тестовая сцена-приёмник: проверяет, что [[Сцена Start_Program]] после кнопки «Войти» корректно переключает сцену (`Class_UI.fxC_SwitchingScene_0000("res://Scenes/UIScenes/Home/Home.tscn")`). Отдельной реализации не требует.

## Текущее состояние
Корень — `Control` на весь экран, скрипт `home.gd` с пустым `_ready()`. Прежнее нерабочее содержимое убрано 24.08, его полный текст сохранён в [[Журнал Сцена Home]].

## Связи
- Приходит из: [[Сцена Start_Program]]
- История: [[Журнал Сцена Home]]
