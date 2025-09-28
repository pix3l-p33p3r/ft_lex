Here’s the detailed plan in **Markdown (md) format** to achieve **125/100** for `ft_lex` using Zig:

```markdown
# ft_lex Implementation Plan (Zig)

## Overview
Implement a POSIX-compliant lexer generator (`ft_lex`) in Zig, including bonuses for a 125/100 score.

---

## **Phase 1: Mandatory Part (100/100)**

### **1.1 Project Setup**
- **Language**: Zig (latest stable).
- **Structure**:
  ```bash
  ft_lex/
  ├── src/
  │   ├── main.zig        # Entry point
  │   ├── parser.zig      # Parse .l files
  │   ├── dfa.zig         # NFA/DFA logic
  │   ├── codegen.zig     # Generate lex.yy.c
  │   └── libl/           # POSIX libl implementation
  ├── tests/              # Test .l files
  ├── Makefile            # Compilation
  └── README.md           # Documentation
  ```

### **1.2 Lexer Parser**
- **Input**: `.l` file (regex rules + actions).
- **Tasks**:
  - Tokenize sections (`%{ %}`, `%%`, rules).
  - Parse regex (e.g., `[0-9]+`, `"+"`).
  - Validate actions (e.g., `printf("NUMBER: %s\n", yytext)`).

### **1.3 NFA/DFA Construction**
- **NFA**: Thompson’s algorithm for regex.
- **DFA**: Subset construction + state minimization.
- **Output**: `lex.yy.c` with:
  - DFA state table.
  - `yylex()` function.
  - `libl` functions (`yywrap`, `yymore`).

### **1.4 Testing**
- **Test Cases**:
  - Arithmetic: `42+1337`
  - Parentheses: `(21*19)`
  - Edge cases: Empty input, invalid regex.

---

## **Phase 2: Bonus - Polyglotism (15/100)**
- **Flag**: `--target=zig` to generate Zig code.
- **Tasks**:
  - Modify codegen for Zig output.
  - Ensure actions work in Zig (e.g., `std.debug.print`).

---

## **Phase 3: Bonus - Compression (10/100)**
- **Flag**: `-Cf` to enable compression.
- **Approach**:
  - **Bit-packing**: Compress DFA transitions.
  - **Goal**: ≥2x size reduction (validate with `flex -t lexer.l | wc`).

---

## **Timeline**
| Phase       | Goal                     |
|-------------|--------------------------|
| Parser      | Parse .l files           |
| NFA/DFA     | Regex → DFA              |
| Codegen     | Generate lex.yy.c        |
| Testing     | Validate with test cases |
| Polyglotism | Zig output support       |
| Compression | DFA compression          |

---

## **Resources**
- **POSIX `lex`**: [POSIX.1-2024](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/lex.html)
- **Zig**: [ziglang.org](https://ziglang.org/documentation/master/)

---

## **Validation**
- Compare output with `flex` for correctness.
- Test compression: `flex -t -Cf lexer.l | wc`.

---

## **Next Steps**
1. Start with the parser (Phase 1.2).
2. Prioritize **Zig output** or **compression**? Let me know!
```

### **Key Notes**:
- Use `zig build-exe` for compilation.
- Document all code with `///` comments.

Ready to begin? 🚀