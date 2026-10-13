package com.altama.sonarcube;

import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Reads students from the database. */
@Repository
public class StudentRepository {

    private final JdbcClient jdbc;

    public StudentRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public List<Student> findAll() {
        return jdbc.sql("select id, name, score from students order by id")
                .query((rs, rowNum) -> new Student(rs.getLong("id"), rs.getString("name"), rs.getInt("score")))
                .list();
    }
}
