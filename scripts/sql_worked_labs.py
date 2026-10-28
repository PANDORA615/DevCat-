"""Executed DDL/DML scenarios for the database-design portion of the book."""
import json
import sqlite3
from lecture_depth import sql_fixture

LABS = {
'schema': ('Книга и отдельный экземпляр',
 'Книга как произведение и физический экземпляр — разные сущности. Две копии одной книги имеют общий book_id, но разные собственные id. Поэтому выдача одного экземпляра не должна делать недоступными все остальные. Сначала проверь такую возможность на нескольких строках, а затем добавляй историю операций. Внешний ключ выражает связь; включённая проверка ссылок не разрешает экземпляр несуществующей книги. После каждой команды прочитай конкретное состояние, а не только сообщение об успешном выполнении.',
 'PRAGMA foreign_keys=ON; CREATE TABLE books(id INTEGER PRIMARY KEY,title TEXT NOT NULL); CREATE TABLE copies(id INTEGER PRIMARY KEY,book_id INTEGER NOT NULL REFERENCES books(id)); INSERT INTO books VALUES(1,\'Основы SQL\');',
 [("INSERT INTO copies VALUES(10,1)",False,None),("INSERT INTO copies VALUES(11,1)",False,None),("INSERT INTO copies VALUES(12,999)",True,None)],
 'SELECT c.id,b.title FROM copies c JOIN books b ON b.id=c.book_id ORDER BY c.id'),
'constraints': ('Отказ ограничения не повреждает прежние записи',
 'В примере цена хранится целым числом копеек и не может быть отрицательной. Попытка добавить −5 должна завершиться отказом, а не преобразоваться в ноль. Следующая корректная вставка подтверждает, что база остаётся пригодной к работе. Отдельно проверь NULL и повтор id: это другие ограничения. Сообщение базы является диагностикой причины, а интерфейс приложения должен показать понятное предметное объяснение, сохранив исходную информацию для разработки.',
 'CREATE TABLE products(id INTEGER PRIMARY KEY, price_cents INTEGER NOT NULL CHECK(price_cents>=0)); INSERT INTO products VALUES(1,100);',
 [('INSERT INTO products VALUES(2,-5)',True,None),('INSERT INTO products VALUES(2,0)',False,None)],
 'SELECT id,price_cents FROM products ORDER BY id'),
'normalization': ('Одно переименование без рассогласованных копий',
 'Имя покупателя хранится один раз в customers, а заказы ссылаются на id. Переименование одной строки меняет представление всех связанных заказов при следующем запросе, не требуя переписывать имя внутри каждого заказа. Это устраняет конкретную аномалию обновления. Убедись, что меняется только представление имени, а число заказов, их суммы и идентификаторы сохраняются. Затем объясни, какие зависимости были бы скрыты в ненормализованной общей таблице.',
 sql_fixture(), [("UPDATE customers SET name='Анна' WHERE id=1",False,None)],
 'SELECT o.id,c.id,c.name,o.amount FROM orders o JOIN customers c ON c.id=o.customer_id ORDER BY o.id'),
'insert': ('Значение с апострофом через параметр',
 'Значение передаётся отдельно от SQL. Знак ? является местом параметра клиентского API, а не готовым значением для ручного запуска. Ниже показаны текст операции и значения; приложение связывает их через библиотеку. Имя с апострофом остаётся обычными данными, структура команды не меняется. Для самостоятельной проверки используй выбранный язык клиента и никогда не превращай параметризацию обратно в конкатенацию текста.',
 'CREATE TABLE customers(id INTEGER PRIMARY KEY,name TEXT NOT NULL);',
 [('INSERT INTO customers(id,name) VALUES(?,?)',False,(4,"O'Brien"))],
 'SELECT id,name FROM customers ORDER BY id'),
'update': ('Изменение ровно выбранной записи',
 'Первое действие меняет цену id=1, второе удаляет id=2. Условия выражают устойчивую идентичность, а не позицию результата или название. До выполнения каждого действия выпиши ожидаемые затронутые строки. После — проверь реальную модель. Если запись не найдена, приложение должно обработать этот исход, а не безусловно утверждать, что сохранение произошло. Для конкурентного изменения можно добавить ожидаемый номер версии к WHERE.',
 'CREATE TABLE products(id INTEGER PRIMARY KEY,price_cents INTEGER NOT NULL); INSERT INTO products VALUES(1,100),(2,200);',
 [('UPDATE products SET price_cents=150 WHERE id=1',False,None),('DELETE FROM products WHERE id=2',False,None)],
 'SELECT id,price_cents FROM products ORDER BY id'),
 'transactions': ('Откат незавершённого перевода',
 'Сначала списываются 20 единиц со счёта A и зачисляются на B. Внутри транзакции промежуточные значения уже существуют для самой операции. Затем выполняется ROLLBACK, и итоговое чтение должно вернуть исходные 100 и 30. Это отдельная проверка от успешного COMMIT. Общая сумма 130 является полезным инвариантом, но одной её недостаточно: ошибочный перевод в обратную сторону тоже мог бы сохранить сумму.',
 "CREATE TABLE accounts(id TEXT PRIMARY KEY,balance INTEGER NOT NULL CHECK(balance>=0)); INSERT INTO accounts VALUES('A',100),('B',30);",
 [('BEGIN',False,None),("UPDATE accounts SET balance=balance-20 WHERE id='A'",False,None),("UPDATE accounts SET balance=balance+20 WHERE id='B'",False,None),('ROLLBACK',False,None)],
 'SELECT id,balance FROM accounts ORDER BY id'),
'isolation': ('Составное действие и выражение обновления',
 'Два последовательных увеличения через value=value+1 дают 12 из начального 10. Этот односоединительный опыт показывает контракт выражения, но сам по себе не доказывает поведение двух конкурентных соединений. Для конкурентного эксперимента распиши отдельно чтение и запись обоих клиентов: два чтения 10 и две записи 11 демонстрируют потерянное обновление. Затем исследуй транзакцию или контроль версии именно выбранной СУБД, а не переноси результат этого простого примера на все уровни изоляции.',
 'CREATE TABLE counters(id INTEGER PRIMARY KEY,value INTEGER NOT NULL); INSERT INTO counters VALUES(1,10);',
 [('UPDATE counters SET value=value+1 WHERE id=1',False,None),('UPDATE counters SET value=value+1 WHERE id=1',False,None)],
 'SELECT id,value FROM counters'),
'indexes': ('Создание и независимая проверка индекса',
 'Индекс создаётся по customer_id и amount. Итоговая проверка метаданных подтверждает существование именно нужной структуры, а не наличие случайного другого индекса. После этого исследуй запрос по покупателю с сортировкой по сумме через EXPLAIN QUERY PLAN. На трёх строках нельзя делать убедительный вывод об ускорении: подготовь больший объём и подходящее распределение, отдельно измерив вставки. Удаление индекса должно менять способ доступа, но не смысл результата правильного SELECT.',
 sql_fixture(), [('CREATE INDEX orders_customer_amount ON orders(customer_id,amount)',False,None)],
 "SELECT name,tbl_name FROM sqlite_master WHERE type='index' AND name='orders_customer_amount' ORDER BY name"),
'plan': ('От результата к способу его получения',
 'Сначала проверь сам результат запроса для customer_id=1: суммы упорядочены, а id не потеряны. Затем выполни EXPLAIN QUERY PLAN перед тем же SELECT и прочитай выбранный доступ. Текст плана зависит от версии SQLite и не является долговременным пользовательским форматом. Сравни результаты до и после добавления индекса, а измерения проводи отдельно от подготовки данных. Усложнение — сделать условие менее избирательным и объяснить разумность полного просмотра.',
 sql_fixture(), [('CREATE INDEX orders_customer_amount ON orders(customer_id,amount)',False,None)],
 'SELECT id,amount FROM orders WHERE customer_id=1 ORDER BY amount,id'),
'security': ('Точное имя остаётся значением',
 'Запрос ниже использует параметр для имени с апострофом. Структура SELECT постоянна, поэтому содержимое значения не превращается в часть команды. Это не отменяет ограничение размера имени и правила предметного поиска, но отделяет данные от синтаксиса. Для ручного эксперимента в IDE можно использовать безопасный фиксированный литерал, а в клиентском приложении нужно сохранять связывание параметра библиотекой. Сортировочные имена и другие части синтаксиса выбираются из контролируемого набора отдельно.',
 "CREATE TABLE customers(id INTEGER PRIMARY KEY,name TEXT NOT NULL); INSERT INTO customers VALUES(1,'O''Brien'),(2,'Аня');",
 [('SELECT id,name FROM customers WHERE name=?',False,("O'Brien",))],
 'SELECT id,name FROM customers ORDER BY id'),
'migration': ('Новая колонка сохраняет смысл старой записи',
 'В исходной схеме у заметки есть id и title. Миграция добавляет archived с явным значением по умолчанию 0 и сохраняет старый id. После изменения нужно проверить и схему, и данные, а затем записать номер версии по принятому протоколу. Одного ALTER TABLE недостаточно для описания поведения при отказе и повторном запуске. Подготовь старую копию и проверь весь переход в отдельной базе, не на единственном рабочем файле пользователя.',
 "CREATE TABLE notes(id INTEGER PRIMARY KEY,title TEXT NOT NULL); INSERT INTO notes VALUES(1,'Первая');",
 [('ALTER TABLE notes ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',False,None),('PRAGMA user_version=2',False,None)],
 'SELECT id,title,archived FROM notes ORDER BY id'),
'project': ('Независимая сверка аналитического отчёта',
 'На основном наборе Аня имеет заказы 10 и 25, Борис — 40, Вера — ни одного. Индивидуальные итоги равны 35,40,0, а общий итог — 75. Соединение предварительно агрегированных заказов сохраняет одну строку на покупателя. Проверка суммы групп полезна, но дополнительно проверь каждого покупателя, иначе неверное перераспределение могло бы оставить общую сумму прежней. Добавь второго покупателя с тем же именем и убедись, что id продолжает различать сущности.',
 sql_fixture(), [],
 'WITH totals AS (SELECT customer_id,SUM(amount) AS total FROM orders GROUP BY customer_id) SELECT c.id,c.name,COALESCE(t.total,0) AS total FROM customers c LEFT JOIN totals t ON t.customer_id=c.id ORDER BY total DESC,c.id'),
'graduation': ('Нельзя выдать один экземпляр дважды',
 'Частичный уникальный индекс разрешает только одну активную выдачу одного copy_id. Возвращённая запись остаётся в истории, но перестаёт участвовать в индексе. Поэтому после возврата разрешена новая выдача того же экземпляра, а первая запись не уничтожается. Это конкретное правило модели, а не просто наличие таблицы loans. Проверь отказ второй активной выдачи, затем возврат и новую допустимую операцию; после каждого шага история должна оставаться согласованной.',
 "CREATE TABLE loans(id INTEGER PRIMARY KEY,copy_id INTEGER NOT NULL,reader_id INTEGER NOT NULL,returned_at TEXT); CREATE UNIQUE INDEX one_active_copy ON loans(copy_id) WHERE returned_at IS NULL; INSERT INTO loans VALUES(1,10,7,NULL);",
 [('INSERT INTO loans VALUES(2,10,8,NULL)',True,None),("UPDATE loans SET returned_at='2026-10-28' WHERE id=1",False,None),('INSERT INTO loans VALUES(2,10,8,NULL)',False,None)],
 'SELECT id,copy_id,reader_id,returned_at FROM loans ORDER BY id'),
}


def sections(slug):
    title,notes,setup,steps,inspection=LABS[slug]
    db=sqlite3.connect(':memory:',isolation_level=None);db.executescript(setup)
    history=[]
    for statement,expected_error,parameters in steps:
        try:
            cursor=db.execute(statement,parameters or ())
            if expected_error:raise AssertionError('Expected a constraint failure: '+slug)
            if cursor.description:detail='; '.join(' | '.join(map(str,row)) for row in cursor.fetchall())
            else:detail='Операция выполнена'
        except sqlite3.IntegrityError:
            if not expected_error:raise
            detail='Ожидаемый отказ ограничения; прежние данные сохранены'
        history.append([statement, json.dumps(parameters,ensure_ascii=False) if parameters else '—',detail])
    cursor=db.execute(inspection);rows=cursor.fetchall();columns=[c[0] for c in cursor.description];db.close()
    return [{'heading':'Полный практический сценарий: '+title,'text':notes+'\n\nКоманды выполняются в собственной базе. Связанный сценарий BEGIN … COMMIT или ROLLBACK вставляй целиком в один запуск IDE; соединение не переносит открытую транзакцию в следующий запуск. Намеренно ошибочные операции для изучения ограничений проверяй по отдельности. Операции с ? требуют связывания параметров через клиентскую библиотеку; столбец параметров показывает передаваемые значения. Этот сценарий реально исполняется SQLite при сборке учебника.','code':setup},
        {'heading':'Действия и наблюдаемые исходы','text':'Ошибка, специально ожидаемая в таблице, является проверкой защиты инварианта. Остальные операции после неё должны оставаться работоспособными. Не выполняй такой эксперимент на единственной рабочей базе.','table':{'columns':['Оператор','Параметры','Исход'],'rows':history}},
        {'heading':'Проверка итогового состояния','text':'Запрос ниже проверяет результат после описанных действий. Сверь не только число строк, но и устойчивые id, значения и сохранность истории.','code':inspection,'table':{'columns':columns,'rows':[['NULL' if v is None else str(v) for v in row] for row in rows]}}]
