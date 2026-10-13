package com.altama.sonarcube;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabase;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;

class StudentRepositoryTests {

    private EmbeddedDatabase database;
    private StudentRepository repository;

    @BeforeEach
    void setUp() {
        database = new EmbeddedDatabaseBuilder()
                .setType(EmbeddedDatabaseType.H2)
                .addScript("file:db/init.sql")
                .build();
        repository = new StudentRepository(JdbcClient.create(database));
    }

    @AfterEach
    void tearDown() {
        database.shutdown();
    }

    @Test
    void readsAllStudentsOrderedById() {
        List<Student> students = repository.findAll();

        assertEquals(4, students.size());
        assertEquals(new Student(1, "Ani", 95), students.get(0));
        assertEquals(new Student(4, "Dedi", 10), students.get(3));
    }
}
