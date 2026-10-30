# Источники и устройство новых курсов

В присланных архивах были ссылки на учебники. Для редакции 0.5.0 открыты официальные страницы и выбранные разделы, скачаны справочники GoalKicker и C# Yellow Book. Тексты DevCat заново написаны на русском; исходные книги служат источниками понятий и дополнительного чтения. Сам курс, код, таблицы и иллюстрации работают без открытия внешних ссылок.

| Направление | Основной источник | Дополнительно |
|---|---|---|
| C | [Beej’s Guide to C Programming](https://beej.us/guide/bgc/html/index.html) | [C Notes for Professionals](https://books.goalkicker.com/CBook/CNotesForProfessionals.pdf) |
| C++ | [LearnCpp: variables and functions](https://www.learncpp.com/cpp-tutorial/variable-assignment-and-initialization/) | [CPP Notes for Professionals](https://books.goalkicker.com/CPlusPlusBook/CPlusPlusNotesForProfessionals.pdf) |
| C# | [Rob Miles: C# Yellow Book](https://www.robmiles.com/s/CSharp-Book-2019-Refresh.pdf) | [CSHARP Notes for Professionals](https://books.goalkicker.com/CSharpBook/CSharpNotesForProfessionals.pdf) |
| Python | [Python for Everybody: Variables](https://www.py4e.com/html3/02-variables) | [PYTHON Notes for Professionals](https://books.goalkicker.com/PythonBook/PythonNotesForProfessionals.pdf) |
| Java | [Javanotes: A First Java Program](https://davidjeck.github.io/javanotes/c2/s1.html) | [JAVA Notes for Professionals](https://books.goalkicker.com/JavaBook/JavaNotesForProfessionals.pdf) |
| JavaScript | [Eloquent JavaScript: Program Structure](https://eloquentjavascript.net/02_program_structure.html) | [JAVASCRIPT Notes for Professionals](https://books.goalkicker.com/JavaScriptBook/JavaScriptNotesForProfessionals.pdf) |
| Go | [Go 101 — содержание учебника и выбранные главы](https://go101.org/article/101.html) |  |
| SQL | [SQL Notes for Professionals](https://books.goalkicker.com/SQLBook/SQLNotesForProfessionals.pdf) |  |
| HTML | [MDN: Basic HTML syntax](https://developer.mozilla.org/ru/docs/Learn_web_development/Core/Structuring_content/Basic_HTML_syntax) | [HTML Notes for Professionals](https://books.goalkicker.com/HTML5Book/HTML5NotesForProfessionals.pdf) |
| CSS | [Learn CSS: Box Model](https://web.dev/learn/css/box-model) | [CSS Notes for Professionals](https://books.goalkicker.com/CSSBook/CSSNotesForProfessionals.pdf) |

Для Git/GitHub: [Pro Git](https://git-scm.com/book/ru/v2) и [GitHub Docs](https://docs.github.com/ru/get-started). Дополнительно сверены открытые исходные разделы: [создание репозитория](https://github.com/progit/progit2-ru/blob/master/book/02-git-basics/sections/getting-a-repository.asc), [запись изменений](https://github.com/progit/progit2-ru/blob/master/book/02-git-basics/sections/recording-changes.asc) и [первые действия в GitHub](https://github.com/github/docs/blob/main/content/repositories/creating-and-managing-repositories/quickstart-for-repositories.md).

## Как читать

Каждая тема проходит четыре этапа: объяснение, разобранный пример, небольшой опыт с изменением, самостоятельная работа. Сначала вводится значение слова, затем правило и пример. Служебный каркас первых программ разобран отдельно для каждого языка. Для SQL видны данные и результат; для HTML/CSS показаны конкретный фрагмент, полный набор файлов и реальный браузерный снимок.

Первые 32 занятия семи программных курсов имеют полный исходник с проверяемым результатом. В языке SQL первые восемь опытов не требуют подготовки собственной базы. Автоматических лабораторных по-прежнему 125; их условия и проверки сохранены. У проектных работ явно указан самостоятельный способ проверки.

## Версии

Книги разных лет не описывают одинаковый набор версий. DevCat использует C17, C++20, .NET 8, Python 3, Java 21, Node.js 22, Go и SQLite. Версионные возможности, например virtual threads Java 21, сверяются с актуальной официальной документацией из поля source соответствующего курса. Старые таблицы версий из справочников не выдаются за состояние современной среды.

Первичные URL, дата проверки и SHA-256 скачанных источников: [каталог](../content/reference_sources.json). Сами PDF авторов в APK не включаются. В [офлайн-архиве DevCat](DevCat-lectures.zip) находятся 11 собственных HTML/Markdown-учебников с иллюстрациями и шрифтами.

## Короткие занятия 0.6

Поверх той же подробной теории добавлены 1 548 интерактивных занятий. Краткие определения и вопросы написаны для DevCat; это не выдержки из книг. Новые термины закрепляются выбором, вводом и сборкой записи. Вопросы о результате используют буквальные данные проверяемых программ, а задания на код — настоящий локальный запуск. Подробные исходники и ссылки на учебники остаются в полной лекции. [Правила обучения](STUDY_FORMAT.md).
