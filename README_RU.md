<p align="center"><a href="README.md">English</a> · <a href="README_RU.md">Русский</a></p>

<img src="assets/readme/hero.svg" alt="Jerkgram — Telegram, with more control." width="100%">

<p align="center">
  <a href="https://jerkgram.github.io/"><strong>Сайт</strong></a> ·
  <a href="https://github.com/jerkgram/Jerkgram-iOS/releases"><strong>Релизы</strong></a> ·
  <a href="https://t.me/JerkgramApp"><strong>Stable-канал</strong></a> ·
  <a href="https://t.me/JerkgramCommunity"><strong>Сообщество</strong></a> ·
  <a href="docs/SOURCE_TRANSPARENCY.md"><strong>Прозрачность исходников</strong></a>
</p>

# Jerkgram

**Jerkgram — независимый альтернативный Telegram-клиент для iOS с упором на восстановление, контекст сообщений, кастомизацию и дополнительный контроль.**

Он сохраняет нативный опыт Telegram для iOS как основу и добавляет недостающий слой: **что изменилось, что исчезло и что всё ещё относится к разговору.**

> [!NOTE]
> Сейчас Jerkgram готовит первый Stable-релиз с публичными исходниками. SHA-256 IPA и source tag намеренно не публикуются до появления окончательного Stable-артефакта.

## Контекст остаётся

Jerkgram строится вокруг простой идеи: удаление или изменение на сервере не всегда должно стирать весь контекст, который клиент уже успел локально увидеть.

- **Восстановление удалённых сообщений** — сохранение поддерживаемого контекста, который Jerkgram уже получил.
- **История правок** — просмотр ранее наблюдавшихся состояний изменённого сообщения.
- **Ответы на восстановленные сообщения** — сохранение полезного контекста цитаты.
- **Восстановленное медиа** — сохранение поддерживаемых уже загруженных медиа и контекста вокруг них.
- **Time Machine** — единое место для просмотра изменений и восстановленной истории.
- **Контроль приватности** — дополнительные настройки read / typing / presence поведения.
- **Расширенные инструменты** — транскрибация, профиль, медиа и другие power-user возможности поверх нативной архитектуры Telegram.

Набор функций зависит от конкретного релиза. Source tag и release notes Stable-версии являются авторитетным описанием именно этой версии.

## Основан на Official Telegram for iOS

```text
Upstream repository   TelegramMessenger/Telegram-iOS
Upstream tag          release-12.9.2
Upstream commit       6ad963e5b62d354da79040f388ae2b9132fb17b8
```

Jerkgram — независимый проект и **не является официальным приложением Telegram**. Для него предполагаются собственные Telegram API credentials и собственная application/signing identity.

Подробнее: [`UPSTREAM.md`](UPSTREAM.md).

## Посмотреть Jerkgram вживую

На [сайте Jerkgram](https://jerkgram.github.io/) находятся актуальная продуктовая история и реальные интерфейсные captures, включая before/after восстановление. В самом репозитории мы не подменяем их искусственными скриншотами, которые могут разойтись с будущим Stable UI.

## Прозрачность исходников

<img src="assets/readme/provenance.svg" alt="Связь Official Telegram, точного исходного дерева Jerkgram, Stable IPA и публичного snapshot исходников." width="100%">

Для каждого Stable-релиза должно быть однозначно понятно:

> **Какой именно публичный snapshot исходников соответствует этой конкретной выпущенной IPA?**

Stable release record связывает:

```text
Версию Jerkgram
Public source tag
Telegram upstream tag + commit
SHA-256 Stable IPA
SHA-256 source snapshot
Source manifest
```

Публичный репозиторий содержит **реальный финальный production source**, соответствующий Stable-релизам, а не вручную переписанную красивую копию проекта.

<img src="assets/readme/integrity.svg" alt="Принципы исходников: точное соответствие, проверенный экспорт и привязка к релизу." width="100%">

Полный контракт: [`docs/SOURCE_TRANSPARENCY.md`](docs/SOURCE_TRANSPARENCY.md).

## Релизы

Stable-релизы распространяются через **[GitHub Releases](https://github.com/jerkgram/Jerkgram-iOS/releases)** и **[@JerkgramApp](https://t.me/JerkgramApp)**.

Страница конкретного Stable-релиза на GitHub является канонической страницей этой версии и предназначена для IPA, release notes, данных о соответствии релиза исходникам и ссылок на соответствующий public source.

Кнопка **Download IPA** на сайте Jerkgram может вести напрямую на IPA asset соответствующего GitHub Release, а **View on GitHub** — на полную страницу релиза.

**AltStore Classic** и **SideStore** используют единый официальный AltStore source Jerkgram: [`https://jerkgram.github.io/altstore-source.json`](https://jerkgram.github.io/altstore-source.json). Этот JSON содержит только metadata: обе системы устанавливают и обновляют тот же canonical IPA из GitHub Release, отдельного Jerkgram JSON для SideStore нет.

Beta-тестирование, баг-репорты и обратная связь: [@JerkgramCommunity](https://t.me/JerkgramCommunity).

Подробнее о связи релиза и исходников: [`docs/RELEASES.md`](docs/RELEASES.md).

## Сборка из исходников

Первый Stable snapshot исходников получит build-инструкцию, проверенную именно против этого release tree.

Публичный source не должен содержать личные сертификаты подписи, provisioning profiles, private keys, пользовательские сессии, токены или private signing identities. Сборщик предоставляет свои:

- Telegram `api_id` / `api_hash`;
- Apple signing identity;
- provisioning и bundle configuration.

Подробнее: [`docs/BUILDING.md`](docs/BUILDING.md).

## Вклад и поддержка

- Баги и воспроизводимые runtime-проблемы: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Security-sensitive вопросы: [`SECURITY.md`](SECURITY.md)
- Поддержка проекта: [`SUPPORT.md`](SUPPORT.md)
- Сообщество: [@JerkgramCommunity](https://t.me/JerkgramCommunity)

## Лицензия

Jerkgram основан на Telegram for iOS и распространяется по **GNU General Public License, version 2 or later**, с учётом лицензий включённых сторонних компонентов.

См. [`LICENSE`](LICENSE), [`UPSTREAM.md`](UPSTREAM.md) и [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Jerkgram — независимый проект, не связанный с Telegram, не одобренный и не выпускаемый Telegram. Telegram является товарным знаком соответствующего правообладателя.

---

<p align="center"><strong>Jerkgram</strong><br><sub>Telegram, with more control.</sub></p>
