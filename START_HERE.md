# Следующий шаг: Telegram API-реквизиты

Проект находится в приватном репозитории [hhffee/ayupersonal](https://github.com/hhffee/ayupersonal).

1. На [my.telegram.org/apps](https://my.telegram.org/apps) создай приложение: название `Ayu Personal`, short name `ayupersonalclient`, платформа iOS.
2. Открой [GitHub → Actions secrets](https://github.com/hhffee/ayupersonal/settings/secrets/actions).
3. Нажми **New repository secret** и создай:
   - `TELEGRAM_API_ID` — значение поля `App api_id`;
   - `TELEGRAM_API_HASH` — значение поля `App api_hash`.
4. После добавления обоих секретов можно запускать workflow **Build Ayu Personal device IPA** на [странице Actions](https://github.com/hhffee/ayupersonal/actions/workflows/build-ios.yml).

API-реквизиты не записываются в исходники. Сертификат разработчика и пароль от него для облачной сборки не нужны: подпись предполагается выполнить через GBox после сборки.

Наличие workflow ещё не означает, что IPA готов. Сначала должны пройти проверки Swift и полная сборка. Новые функции описаны со статусами в [FEATURES.md](FEATURES.md).
