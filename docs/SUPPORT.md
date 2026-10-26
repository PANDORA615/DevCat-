# Поддержка 0.1

Это первый вводный релиз из поэтапного ТЗ, а не завершённая промышленная IDE.

| Возможность | Windows / macOS / Linux | Android |
|---|---|---|
| Русский UI, Material 3, системная / светлая / тёмная тема, свой seed HEX | Да | Да |
| Динамическая палитра | При наличии системной поддержки | При наличии системной поддержки |
| 8 языков × 2 вводных урока, справочник | Офлайн | Офлайн |
| Параметрические задания кота для 8 языков | Офлайн | Офлайн |
| Генератор Git/GitHub | Исключён по запросу пользователя | Исключён |
| Редактор одного файла, подсветка, undo, импорт/экспорт | Да | Да |
| Проверка C/C++/C#/Python/Java/JS/Go | Реальные локальные toolchain, нужно установить | NOT_IMPLEMENTED |
| SQLite SELECT/JOIN, два набора данных, лимит времени | Встроен, офлайн | Встроен, офлайн |
| Git init/add/commit/log, проверка HEAD и README | Настоящий Git, нужно установить | Теория; исполнение NOT_IMPLEMENTED |
| Локальный профиль и черновики | Да | Да |
| Ручная WebDAV-синхронизация прогресса и черновиков | HTTPS, личное хранилище | HTTPS, то же хранилище |
| Синхронизация файловых проектов / аккаунт / фоновые push | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Тихие оригинальные звуки касаний и результата | Да; нужны аудиосервисы ОС | Да |
| Reduced motion, масштаб текста системы | Да; проверка скринридеров вручную ещё нужна | Да; проверка TalkBack вручную ещё нужна |
| Канонический кот | Временный idle из исходника, набор спрайтов NOT_IMPLEMENTED | Аналогично |
| LSP, DAP, PTY, многофайловые сборки, NuGet/npm UI, SSH, OAuth | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| Полные профессиональные курсы и все версии языков | NOT_IMPLEMENTED | NOT_IMPLEMENTED |

## ОС и пакеты

- Linux x86_64: Ubuntu 22.04+, Debian 12+, актуальные Fedora/openSUSE/Arch с glibc ≥ 2.35. `deb`, `rpm`, Arch `pkg.tar.zst`, `AppImage`, `tar.gz`. GTK 3, libsecret и GStreamer — зависимости ОС, в том числе для AppImage; musl/Alpine и ARM Linux не заявлены.
- Windows x64: Windows 10/11, portable ZIP и setup EXE. Для Flutter и плагинов может понадобиться Microsoft Visual C++ Redistributable 2015–2022 x64. Authenticode не настроен.
- macOS: сборка Flutter Release, DMG и ZIP; архитектуры подтверждаются `lipo` в проверке релиза. Developer ID / notarization не настроены, поэтому Gatekeeper может потребовать ручное открытие через системные настройки.
- Android: APK universal + arm64-v8a + armeabi-v7a + x86_64 и AAB. APK для прямой установки; AAB предназначен для магазина, а не установки касанием. Фактический minimum SDK задаёт Flutter/плагины. Магазин Google Play не настроен.

Сборка пакета не доказывает проверку на реальном устройстве. Фактические результаты: [VALIDATION.md](VALIDATION.md).

## Toolchain

| Язык | Требование |
|---|---|
| C / C++ | Clang или GCC в PATH, C17 / C++20 |
| C# | .NET 8 SDK, а не только runtime |
| Python | CPython 3 в PATH |
| Java | JDK 21 с `java` и `javac` в PATH |
| JavaScript | Node.js LTS |
| Go | Go 1.22+ в PATH, без скачивания модулей |
| Git | Git 2 в PATH |

Компиляторы не входят в установщики. C# собирает только локальный проект без NuGet-источников. Go использует `GOPROXY=off`, `GOTOOLCHAIN=local`. Перед запуском локального кода пользователь даёт согласие. Это процесс с его правами, не sandbox. Не запускайте сторонний код как недоверенные серверные задания.
