package com.altama.sonarcube;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class StudentControllerTests {

    @Test
    void returnsTheStudentsAsJson() throws Exception {
        StudentService service = mock(StudentService.class);
        when(service.findAll()).thenReturn(List.of(new StudentGrade(1, "Ani", 95, "A")));
        MockMvc mvc = MockMvcBuilders.standaloneSetup(new StudentController(service)).build();

        mvc.perform(get("/api/students"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Ani"))
                .andExpect(jsonPath("$[0].grade").value("A"));
    }
}
