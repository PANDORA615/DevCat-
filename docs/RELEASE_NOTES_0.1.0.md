# DevCat 0.1.0 — первая локальная мастерская

Первый рабочий срез большого ТЗ: русский Flutter Material 3, 16 вводных уроков для 8 языков, отдельный Git-урок, офлайн-генератор задач, редактор, настоящая проверка решений, локальный прогресс и добровольная синхронизация через личный HTTPS WebDAV.

Кот использует канонический исходник. Иконка, иллюстрация и тихие звуки созданы для проекта. Системная/светлая/тёмная тема, свои палитры, reduced motion и управление громкостью доступны в настройках.

## Загрузки

| Система | Пакет |
|---|---|
| Ubuntu 22.04+, Debian 12+, Mint, Pop!_OS | `linux-amd64.deb` |
| Fedora | `linux-fedora-x86_64.rpm` |
| openSUSE | `linux-opensuse-x86_64.rpm` |
| Arch / Manjaro | `linux-x86_64.pkg.tar.zst` |
| Linux glibc ≥2.35 | `linux-x86_64.AppImage` / `tar.gz` |
| Windows 10/11 x64 | `windows-x64-setup.exe` / portable ZIP |
| macOS Intel + Apple Silicon | `macos-universal.dmg` / ZIP |
| Android 7.0+ (API 24) | universal APK либо APK своей ABI: arm64-v8a / armeabi-v7a / x86_64 |
| Android-магазин | AAB; для прямой установки нужен APK |

Полные названия файлов начинаются с `DevCat-0.1.0-`. AppImage требует системные GTK 3, GStreamer и libsecret; при отсутствии FUSE используйте `--appimage-extract-and-run`. Для desktop-языков кроме SQLite установите соответствующий toolchain в PATH. Инструкции в [README](https://github.com/PANDORA615/DevCat-#readme).

## Проверка

Финальный [CI](https://github.com/PANDORA615/DevCat-/actions/runs/40424035892): 15 тестов, Flutter analyze, сборки Linux/Windows/macOS/Android — успешно. Проверены целостность архивов, Windows x64, macOS universal (оба CPU), установка и запуск deb в Linux-контейнере. В нативном UI пройден путь ошибка → подсказка → исправление → успех, тема и код восстановились после перезапуска.

Android APK/AAB подписаны постоянным ключом, APK выровнены для страниц 16 КиБ. SHA-256 сертификата: `F4412CFC2567A7B33248DF99777C0D104761DD2DDA3EE7DE8FE8BAC467098BCA`. Приватный ключ не публикуется. Контрольные суммы файлов — `SHA256SUMS`, публичный сертификат и инвентарь зависимостей приложены.

## Ограничения первого релиза

- Это вводный релиз, а не весь многолетний объём ТЗ. Полные продвинутые курсы, LSP/DAP/PTY, многофайловые проекты, GitHub OAuth/SSH и серверная инфраструктура ещё не реализованы.
- На Android **локально исполняется SQLite**; для остальных языков работают материалы, генератор и редактор, но компиляторы пока не встроены. Код на сервер автоматически не отправляется.
- Помощник составляет параметрические задания из проверяемых шаблонов, без LLM. Git исключён из генерации.
- WebDAV-синхронизация ручная и требует вашего хранилища. Разные черновики сохраняются; это не E2EE.
- Кот пока использует временный idle из исходника. Полный spritesheet/atlas не завершён.
- Windows Authenticode и macOS Developer ID/notarization отсутствуют; возможны системные запросы SmartScreen/Gatekeeper. Магазины не настроены.
- Проверка на реальных устройствах, TalkBack/VoiceOver, аппаратного звука и 60 fps ещё требуется. Код запускается на ПК с правами пользователя, не в защищённой песочнице.

[Подробная матрица поддержки](https://github.com/PANDORA615/DevCat-/blob/main/docs/SUPPORT.md) · [Отчёт проверки](https://github.com/PANDORA615/DevCat-/blob/main/docs/VALIDATION.md) · [План](https://github.com/PANDORA615/DevCat-/blob/main/IMPLEMENTATION_PLAN.md)
