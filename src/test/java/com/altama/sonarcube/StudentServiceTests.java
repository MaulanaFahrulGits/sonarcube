package com.altama.sonarcube;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;

import org.junit.jupiter.api.Test;

class StudentServiceTests {

    @Test
    void addsTheLetterGradeToEachStudent() {
        StudentRepository repository = mock(StudentRepository.class);
        when(repository.findAll()).thenReturn(List.of(new Student(1, "Ani", 95), new Student(2, "Dedi", 10)));
        StudentService service = new StudentService(repository, new GradeService());

        List<StudentGrade> result = service.findAll();

        assertEquals(List.of(new StudentGrade(1, "Ani", 95, "A"), new StudentGrade(2, "Dedi", 10, "D")), result);
    }
}
