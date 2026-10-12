package com.altama.sonarcube;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

class GradeServiceTests {

    private final GradeService service = new GradeService();

    @Test
    void mapsScoreToGrade() {
        assertEquals("A", service.grade(95));
        assertEquals("B", service.grade(80));
        assertEquals("C", service.grade(60));
        assertEquals("D", service.grade(10));
    }

    @Test
    void rejectsOutOfRangeScore() {
        assertThrows(IllegalArgumentException.class, () -> service.grade(-1));
        assertThrows(IllegalArgumentException.class, () -> service.grade(101));
    }
}
