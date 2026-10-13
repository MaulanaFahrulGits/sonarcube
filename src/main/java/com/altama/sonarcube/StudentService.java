package com.altama.sonarcube;

import java.util.List;

import org.springframework.stereotype.Service;

/** Combines the stored students with their letter grade. */
@Service
public class StudentService {

    private final StudentRepository repository;
    private final GradeService gradeService;

    public StudentService(StudentRepository repository, GradeService gradeService) {
        this.repository = repository;
        this.gradeService = gradeService;
    }

    public List<StudentGrade> findAll() {
        return repository.findAll().stream()
                .map(s -> new StudentGrade(s.id(), s.name(), s.score(), gradeService.grade(s.score())))
                .toList();
    }
}
