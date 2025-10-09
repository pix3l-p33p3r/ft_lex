# ft_lex: A POSIX Lexical Analyzer Generator

**ft_lex** is a robust and feature-complete implementation of the standard `lex` utility, developed in compliance with the POSIX.1-2024 standard. This project, created as part of the 1337 curriculum, takes a lexer definition file (`.l`) and generates highly optimized C source code for a lexical analyzer. The project also includes bonus features such as multi-language code generation (Zig) and advanced DFA compression.

---

## Table of Contents

* [About The Project](#about-the-project)
* [Core Features](#core-features)
    * [Full POSIX Compliance](#full-posix-compliance)
    * [Internal Architecture](#internal-architecture)
    * [Bonus Implementations](#bonus-implementations)
* [Getting Started](#getting-started)
    * [Prerequisites](#prerequisites)
    * [Installation](#installation)
* [Usage](#usage)
    * [Generating a Scanner](#generating-a-scanner)
    * [Command-Line Options](#command-line-options)
* [Performance Considerations](#performance-considerations)
* [Project Status](#project-status)
* [References and Acknowledgments](#references-and-acknowledgments)

---

## About The Project

The `lex` utility is a foundational tool in compiler construction, responsible for the first phase of compilation: lexical analysis. It converts a stream of input characters into a sequence of tokens based on a set of rules defined by regular expressions.

This project is a from-scratch implementation that handles the entire pipeline:

1.  Parsing a `.l` file containing lexer rules.
2.  Constructing a finite automaton from the regular expressions.
3.  Generating a C source file (`lex.yy.c`) that contains a state machine capable of executing the lexical analysis.

The entire generator is written in Zig, chosen for its performance, safety, and control over memory, while the output C code is designed to be portable and efficient, using only a minimal set of standard library functions.

---

## Core Features

### Full POSIX Compliance

`ft_lex` adheres strictly to the POSIX.1-2024 specification, implementing all standard features required for a `lex` utility.

* **Extended Regular Expressions (ERE):** Full support for the POSIX ERE syntax in rule definitions.
* **Standard Library (`libl`):** Provides the complete `libl` library with all required functions and external variables, such as `yyin`, `yyout`, `yytext`, `yyleng`, and `yylineno`.
* **Scanner Control Functions:** Full implementation of `input()`, `unput()`, `yywrap()`, `yymore()`, and `yyless()` for fine-grained control over the input stream.
* **Start Conditions:** Supports both inclusive (`%s`) and exclusive (`%x`) start conditions using the `BEGIN` macro.
* **Context Sensitivity:** Implements trailing context using the `/` operator and line anchoring with `^` and `$`.
* **Action Keywords:** Full support for advanced action control, including the `REJECT` keyword to match subsequent rules.

### Internal Architecture

The generator employs a classic, multi-stage pipeline based on established compiler theory.

* **Tokenizer & Parser:** A hand-written parser for the `.l` file format and its specific regular expression grammar.
* **AST Construction:** Regular expression rules are converted into an Abstract Syntax Tree (AST) for further processing.
* **Thompson's Construction:** Each AST is transformed into a Nondeterministic Finite Automaton (NFA).
* **Subset Construction:** All individual NFAs are converted into a single, unified Deterministic Finite Automaton (DFA).
* **DFA Minimization:** The resulting DFA is optimized using Moore’s algorithm to reduce its number of states to the minimum possible, ensuring an efficient scanner.
* **Modular Code Generation:** A template-based system generates the final C or Zig source code. The output is modular, including only the logic required for the features used in the source `.l` file.

### Bonus Implementations

This project successfully implements all bonus objectives outlined in the project subject.

* **Polyglotism (Zig Target):** In addition to C, `ft_lex` can generate scanner source code in Zig. This feature is activated with a command-line flag.
* **DFA Compression:** Implements a Triple Array Trie (`base`, `check`, `next`, `default` arrays) to compress the DFA's transition table. This significantly reduces the memory footprint of the generated scanner, especially for complex rule sets.
* **Graph Visualization:** A `-g` flag generates `.dot` files representing the NFA and DFA for each start condition. These files can be visualized using Graphviz, providing invaluable insight into the generated state machines for debugging and educational purposes.

---

## Getting Started

Follow these instructions to build and run `ft_lex` on your local machine.

### Prerequisites

This project is written in Zig. You will need to have the Zig toolchain (version 0.11.0 or later) installed.

* [Zig Installation Guide](https://ziglang.org/learn/getting-started/)

### Installation

1.  Clone the repository:
    ```sh
    git clone https://github.com/pix3l-p33p3r/ft_lex.git && cd ft_lex
    ```
2.  Build the `libl` static library:
    ```sh
    zig build libl
    ```
3.  Build the `ft_lex` executable:
    ```sh
    zig build
    ```
    The executable will be available at `./zig-out/bin/ft_lex`.

---

## Usage

### Generating a Scanner

1.  Create a lexer definition file (e.g., `scanner.l`).
2.  Run `ft_lex` to generate the C source file:
    ```sh
    ./zig-out/bin/ft_lex scanner.l
    ```
3.  Compile the generated scanner with the `libl` library:
    ```sh
    cc -o scanner lex.yy.c src/libl/libl.a
    ```
4.  Run your compiled scanner on an input file:
    ```sh
    ./scanner < input.txt
    ```

### Command-Line Options

To see all available options, run the program with the `--help` flag:

```sh
./zig-out/bin/ft_lex --help
````

The `examples/` directory contains several `.l` files demonstrating various features, including start conditions, `REJECT`, and `yymore()`.

-----

## Performance Considerations

Users should be aware that certain powerful features can have a significant impact on the size and performance of the generated DFA.

  * The use of `REJECT`, `yymore()`, and trailing context (`/`) can lead to a substantial increase in the number of states in the DFA.
  * This is an inherent characteristic of how finite automata handle these features and is consistent with the behavior of other `lex` implementations like `flex`. For performance-critical applications, these features should be used judiciously.

-----

## Project Status

This project is complete. All mandatory requirements of the 1337 school subject have been fulfilled, and all bonus objectives have been successfully implemented and tested.

-----

## References and Acknowledgments

  * [POSIX.1-2024 `lex` Specification](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/lex.html)
  * Aho, Sethi, & Ullman – *Compilers: Principles, Techniques, and Tools* (The Dragon Book)
  * The source code of `flex` was used as a reference for behavior in ambiguous or unspecified cases.
  * This project was completed as part of the advanced UNIX curriculum at 1337 (42 Network).

---