# Сборки и подпись

Workflow `build.yml` создаёт проверенные desktop-пакеты и Android build inputs. Публикация выполняется отдельно после проверки; не выкладывайте debug-signed Android inputs под видом production APK.

## Android

Текущий релиз подписывается постоянным RSA-4096 ключом `devcat`, хранимым вне git. Ключ и пароль должны остаться у владельца: без того же ключа нельзя установить обновление поверх APK. Резервная копия передаётся владельцу отдельно и не входит в GitHub Release.

Для следующих CI-сборок владелец может добавить Secrets:

- `ANDROID_KEYSTORE_BASE64`: base64 файла JKS, alias `devcat`.
- `ANDROID_STORE_PASSWORD`: пароль JKS.
- `ANDROID_KEY_PASSWORD`: пароль ключа.

Текущая интеграция GitHub не имеет доступа к Actions Secrets (HTTP 403), поэтому они не создаются автоматически. Скрипт `android_signing_config.py` читает их без вывода значений; Gradle использует окружение. Не фиксируйте `release.jks`, `key.properties`, `owner-signing.enabled` или пароли в git.

При отсутствии Secrets inputs подписываются временным debug-ключом среды и требуют переподписи постоянным ключом вне CI: APK — `apksigner`, AAB — `jarsigner`. Затем проверьте `apksigner verify --print-certs` и `jarsigner -verify`. Сертификат должен совпадать для universal APK и всех ABI. AAB не заменяет APK для прямой установки.

## Desktop

Windows: Inno Setup installer и ZIP x64; Authenticode NOT_CONFIGURED. macOS: ZIP и DMG, ad hoc codesign; Developer ID/notarization NOT_CONFIGURED. Для магазинной или доверенной коммерческой поставки владелец должен предоставить свои сертификаты через секретное хранилище, не в репозиторий.

Linux: сборка на Ubuntu 22.04 для glibc ≥2.35. Deb/RPM/Arch metadata включают runtime dependencies. AppImage содержит приложение и Flutter, но требует системные GTK 3, GStreamer, libsecret; это явно указано в README.

## Проверка перед публикацией

1. Успешны analyze/test и сборки каждого выпускаемого пакета.
2. В артефактах нет ключей, локальных данных пользователя, паролей и debug Android inputs.
3. Составить SHA256SUMS по фактическим файлам.
4. Опубликовать prerelease с точными ограничениями и ссылкой на validation report.
5. Не называть CI-сборку проверкой на реальных Windows/macOS/Android устройствах.

Публичный сертификат текущего Android-ключа: [android-release-cert.pem](android-release-cert.pem). SHA-256: `F4412CFC2567A7B33248DF99777C0D104761DD2DDA3EE7DE8FE8BAC467098BCA`.

Для локальной переподписи: `python3 scripts/sign_android.py INPUTS OUTPUT --keystore /private/devcat.jks --password-file /private/password.txt --build-tools /path/to/android/build-tools/36.0.0`. Скрипт выравнивает APK для страниц 16 КиБ, проверяет подпись и не выводит пароли.

## Публикация 0.1 из managed environment

Текущая учётная запись среды позволяет Git/API, но отклоняется `uploads.github.com`. Публикацию выполняет отдельный `publish.yml` с минимальными `contents: write` и `actions: read` в GitHub Actions. Native-пакеты берутся из зафиксированного успешного build run. Уже подписанные Android-файлы переданы небольшими **публичными бинарными Git blobs без включения в дерево исходников**; manifest содержит только SHA и размеры. Это временный транспорт для открытых установщиков, не хранение ключей. Обычный clone не включает эти бинарные объекты в историю файлов.

Publisher проверяет исходный commit, успешность CI и все SHA256SUMS до загрузки. Приватный keystore и пароли в Actions не передаются. Для будущих версий предпочтительна настройка owner signing Secrets и обычная публикация из CI; staging manifest относится к 0.1.0.
