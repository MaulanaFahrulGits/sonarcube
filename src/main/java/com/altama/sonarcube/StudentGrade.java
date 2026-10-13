package com.altama.sonarcube;

/** What the API returns: a student with the letter grade of the score. */
public record StudentGrade(long id, String name, int score, String grade) {
}
