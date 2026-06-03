-- テーブル作成
CREATE TABLE IF NOT EXISTS users (
    id      INTEGER PRIMARY KEY,
    name    VARCHAR,
    age     INTEGER,
    city    VARCHAR
);

-- データ挿入
INSERT INTO users VALUES
    (1, '田中太郎', 30, '横浜'),
    (2, '鈴木花子', 25, '東京'),
    (3, '佐藤次郎', 35, '大阪'),
    (4, '山田美咲', 28, '横浜');

-- クエリ実行
SELECT city, count(*) AS 人数, avg(age) AS 平均年齢
FROM users
GROUP BY city
ORDER BY 人数 DESC;
