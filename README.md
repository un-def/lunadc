lunadc
======

Автономный (не зависящий от DC-клиентов/библиотек) бот для NMDC-хабов. Выводит сообщения главного чата в stdout и пересылает их удалённому логгеру по http (основная, но отключаемая функция).

Настраивается редактированием файла config.lua (описание опций ниже). Делает одну попытку коннекта, при ошибках не реконнектится и завершает работу с exit status 1. Для автоматического переподключения при ошибках можно запускать через shell: `while true; do lua ./lunadc.lua; sleep 10; done`

Протестирован на Lua 5.1.5 (Ubuntu, OpenWrt) и 5.2.3 (Windows).

### Зависимости

* [LuaSocket](http://w3.impa.br/~diego/software/luasocket/) (тестировалось с версией 3.0rc1)

### Замечание о типах сообщений

Все выводимые скриптом сообщения делятся на информационные (info) сообщения и сообщения чата (chat). Сообщения чата — это все сообщения от хаба вида ‘\<nick\> [text]’, отправляемые после $Hello (т.е. после успешного входа на хаб). Информационные сообщения — все сообщения, выводимые самим скриптом (приветствие, ошибки, и т.д.) и сообщения хаба, отправляемые до $Hello (обычно это информация о версии хаба, плагинах, сообщения об ошибках).

По http логгируются (если логгирование не отключено) только сообщения чата. Игнорирование пользователей также работает только c сообщениями чата (т.е. если, например, игнорируется ник VerliHub, то сообщения от него в процессе входа на хаб (например, ‘\<VerliHub\> This hub is running version …’) всё равно будут выводиться на экран, но никогда не будут отправляться по http, поскольку информационные сообщения не логгируются по http).

Вывод на экран (в stdout) сообщений можно отключить по отдельности соответствующими опциями конфига ‘cfg.hide_info_msg’ и ‘cfg.hide_chat_msg’. Опции ‘cfg.hide_chat_msg’ и ‘cfg.logger’ (вывод на экран и отправка сообщений чата логгеру по http соответственно) не влияют друг на друга. Опция ‘cfg.ignore’ оказывает действие и на вывод на экран, и на логгирование по http.

### Опции конфига (файл config.lua)

* cfg.**host** = "*хост*" — обязательный параметр; адрес хаба.
* cfg.**port** = *порт* — обязательный параметр; порт хаба (обычно 411).
* cfg.**nick** = "*ник*" — обязательный параметр; ник для бота.
* cfg.**pass** = "*пароль*" — пароль, если ник бота зарегистрирован.
* cfg.**slots** = *количество_слотов* — количество слотов (фиктивные данные). По умолчанию 10.
* cfg.**share** = *размер\_в\_байтах* — размер шары (фиктивные данные). По умолчанию 0. Как и количество слотов, эта опция используется для обхода ограничений на вход по слотам/шаре.
* cfg.**desc** = "*текст*" — описание бота (часть $MyINFO).
* cfg.**email** = "*e-mail*" — адрес почты (часть $MyINFO).
* cfg.**timeout** = *таймаут\_в\_секундах* — таймаут чтения из сокета. По умолчанию 180 секунд.
* cfg.**ignore** = {*таблица ["игнорируемый_ник"] = true*,… } — список игнорируемых пользователей. Меняя true на false, можно отключать игнорирование отдельного пользователя. Для отключения функции игнорирования удалите эту опцию или укажите cfg.ignore = false.
* cfg.**logger** = {*таблица ["url_логгера"] = "токен",…*} — список удалённых логгеров, которым будут отправляться сообщения чата. Данные отправляются POST-запросом (тип данных ‘application/x-www-form-urlencoded’). Токен может использоваться для примитивной аутентификации, для идентификации логгера из нескольких, и т.п. Для отключения логгирования по http удалите эту опцию или укажите cfg.logger = false.
* cfg.**hide_info_msg** = *false или true* — отключить вывод информационных сообщений. По умолчанию false.
* cfg.**hide_chat_msg** = *false или true* — отключить вывод сообщений чата. По умолчанию false.
* cfg.**timestamp** = "*формат*" — формат временной метки выводимых сообщений. По умолчанию "[%d-%m-%Y %H:%M:%S]" (см. os.date()).
* cfg.**control_nick** = "*ник*" — ник пользователя, который может управлять ботом. Управление осуществляется отправкой боту личного сообщения с командой. Команда одна — ‘!die’ (без кавычек и пробелов; завершает работу скрипта). Для отключения управления удалите эту опцию или укажите cfg.control_nick = false.

Любую опцию можно отключить, закомментировав её с помощью ‘--’ в начале строки; многострочные комментарии — ‘--[[*закомментированный фрагмент*]]’ (стандартные комментарии в Lua).

### http-логгер

При получении нового сообщения чата скрипт отправляет всем удалённым логгерам, указанным в опции ‘cfg.logger’ ({*["logger1_url"] = "logger1_token", ["logger2_url"] = "logger2_token",…*}), POST-запросы (application/x-www-form-urlencoded) следующего содержания:

time=**unix_time**&user=**ник**&message=**текст_сообщения**&me=**0_или_1**&token=**токен**

* time — UNIX-время получения сообщения.
* me — 0 или 1. 0 — обычное сообщение; 1 — ‘/me’-сообщение (распознаются сообщения вида ‘\<ник\> /me текст’ и ‘\* ник текст’ (с произвольным количеством ‘\*’ и необязательным пробелом после них)).
* user, message — “percent-encoded” (т.е. user=urlencode("ник")). В той же кодировке, в которой были получены от хаба.
* token — “percent-encoded”. Логгер может не проверять его, но отсылаться он будет всегда.

Пример http-логгера — [lunalogger](https://github.com/un-def/lunalogger).
