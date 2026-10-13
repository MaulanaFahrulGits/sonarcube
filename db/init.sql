-- Schema and sample data. Postgres runs this on first start (docker-compose mounts it into
-- /docker-entrypoint-initdb.d); the unit tests run the same file on H2.
create table if not exists students (
    id    bigint       primary key,
    name  varchar(100) not null,
    score int          not null
);

insert into students (id, name, score) values
    (1, 'Ani', 95),
    (2, 'Budi', 80),
    (3, 'Citra', 60),
    (4, 'Dedi', 10);
